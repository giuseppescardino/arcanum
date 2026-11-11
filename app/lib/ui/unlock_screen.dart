import 'package:flutter/material.dart';

import '../app/messages.dart';
import '../app/vault_controller.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/vault.dart';
import 'widgets.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key, required this.controller});

  final VaultController controller;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _secretKey = TextEditingController();
  late bool _askSecretKey = !widget.controller.hasStoredSecretKey;
  bool _busy = false;
  String? _error;

  bool get _canUseBiometrics =>
      widget.controller.quickUnlockEnabled &&
      widget.controller.quickUnlockAvailable &&
      !_askSecretKey;

  late final AppLifecycleListener _lifecycle;

  /// Set while the app is in the background: the system refuses the
  /// biometric prompt there, so it is shown when the app comes back.
  bool _promptOnResume = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      // Only a real trip to the background (hidden), not the inactive
      // state the Face ID sheet itself causes, or a cancel would loop.
      onHide: () => _promptOnResume = true,
      onResume: () {
        if (!_promptOnResume) return;
        _promptOnResume = false;
        if (_canUseBiometrics) _biometrics();
      },
    );
    // Offer biometrics right away, as users expect. On mobile this screen
    // is usually built while the app is still coming back (leaving the app
    // locks the vault): the prompt would fail, so wait until it is active.
    if (_canUseBiometrics) {
      switch (WidgetsBinding.instance.lifecycleState) {
        case null || AppLifecycleState.resumed:
          WidgetsBinding.instance.addPostFrameCallback((_) => _biometrics());
        case _:
          _promptOnResume = true;
      }
    }
  }

  Future<void> _biometrics() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.unlockWithBiometrics();
    } catch (e) {
      if (mounted) setState(() => _error = failureMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _password.dispose();
    _secretKey.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.unlock(
        _password.text,
        secretKey: _askSecretKey ? _secretKey.text.trim() : null,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = failureMessage(e));
        _password.clear();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Form(
      key: _formKey,
      child: NarrowPage(
        children: [
          const Icon(Icons.lock_outline, size: 56),
          const SizedBox(height: 16),
          Text(
            context.l10n.unlockTitle,
            style: text.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ErrorBanner(_error),
          if (_askSecretKey) ...[
            TextFormField(
              controller: _secretKey,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontFamily: 'monospace'),
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: context.l10n.secretKey,
                hintText: 'PM1-XXXXXX-XXXXX-XXXXX-XXXXX-XXXXX',
              ),
              validator: (v) => isValidSecretKey(secretKey: v ?? '')
                  ? null
                  : context.l10n.commonInvalidSecretKey,
            ),
            const SizedBox(height: 16),
          ],
          PasswordField(
            controller: _password,
            label: context.l10n.masterPassword,
            autofocus: !_askSecretKey,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            validator: (v) => (v ?? '').isEmpty
                ? context.l10n.commonEnterMasterPassword
                : null,
          ),
          const SizedBox(height: 24),
          BusyButton(
            busy: _busy,
            label: context.l10n.unlockButton,
            onPressed: _submit,
          ),
          if (_canUseBiometrics) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.fingerprint),
              label: Text(
                context.l10n.unlockWithMethod(
                  widget.controller.quickUnlock.methodName,
                ),
              ),
              onPressed: _busy ? null : _biometrics,
            ),
          ],
          if (!_askSecretKey) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _askSecretKey = true),
              child: Text(context.l10n.unlockEnterSecretKeyManually),
            ),
          ],
        ],
      ),
    );
  }
}
