import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/background_mode.dart';
import '../app/breach_check.dart';
import '../app/favicons.dart';
import '../app/language_settings.dart';
import '../app/vault_controller.dart';
import '../browser/bridge_server.dart';
import '../l10n/l10n.dart';
import 'browser_pairing.dart';
import 'emergency_kit_screen.dart';
import 'setup_screen.dart';
import 'theme.dart';
import 'unlock_screen.dart';
import 'vault_screen.dart';

class ArcanumApp extends StatefulWidget {
  ArcanumApp({
    super.key,
    required this.controller,
    LanguageSettings? language,
    BreachChecker? breach,
    FaviconCache? favicons,
    this.bridge,
    this.background,
  }) : language = language ?? LanguageSettings(),
       breach = breach ?? BreachChecker(),
       favicons = favicons ?? FaviconCache.disabled();

  final VaultController controller;
  final LanguageSettings language;
  final BreachChecker breach;
  final FaviconCache favicons;

  /// Browser extension server; null where it does not run (mobile).
  final BridgeServer? bridge;

  /// Tray and launch at login; null where they do not apply (mobile).
  final BackgroundMode? background;

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
        if (_isMobile && _controller.locksOnPause) _controller.lock();
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
      // Breach results name vault passwords: forget them when locked.
      if (_lastStage != VaultStage.unlocked) {
        widget.breach.clear();
        // Icons tell which sites are in the vault.
        widget.favicons.clear();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LanguageScope(
      settings: widget.language,
      child: BreachScope(
        checker: widget.breach,
        child: FaviconScope(
          cache: widget.favicons,
          child: _withBridge(
            ListenableBuilder(
              listenable: Listenable.merge([_controller, widget.language]),
              builder: (context, _) => MaterialApp(
                title: 'Arcanum',
                navigatorKey: _navigatorKey,
                debugShowCheckedModeBanner: false,
                theme: appTheme(Brightness.light),
                darkTheme: appTheme(Brightness.dark),
                locale: widget.language.locale,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                builder: (context, child) {
                  trackLocale(context);
                  return Listener(
                    onPointerDown: (_) => _controller.touch(),
                    child: child,
                  );
                },
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _withBridge(Widget child) {
    final bridge = widget.bridge;
    final background = widget.background;
    if (background != null) {
      child = BackgroundScope(mode: background, child: child);
    }
    return bridge == null ? child : BridgeScope(server: bridge, child: child);
  }
}
