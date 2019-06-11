// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'gesture_tester.dart';

void main() {
  setUp(ensureGestureBinding);

  testGesture('A force press can be recognized', (GestureTester tester) {

    // Device specific constants that represent those from the iPhone X
    const double pressureMin = 0;
    const double pressureMax = 6.66;

    // Interpolated Flutter pressure values.
    const double startPressure = 0.4; // = Device pressure of 2.66.
    const double peakPressure = 0.85; // = Device pressure of 5.66.

    int started = 0;
    int peaked = 0;
    int updated = 0;
    int ended = 0;

    Offset startGlobalPosition;

    void onStart(ForcePressDetails details) {
      startGlobalPosition = details.globalPosition;
      started += 1;
    }

    final ForcePressGestureRecognizer force = ForcePressGestureRecognizer(startPressure: startPressure, peakPressure: peakPressure);

    force.onStart = onStart;
    force.onPeak = (ForcePressDetails details) => peaked += 1;
    force.onUpdate = (ForcePressDetails details) => updated += 1;
    force.onEnd = (ForcePressDetails details) => ended += 1;

    const int pointerValue = 1;
    final TestPointer pointer = TestPointer(pointerValue);
    const PointerDownEvent down = PointerDownEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 0, pressureMin: pressureMin, pressureMax: pressureMax);
    pointer.setDownInfo(down, const Offset(10.0, 10.0));
    force.addPointer(down);
    tester.closeArena(pointerValue);

    expect(started, 0);
    expect(peaked, 0);
    expect(updated, 0);
    expect(ended, 0);

    // Pressure fed into the test environment simulates the values received directly from the device.
    tester.route(const PointerMoveEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 2.5, pressureMin: pressureMin, pressureMax: pressureMax));

    // We have not hit the start pressure, so no events should be true.
    expect(started, 0);
    expect(peaked, 0);
    expect(updated, 0);
    expect(ended, 0);

    tester.route(const PointerMoveEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 2.8, pressureMin: pressureMin, pressureMax: pressureMax));

    // We have just hit the start pressure so just the start event should be triggered and one update call should have occurred.
    expect(started, 1);
    expect(peaked, 0);
    expect(updated, 1);
    expect(ended, 0);

    tester.route(const PointerMoveEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 3.3, pressureMin: pressureMin, pressureMax: pressureMax));
    tester.route(const PointerMoveEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 4.0, pressureMin: pressureMin, pressureMax: pressureMax));
    tester.route(const PointerMoveEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 5.0, pressureMin: pressureMin, pressureMax: pressureMax));
    tester.route(const PointerMoveEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 1.0, pressureMin: pressureMin, pressureMax: pressureMax));

    // We have exceeded the start pressure so update should be greater than 0.
    expect(started, 1);
    expect(updated, 5);
    expect(peaked, 0);
    expect(ended, 0);
    expect(startGlobalPosition, const Offset(10.0, 10.0));

    tester.route(const PointerMoveEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 6.0, pressureMin: pressureMin, pressureMax: pressureMax));

    // We have exceeded the peak pressure so peak pressure should be true.
    expect(started, 1);
    expect(updated, 6);
    expect(peaked, 1);
    expect(ended, 0);

    tester.route(const PointerMoveEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 3.3, pressureMin: pressureMin, pressureMax: pressureMax));
    tester.route(const PointerMoveEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 4.0, pressureMin: pressureMin, pressureMax: pressureMax));
    tester.route(const PointerMoveEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 5.0, pressureMin: pressureMin, pressureMax: pressureMax));
    tester.route(const PointerMoveEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 1.0, pressureMin: pressureMin, pressureMax: pressureMax));

    // Update is still called.
    expect(started, 1);
    expect(updated, 10);
    expect(peaked, 1);
    expect(ended, 0);

    tester.route(pointer.up());

    // We have ended the gesture so ended should be true.
    expect(started, 1);
    expect(updated, 10);
    expect(peaked, 1);
    expect(ended, 1);
  });

  testGesture('If minimum pressure is not reached, start and end callbacks are not called', (GestureTester tester) {
    // Device specific constants that represent those from the iPhone X
    const double pressureMin = 0;
    const double pressureMax = 6.66;

    // Interpolated Flutter pressure values.
    const double startPressure = 0.4; // = Device pressure of 2.66.
    const double peakPressure = 0.85; // = Device pressure of 5.66.

    int started = 0;
    int peaked = 0;
    int updated = 0;
    int ended = 0;

    final ForcePressGestureRecognizer force = ForcePressGestureRecognizer(startPressure: startPressure, peakPressure: peakPressure);

    force.onStart = (_) => started += 1;
    force.onPeak = (_) => peaked += 1;
    force.onUpdate = (_) => updated += 1;
    force.onEnd = (_) => ended += 1;

    const int pointerValue = 1;
    final TestPointer pointer = TestPointer(pointerValue);
    const PointerDownEvent down = PointerDownEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 0, pressureMin: pressureMin, pressureMax: pressureMax);
    pointer.setDownInfo(down, const Offset(10.0, 10.0));
    force.addPointer(down);
    tester.closeArena(1);

    expect(started, 0);
    expect(peaked, 0);
    expect(updated, 0);
    expect(ended, 0);

    // Pressure fed into the test environment simulates the values received directly from the device.
    tester.route(const PointerMoveEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 2.5, pressureMin: pressureMin, pressureMax: pressureMax));

    // We have not hit the start pressure, so no events should be true.
    expect(started, 0);
    expect(peaked, 0);
    expect(updated, 0);
    expect(ended, 0);

    tester.route(pointer.up());

    expect(started, 0);
    expect(peaked, 0);
    expect(updated, 0);
    expect(ended, 0);
  });

  testGesture('Should recognize drag and not force touch if there is a drag recognizer', (GestureTester tester) {
    final PanGestureRecognizer drag = PanGestureRecognizer();

    // Device specific constants that represent those from the iPhone X
    const double pressureMin = 0;
    const double pressureMax = 6.66;

    // Interpolated Flutter pressure values.
    const double startPressure = 0.4; // = Device pressure of 2.66.
    const double peakPressure = 0.85; // = Device pressure of 5.66.

    int started = 0;
    int peaked = 0;
    int updated = 0;
    int ended = 0;

    final ForcePressGestureRecognizer force = ForcePressGestureRecognizer(startPressure: startPressure, peakPressure: peakPressure);

    force.onStart = (_) => started += 1;
    force.onPeak = (_) => peaked += 1;
    force.onUpdate = (_) => updated += 1;
    force.onEnd = (_) => ended += 1;

    int didStartPan = 0;
    drag.onStart = (_) => didStartPan += 1;

    const int pointerValue = 1;
    final TestPointer pointer = TestPointer(pointerValue);
    const PointerDownEvent down = PointerDownEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 1.0, pressureMin: pressureMin, pressureMax: pressureMax);
    pointer.setDownInfo(down, const Offset(10.0, 10.0));
    force.addPointer(down);
    drag.addPointer(down);
    tester.closeArena(1);

    expect(started, 0);
    expect(peaked, 0);
    expect(updated, 0);
    expect(ended, 0);
    expect(didStartPan, 0);

    tester.route(pointer.move(const Offset(30.0, 30.0))); // moved 20 horizontally and 20 vertically which is 28 total

    expect(started, 0);
    expect(peaked, 0);
    expect(updated, 0);
    expect(ended, 0);
    expect(didStartPan, 1);

    // Pressure fed into the test environment simulates the values received directly from the device.
    tester.route(const PointerMoveEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 2.5, pressureMin: pressureMin, pressureMax: pressureMax));

    // We have not hit the start pressure, so no events should be true.
    expect(started, 0);
    expect(peaked, 0);
    expect(updated, 0);
    expect(ended, 0);
    expect(didStartPan, 1);

    // We don't expect any events from the force press recognizer.
    tester.route(const PointerMoveEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 4.0, pressureMin: pressureMin, pressureMax: pressureMax));

    expect(started, 0);
    expect(peaked, 0);
    expect(updated, 0);
    expect(ended, 0);
    expect(didStartPan, 1);

    tester.route(pointer.up());

    expect(started, 0);
    expect(peaked, 0);
    expect(updated, 0);
    expect(ended, 0);
    expect(didStartPan, 1);
  });

  testGesture('Should not call ended on pointer up if the gesture was never accepted', (GestureTester tester) {
    final PanGestureRecognizer drag = PanGestureRecognizer();

    // Interpolated Flutter pressure values.
    const double startPressure = 0.4; // = Device pressure of 2.66.
    const double peakPressure = 0.85; // = Device pressure of 5.66.

    // Device specific constants that represent those from the iPhone X
    const double pressureMin = 0;
    const double pressureMax = 6.66;

    int started = 0;
    int peaked = 0;
    int updated = 0;
    int ended = 0;

    final ForcePressGestureRecognizer force = ForcePressGestureRecognizer(startPressure: startPressure, peakPressure: peakPressure);

    force.onStart = (_) => started += 1;
    force.onPeak = (_) => peaked += 1;
    force.onUpdate = (_) => updated += 1;
    force.onEnd = (_) => ended += 1;

    int didStartPan = 0;
    drag.onStart = (_) => didStartPan += 1;

    const int pointerValue = 1;
    final TestPointer pointer = TestPointer(pointerValue);
    const PointerDownEvent down = PointerDownEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 1.0, pressureMin: pressureMin, pressureMax: pressureMax);
    pointer.setDownInfo(down, const Offset(10.0, 10.0));
    force.addPointer(down);
    drag.addPointer(down);
    tester.closeArena(1);

    expect(started, 0);
    expect(peaked, 0);
    expect(updated, 0);
    expect(ended, 0);
    expect(didStartPan, 0);

    tester.route(pointer.up());

    expect(started, 0);
    expect(peaked, 0);
    expect(updated, 0);
    expect(ended, 0);
    expect(didStartPan, 0);
  });

  testGesture('Should call start only once if there is a competing gesture recognizer', (GestureTester tester) {
    final PanGestureRecognizer drag = PanGestureRecognizer();

    // Interpolated Flutter pressure values.
    const double startPressure = 0.4; // = Device pressure of 2.66.
    const double peakPressure = 0.85; // = Device pressure of 5.66.

    // Device specific constants that represent those from the iPhone X
    const double pressureMin = 0;
    const double pressureMax = 6.66;

    int started = 0;
    int peaked = 0;
    int updated = 0;
    int ended = 0;

    final ForcePressGestureRecognizer force = ForcePressGestureRecognizer(startPressure: startPressure, peakPressure: peakPressure);

    force.onStart = (_) => started += 1;
    force.onPeak = (_) => peaked += 1;
    force.onUpdate = (_) => updated += 1;
    force.onEnd = (_) => ended += 1;

    int didStartPan = 0;
    drag.onStart = (_) => didStartPan += 1;

    const int pointerValue = 1;
    final TestPointer pointer = TestPointer(pointerValue);
    const PointerDownEvent down = PointerDownEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 1.0, pressureMin: pressureMin, pressureMax: pressureMax);
    pointer.setDownInfo(down, const Offset(10.0, 10.0));
    force.addPointer(down);
    drag.addPointer(down);
    tester.closeArena(1);

    expect(started, 0);
    expect(peaked, 0);
    expect(updated, 0);
    expect(ended, 0);
    expect(didStartPan, 0);

    // Pressure fed into the test environment simulates the values received directly from the device.
    tester.route(const PointerMoveEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 3.0, pressureMin: pressureMin, pressureMax: pressureMax));

    // We have not hit the start pressure, so no events should be true.
    expect(started, 1);
    expect(peaked, 0);
    expect(updated, 1);
    expect(ended, 0);
    expect(didStartPan, 0);

    tester.route(pointer.up());

    expect(started, 1);
    expect(peaked, 0);
    expect(updated, 1);
    expect(ended, 1);
    expect(didStartPan, 0);
  });

  testGesture('A force press can be recognized with a custom interpolation function', (GestureTester tester) {

    // Device specific constants that represent those from the iPhone X
    const double pressureMin = 0;
    const double pressureMax = 6.66;

    // Interpolated Flutter pressure values.
    const double startPressure = 0.4; // = Device pressure of 2.66.
    const double peakPressure = 0.85; // = Device pressure of 5.66.

    int started = 0;
    int peaked = 0;
    int updated = 0;
    int ended = 0;

    Offset startGlobalPosition;

    void onStart(ForcePressDetails details) {
      startGlobalPosition = details.globalPosition;
      started += 1;
    }

    double interpolateWithEasing(double min, double max, double t) {
      final double lerp = (t - min) / (max - min);
      return Curves.easeIn.transform(lerp);
    }

    final ForcePressGestureRecognizer force = ForcePressGestureRecognizer(startPressure: startPressure, peakPressure: peakPressure, interpolation: interpolateWithEasing);

    force.onStart = onStart;
    force.onPeak = (ForcePressDetails details) => peaked += 1;
    force.onUpdate = (ForcePressDetails details) => updated += 1;
    force.onEnd = (ForcePressDetails details) => ended += 1;

    const int pointerValue = 1;
    final TestPointer pointer = TestPointer(pointerValue);
    const PointerDownEvent down = PointerDownEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 0, pressureMin: pressureMin, pressureMax: pressureMax);
    pointer.setDownInfo(down, const Offset(10.0, 10.0));
    force.addPointer(down);
    tester.closeArena(pointerValue);

    expect(started, 0);
    expect(peaked, 0);
    expect(updated, 0);
    expect(ended, 0);

    // Pressure fed into the test environment simulates the values received directly from the device.
    tester.route(const PointerMoveEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 2.5, pressureMin: pressureMin, pressureMax: pressureMax));

    // We have not hit the start pressure, so no events should be true.
    expect(started, 0);
    expect(peaked, 0);
    expect(updated, 0);
    expect(ended, 0);

    tester.route(const PointerMoveEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 2.8, pressureMin: pressureMin, pressureMax: pressureMax));

    // We have just hit the start pressure so just the start event should be triggered and one update call should have occurred.
    expect(started, 0);
    expect(peaked, 0);
    expect(updated, 0);
    expect(ended, 0);

    tester.route(const PointerMoveEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 3.3, pressureMin: pressureMin, pressureMax: pressureMax));
    expect(started, 0);

    tester.route(const PointerMoveEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 4.0, pressureMin: pressureMin, pressureMax: pressureMax));
    expect(started, 1);

    tester.route(const PointerMoveEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 5.0, pressureMin: pressureMin, pressureMax: pressureMax));
    tester.route(const PointerMoveEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 1.0, pressureMin: pressureMin, pressureMax: pressureMax));

    // We have exceeded the start pressure so update should be greater than 0.
    expect(started, 1);
    expect(updated, 3);
    expect(peaked, 0);
    expect(ended, 0);
    expect(startGlobalPosition, const Offset(10.0, 10.0));

    tester.route(const PointerMoveEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 6.0, pressureMin: pressureMin, pressureMax: pressureMax));

    // We have exceeded the peak pressure so peak pressure should be true.
    expect(started, 1);
    expect(updated, 4);
    expect(peaked, 0);
    expect(ended, 0);

    tester.route(const PointerMoveEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 3.3, pressureMin: pressureMin, pressureMax: pressureMax));
    tester.route(const PointerMoveEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 4.0, pressureMin: pressureMin, pressureMax: pressureMax));
    tester.route(const PointerMoveEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 6.5, pressureMin: pressureMin, pressureMax: pressureMax));
    tester.route(const PointerMoveEvent(pointer: pointerValue, position: Offset(10.0, 10.0), pressure: 1.0, pressureMin: pressureMin, pressureMax: pressureMax));

    // Update is still called.
    expect(started, 1);
    expect(updated, 8);
    expect(peaked, 1);
    expect(ended, 0);

    tester.route(pointer.up());

    // We have ended the gesture so ended should be true.
    expect(started, 1);
    expect(updated, 8);
    expect(peaked, 1);
    expect(ended, 1);
  });
}
