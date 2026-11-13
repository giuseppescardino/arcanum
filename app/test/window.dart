import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phone-sized window: 480 x [height] logical pixels at pixel ratio 1.
void useNarrowWindow(WidgetTester tester, {double height = 900}) =>
    _useWindow(tester, 480, height);

/// Desktop-sized window: 1200 x [height] logical pixels at pixel ratio 1.
void useWideWindow(WidgetTester tester, {double height = 900}) =>
    _useWindow(tester, 1200, height);

void _useWindow(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
