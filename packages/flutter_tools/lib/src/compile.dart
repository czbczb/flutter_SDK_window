// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:usage/uuid/uuid.dart';

import 'artifacts.dart';
import 'base/common.dart';
import 'base/context.dart';
import 'base/file_system.dart';
import 'base/fingerprint.dart';
import 'base/io.dart';
import 'base/platform.dart';
import 'base/process_manager.dart';
import 'base/terminal.dart';
import 'convert.dart';
import 'dart/package_map.dart';
import 'globals.dart';

KernelCompilerFactory get kernelCompilerFactory => context[KernelCompilerFactory];

typedef CompilerMessageConsumer = void Function(String message, {bool emphasis, TerminalColor color});

/// Injectable factory to allow async construction of a [KernelCompiler].
class KernelCompilerFactory {
  const KernelCompilerFactory();

  /// Return the correct [KernelCompiler] instance for the given project
  /// configuration.
  FutureOr<KernelCompiler> create() async {
    return const KernelCompiler();
  }
}

/// The target model describes the set of core libraries that are availible within
/// the SDK.
class TargetModel {
  /// Parse a [TargetModel] from a raw string.
  ///
  /// Throws an [AssertionError] if passed a value other than 'flutter' or
  /// 'flutter_runner'.
  factory TargetModel(String rawValue) {
    switch (rawValue) {
      case 'flutter':
        return flutter;
      case 'flutter_runner':
        return flutterRunner;
    }
    assert(false);
    return null;
  }

  const TargetModel._(this._value);

  /// The flutter patched dart SDK
  static const TargetModel flutter = TargetModel._('flutter');

  /// The fuchsia patched SDK.
  static const TargetModel flutterRunner = TargetModel._('flutter_runner');

  final String _value;

  @override
  String toString() => _value;
}

class CompilerOutput {
  const CompilerOutput(this.outputFilename, this.errorCount);

  final String outputFilename;
  final int errorCount;
}

/// Handles stdin/stdout communication with the frontend server.
class StdoutHandler {
  StdoutHandler({this.consumer = printError}) {
    reset();
  }

  bool compilerMessageReceived = false;
  final CompilerMessageConsumer consumer;
  String boundaryKey;
  Completer<CompilerOutput> compilerOutput;

  bool _suppressCompilerMessages;

  void handler(String message) {
    const String kResultPrefix = 'result ';
    if (boundaryKey == null && message.startsWith(kResultPrefix)) {
        boundaryKey = message.substring(kResultPrefix.length);
    } else if (message.startsWith(boundaryKey)) {
      if (message.length <= boundaryKey.length) {
        compilerOutput.complete(null);
        return;
      }
      final int spaceDelimiter = message.lastIndexOf(' ');
      compilerOutput.complete(
        CompilerOutput(
          message.substring(boundaryKey.length + 1, spaceDelimiter),
          int.parse(message.substring(spaceDelimiter + 1).trim())));
    } else if (!_suppressCompilerMessages) {
      if (compilerMessageReceived == false) {
        consumer('\nCompiler message:');
        compilerMessageReceived = true;
      }
      consumer(message);
    }
  }

  // This is needed to get ready to process next compilation result output,
  // with its own boundary key and new completer.
  void reset({bool suppressCompilerMessages = false}) {
    boundaryKey = null;
    compilerMessageReceived = false;
    compilerOutput = Completer<CompilerOutput>();
    _suppressCompilerMessages = suppressCompilerMessages;
  }
}

/// Converts filesystem paths to package URIs.
class PackageUriMapper {
  PackageUriMapper(String scriptPath, String packagesPath, String fileSystemScheme, List<String> fileSystemRoots) {
    final Map<String, Uri> packageMap = PackageMap(fs.path.absolute(packagesPath)).map;
    final String scriptUri = Uri.file(scriptPath, windows: platform.isWindows).toString();

    for (String packageName in packageMap.keys) {
      final String prefix = packageMap[packageName].toString();
      if (fileSystemScheme != null && fileSystemRoots != null && prefix.contains(fileSystemScheme)) {
        _packageName = packageName;
        _uriPrefixes = fileSystemRoots
          .map((String name) => Uri.file(name, windows: platform.isWindows).toString())
          .toList();
        return;
      }
      if (scriptUri.startsWith(prefix)) {
        _packageName = packageName;
        _uriPrefixes = <String>[prefix];
        return;
      }
    }
  }

  String _packageName;
  List<String> _uriPrefixes;

  Uri map(String scriptPath) {
    if (_packageName == null) {
      return null;
    }
    final String scriptUri = Uri.file(scriptPath, windows: platform.isWindows).toString();
    for (String uriPrefix in _uriPrefixes) {
      if (scriptUri.startsWith(uriPrefix)) {
        return Uri.parse('package:$_packageName/${scriptUri.substring(uriPrefix.length)}');
      }
    }
    return null;
  }

  static Uri findUri(String scriptPath, String packagesPath, String fileSystemScheme, List<String> fileSystemRoots) {
    return PackageUriMapper(scriptPath, packagesPath, fileSystemScheme, fileSystemRoots).map(scriptPath);
  }
}

class KernelCompiler {
  const KernelCompiler();

  Future<CompilerOutput> compile({
    String sdkRoot,
    String mainPath,
    String outputFilePath,
    String depFilePath,
    TargetModel targetModel = TargetModel.flutter,
    bool linkPlatformKernelIn = false,
    bool aot = false,
    @required bool trackWidgetCreation,
    List<String> extraFrontEndOptions,
    String incrementalCompilerByteStorePath,
    String packagesPath,
    List<String> fileSystemRoots,
    String fileSystemScheme,
    bool targetProductVm = false,
  }) async {
    final String frontendServer = artifacts.getArtifactPath(
      Artifact.frontendServerSnapshotForEngineDartSdk
    );

    // TODO(cbracken): eliminate pathFilter.
    // Currently the compiler emits buildbot paths for the core libs in the
    // depfile. None of these are available on the local host.
    Fingerprinter fingerprinter;
    if (depFilePath != null) {
      fingerprinter = Fingerprinter(
        fingerprintPath: '$depFilePath.fingerprint',
        paths: <String>[mainPath],
        properties: <String, String>{
          'entryPoint': mainPath,
          'trackWidgetCreation': trackWidgetCreation.toString(),
          'linkPlatformKernelIn': linkPlatformKernelIn.toString(),
        },
        depfilePaths: <String>[depFilePath],
        pathFilter: (String path) => !path.startsWith('/b/build/slave/'),
      );

      if (await fingerprinter.doesFingerprintMatch()) {
        printTrace('Skipping kernel compilation. Fingerprint match.');
        return CompilerOutput(outputFilePath, 0);
      }
    }

    // This is a URI, not a file path, so the forward slash is correct even on Windows.
    if (!sdkRoot.endsWith('/'))
      sdkRoot = '$sdkRoot/';
    final String engineDartPath = artifacts.getArtifactPath(Artifact.engineDartBinary);
    if (!processManager.canRun(engineDartPath)) {
      throwToolExit('Unable to find Dart binary at $engineDartPath');
    }
    final List<String> command = <String>[
      engineDartPath,
      frontendServer,
      '--sdk-root',
      sdkRoot,
      '--strong',
      '--target=$targetModel',
    ];
    if (trackWidgetCreation)
      command.add('--track-widget-creation');
    if (!linkPlatformKernelIn)
      command.add('--no-link-platform');
    if (aot) {
      command.add('--aot');
      command.add('--tfa');
    }
    if (targetProductVm) {
      command.add('-Ddart.vm.product=true');
    }
    if (incrementalCompilerByteStorePath != null) {
      command.add('--incremental');
    }
    Uri mainUri;
    if (packagesPath != null) {
      command.addAll(<String>['--packages', packagesPath]);
      mainUri = PackageUriMapper.findUri(mainPath, packagesPath, fileSystemScheme, fileSystemRoots);
    }
    if (outputFilePath != null) {
      command.addAll(<String>['--output-dill', outputFilePath]);
    }
    if (depFilePath != null && (fileSystemRoots == null || fileSystemRoots.isEmpty)) {
      command.addAll(<String>['--depfile', depFilePath]);
    }
    if (fileSystemRoots != null) {
      for (String root in fileSystemRoots) {
        command.addAll(<String>['--filesystem-root', root]);
      }
    }
    if (fileSystemScheme != null) {
      command.addAll(<String>['--filesystem-scheme', fileSystemScheme]);
    }

    if (extraFrontEndOptions != null)
      command.addAll(extraFrontEndOptions);

    command.add(mainUri?.toString() ?? mainPath);

    printTrace(command.join(' '));
    final Process server = await processManager
        .start(command)
        .catchError((dynamic error, StackTrace stack) {
      printError('Failed to start frontend server $error, $stack');
    });

    final StdoutHandler _stdoutHandler = StdoutHandler();

    server.stderr
      .transform<String>(utf8.decoder)
      .listen(printError);
    server.stdout
      .transform<String>(utf8.decoder)
      .transform<String>(const LineSplitter())
      .listen(_stdoutHandler.handler);
    final int exitCode = await server.exitCode;
    if (exitCode == 0) {
      if (fingerprinter != null) {
        await fingerprinter.writeFingerprint();
      }
      return _stdoutHandler.compilerOutput.future;
    }
    return null;
  }
}

/// Class that allows to serialize compilation requests to the compiler.
abstract class _CompilationRequest {
  _CompilationRequest(this.completer);

  Completer<CompilerOutput> completer;

  Future<CompilerOutput> _run(ResidentCompiler compiler);

  Future<void> run(ResidentCompiler compiler) async {
    completer.complete(await _run(compiler));
  }
}

class _RecompileRequest extends _CompilationRequest {
  _RecompileRequest(
    Completer<CompilerOutput> completer,
    this.mainPath,
    this.invalidatedFiles,
    this.outputPath,
    this.packagesFilePath,
  ) : super(completer);

  String mainPath;
  List<String> invalidatedFiles;
  String outputPath;
  String packagesFilePath;

  @override
  Future<CompilerOutput> _run(ResidentCompiler compiler) async =>
      compiler._recompile(this);
}

class _CompileExpressionRequest extends _CompilationRequest {
  _CompileExpressionRequest(
    Completer<CompilerOutput> completer,
    this.expression,
    this.definitions,
    this.typeDefinitions,
    this.libraryUri,
    this.klass,
    this.isStatic
  ) : super(completer);

  String expression;
  List<String> definitions;
  List<String> typeDefinitions;
  String libraryUri;
  String klass;
  bool isStatic;

  @override
  Future<CompilerOutput> _run(ResidentCompiler compiler) async =>
      compiler._compileExpression(this);
}

class _RejectRequest extends _CompilationRequest {
  _RejectRequest(Completer<CompilerOutput> completer): super(completer);

  @override
  Future<CompilerOutput> _run(ResidentCompiler compiler) async =>
      compiler._reject();
}

/// Wrapper around incremental frontend server compiler, that communicates with
/// server via stdin/stdout.
///
/// The wrapper is intended to stay resident in memory as user changes, reloads,
/// restarts the Flutter app.
class ResidentCompiler {
  ResidentCompiler(this._sdkRoot, {
    bool trackWidgetCreation = false,
    String packagesPath,
    List<String> fileSystemRoots,
    String fileSystemScheme,
    CompilerMessageConsumer compilerMessageConsumer = printError,
    String initializeFromDill,
    TargetModel targetModel = TargetModel.flutter,
    bool unsafePackageSerialization,
    List<String> experimentalFlags,
  }) : assert(_sdkRoot != null),
       _trackWidgetCreation = trackWidgetCreation,
       _packagesPath = packagesPath,
       _fileSystemRoots = fileSystemRoots,
       _fileSystemScheme = fileSystemScheme,
       _targetModel = targetModel,
       _stdoutHandler = StdoutHandler(consumer: compilerMessageConsumer),
       _controller = StreamController<_CompilationRequest>(),
       _initializeFromDill = initializeFromDill,
       _unsafePackageSerialization = unsafePackageSerialization,
       _experimentalFlags = experimentalFlags {
    // This is a URI, not a file path, so the forward slash is correct even on Windows.
    if (!_sdkRoot.endsWith('/'))
      _sdkRoot = '$_sdkRoot/';
  }

  final bool _trackWidgetCreation;
  final String _packagesPath;
  final TargetModel _targetModel;
  final List<String> _fileSystemRoots;
  final String _fileSystemScheme;
  String _sdkRoot;
  Process _server;
  final StdoutHandler _stdoutHandler;
  String _initializeFromDill;
  bool _unsafePackageSerialization;
  final List<String> _experimentalFlags;
  bool _compileRequestNeedsConfirmation = false;

  final StreamController<_CompilationRequest> _controller;

  /// If invoked for the first time, it compiles Dart script identified by
  /// [mainPath], [invalidatedFiles] list is ignored.
  /// On successive runs [invalidatedFiles] indicates which files need to be
  /// recompiled. If [mainPath] is [null], previously used [mainPath] entry
  /// point that is used for recompilation.
  /// Binary file name is returned if compilation was successful, otherwise
  /// null is returned.
  Future<CompilerOutput> recompile(String mainPath, List<String> invalidatedFiles,
      {@required String outputPath, String packagesFilePath}) async {
    assert (outputPath != null);
    if (!_controller.hasListener) {
      _controller.stream.listen(_handleCompilationRequest);
    }

    final Completer<CompilerOutput> completer = Completer<CompilerOutput>();
    _controller.add(
        _RecompileRequest(completer, mainPath, invalidatedFiles, outputPath, packagesFilePath)
    );
    return completer.future;
  }

  Future<CompilerOutput> _recompile(_RecompileRequest request) async {
    _stdoutHandler.reset();

    // First time recompile is called we actually have to compile the app from
    // scratch ignoring list of invalidated files.
    PackageUriMapper packageUriMapper;
    if (request.packagesFilePath != null || _packagesPath != null) {
      packageUriMapper = PackageUriMapper(
        request.mainPath,
        request.packagesFilePath ?? _packagesPath,
        _fileSystemScheme,
        _fileSystemRoots,
      );
    }

    _compileRequestNeedsConfirmation = true;

    if (_server == null) {
      return _compile(
          _mapFilename(request.mainPath, packageUriMapper),
          request.outputPath,
          _mapFilename(request.packagesFilePath ?? _packagesPath, /* packageUriMapper= */ null)
      );
    }

    final String inputKey = Uuid().generateV4();
    final String mainUri = request.mainPath != null
        ? _mapFilename(request.mainPath, packageUriMapper) + ' '
        : '';
    _server.stdin.writeln('recompile $mainUri$inputKey');
    for (String fileUri in request.invalidatedFiles) {
      _server.stdin.writeln(_mapFileUri(fileUri, packageUriMapper));
    }
    _server.stdin.writeln(inputKey);

    return _stdoutHandler.compilerOutput.future;
  }

  final List<_CompilationRequest> _compilationQueue = <_CompilationRequest>[];

  Future<void> _handleCompilationRequest(_CompilationRequest request) async {
    final bool isEmpty = _compilationQueue.isEmpty;
    _compilationQueue.add(request);
    // Only trigger processing if queue was empty - i.e. no other requests
    // are currently being processed. This effectively enforces "one
    // compilation request at a time".
    if (isEmpty) {
      while (_compilationQueue.isNotEmpty) {
        final _CompilationRequest request = _compilationQueue.first;
        await request.run(this);
        _compilationQueue.removeAt(0);
      }
    }
  }

  Future<CompilerOutput> _compile(String scriptUri, String outputPath,
      String packagesFilePath) async {
    final String frontendServer = artifacts.getArtifactPath(
      Artifact.frontendServerSnapshotForEngineDartSdk
    );
    final List<String> command = <String>[
      artifacts.getArtifactPath(Artifact.engineDartBinary),
      frontendServer,
      '--sdk-root',
      _sdkRoot,
      '--incremental',
      '--strong',
      '--target=$_targetModel',
    ];
    if (outputPath != null) {
      command.addAll(<String>['--output-dill', outputPath]);
    }
    if (packagesFilePath != null) {
      command.addAll(<String>['--packages', packagesFilePath]);
    }
    if (_trackWidgetCreation) {
      command.add('--track-widget-creation');
    }
    if (_packagesPath != null) {
      command.addAll(<String>['--packages', _packagesPath]);
    }
    if (_fileSystemRoots != null) {
      for (String root in _fileSystemRoots) {
        command.addAll(<String>['--filesystem-root', root]);
      }
    }
    if (_fileSystemScheme != null) {
      command.addAll(<String>['--filesystem-scheme', _fileSystemScheme]);
    }
    if (_initializeFromDill != null) {
      command.addAll(<String>['--initialize-from-dill', _initializeFromDill]);
    }
    if (_unsafePackageSerialization == true) {
      command.add('--unsafe-package-serialization');
    }
    if ((_experimentalFlags != null) && _experimentalFlags.isNotEmpty) {
      final String expFlags = _experimentalFlags.join(',');
      command.add('--enable-experiment=$expFlags');
    }
    printTrace(command.join(' '));
    _server = await processManager.start(command);
    _server.stdout
      .transform<String>(utf8.decoder)
      .transform<String>(const LineSplitter())
      .listen(
        _stdoutHandler.handler,
        onDone: () {
          // when outputFilename future is not completed, but stdout is closed
          // process has died unexpectedly.
          if (!_stdoutHandler.compilerOutput.isCompleted) {
            _stdoutHandler.compilerOutput.complete(null);
          }
        });

    _server.stderr
      .transform<String>(utf8.decoder)
      .transform<String>(const LineSplitter())
      .listen((String message) { printError(message); });

    _server.stdin.writeln('compile $scriptUri');

    return _stdoutHandler.compilerOutput.future;
  }

  Future<CompilerOutput> compileExpression(String expression, List<String> definitions,
      List<String> typeDefinitions, String libraryUri, String klass, bool isStatic) {
    if (!_controller.hasListener) {
      _controller.stream.listen(_handleCompilationRequest);
    }

    final Completer<CompilerOutput> completer = Completer<CompilerOutput>();
    _controller.add(
        _CompileExpressionRequest(
            completer, expression, definitions, typeDefinitions, libraryUri, klass, isStatic)
    );
    return completer.future;
  }

  Future<CompilerOutput> _compileExpression(
      _CompileExpressionRequest request) async {
    _stdoutHandler.reset(suppressCompilerMessages: true);

    // 'compile-expression' should be invoked after compiler has been started,
    // program was compiled.
    if (_server == null)
      return null;

    final String inputKey = Uuid().generateV4();
    _server.stdin.writeln('compile-expression $inputKey');
    _server.stdin.writeln(request.expression);
    request.definitions?.forEach(_server.stdin.writeln);
    _server.stdin.writeln(inputKey);
    request.typeDefinitions?.forEach(_server.stdin.writeln);
    _server.stdin.writeln(inputKey);
    _server.stdin.writeln(request.libraryUri ?? '');
    _server.stdin.writeln(request.klass ?? '');
    _server.stdin.writeln(request.isStatic ?? false);

    return _stdoutHandler.compilerOutput.future;
  }

  /// Should be invoked when results of compilation are accepted by the client.
  ///
  /// Either [accept] or [reject] should be called after every [recompile] call.
  void accept() {
    if (_compileRequestNeedsConfirmation) {
      _server.stdin.writeln('accept');
    }
    _compileRequestNeedsConfirmation = false;
  }

  /// Should be invoked when results of compilation are rejected by the client.
  ///
  /// Either [accept] or [reject] should be called after every [recompile] call.
  Future<CompilerOutput> reject() {
    if (!_controller.hasListener) {
      _controller.stream.listen(_handleCompilationRequest);
    }

    final Completer<CompilerOutput> completer = Completer<CompilerOutput>();
    _controller.add(_RejectRequest(completer));
    return completer.future;
  }

  Future<CompilerOutput> _reject() {
    if (!_compileRequestNeedsConfirmation) {
      return Future<CompilerOutput>.value(null);
    }
    _stdoutHandler.reset();
    _server.stdin.writeln('reject');
    _compileRequestNeedsConfirmation = false;
    return _stdoutHandler.compilerOutput.future;
  }

  /// Should be invoked when frontend server compiler should forget what was
  /// accepted previously so that next call to [recompile] produces complete
  /// kernel file.
  void reset() {
    _server?.stdin?.writeln('reset');
  }

  String _mapFilename(String filename, PackageUriMapper packageUriMapper) {
    return _doMapFilename(filename, packageUriMapper) ?? filename;
  }

  String _mapFileUri(String fileUri, PackageUriMapper packageUriMapper) {
    String filename;
    try {
      filename = Uri.parse(fileUri).toFilePath();
    } on UnsupportedError catch (_) {
      return fileUri;
    }
    return _doMapFilename(filename, packageUriMapper) ?? fileUri;
  }

  String _doMapFilename(String filename, PackageUriMapper packageUriMapper) {
    if (packageUriMapper != null) {
      final Uri packageUri = packageUriMapper.map(filename);
      if (packageUri != null)
        return packageUri.toString();
    }

    if (_fileSystemRoots != null) {
      for (String root in _fileSystemRoots) {
        if (filename.startsWith(root)) {
          return Uri(
              scheme: _fileSystemScheme, path: filename.substring(root.length))
              .toString();
        }
      }
    }
    return null;
  }

  Future<dynamic> shutdown() {
    _server.kill();
    return _server.exitCode;
  }
}
