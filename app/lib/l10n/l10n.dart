import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Locale the UI is currently shown in; kept up to date by the root
/// widgets (see [trackLocale]).
Locale? _currentLocale;

/// Strings for code that has no [BuildContext] (controller, error mapping).
/// Before any UI is built it follows the device languages.
AppLocalizations get l10n => lookupAppLocalizations(
  _currentLocale ??
      basicLocaleListResolution(
        WidgetsBinding.instance.platformDispatcher.locales,
        AppLocalizations.supportedLocales,
      ),
);

/// Called from `MaterialApp.builder`, below the app's [Localizations].
void trackLocale(BuildContext context) {
  _currentLocale = Localizations.localeOf(context);
}
