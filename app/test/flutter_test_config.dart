import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

/// Widget tests look strings up by their Italian text, so the simulated
/// device runs in Italian unless a test picks another language.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized()
      .platformDispatcher
      .localesTestValue = const [
    Locale('it'),
  ];
  await testMain();
}
