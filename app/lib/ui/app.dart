import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/vault_controller.dart';
import 'emergency_kit_screen.dart';
import 'setup_screen.dart';
import 'theme.dart';
import 'unlock_screen.dart';
import 'vault_screen.dart';

class ArcanumApp extends StatefulWidget {
  const ArcanumApp({super.key, required this.controller});

  final VaultController controller;

  @override
  State<ArcanumApp> createState() => _ArcanumAppState();
}

class _ArcanumAppState extends State<ArcanumApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final AppLifecycleListener _lifecycle;
  late VaultStage _lastStage;

  VaultController get _controller => widget.controller;

  bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    _lastStage = _controller.stage;
    _controller.addListener(_onStageChanged);
    HardwareKeyboard.instance.addHandler(_onKey);
    _lifecycle = AppLifecycleListener(
      // On mobile, leaving the app locks the vault immediately.
      onPause: () {
        if (_isMobile) _controller.lock();
      },
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onStageChanged);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _lifecycle.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    _controller.touch();
    return false;
  }

  /// When the vault locks, drop every pushed route (e.g. an open editor)
  /// so no decrypted data stays on screen.
  void _onStageChanged() {
    if (_controller.stage != _lastStage) {
      _lastStage = _controller.stage;
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => MaterialApp(
        title: 'Arcanum',
        navigatorKey: _navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: appTheme(Brightness.light),
        darkTheme: appTheme(Brightness.dark),
        builder: (context, child) =>
            Listener(onPointerDown: (_) => _controller.touch(), child: child),
        home: KeyedSubtree(
          key: ValueKey(_controller.stage),
          child: switch (_controller.stage) {
            VaultStage.setup => SetupScreen(controller: _controller),
            VaultStage.emergencyKit => EmergencyKitScreen(
              controller: _controller,
            ),
            VaultStage.locked => UnlockScreen(controller: _controller),
            VaultStage.unlocked => VaultScreen(controller: _controller),
          },
        ),
      ),
    );
  }
}
