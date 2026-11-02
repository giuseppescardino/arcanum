import 'package:flutter/material.dart';

import '../app/messages.dart';
import '../app/vault_controller.dart';
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

  @override
  void initState() {
    super.initState();
    // Offer biometrics right away, as users expect.
    if (_canUseBiometrics) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _biometrics());
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
            'Sblocca il vault',
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
              decoration: const InputDecoration(
                labelText: 'Secret Key',
                hintText: 'PM1-XXXXXX-XXXXX-XXXXX-XXXXX-XXXXX',
              ),
              validator: (v) => isValidSecretKey(secretKey: v ?? '')
                  ? null
                  : 'Secret Key non valida',
            ),
            const SizedBox(height: 16),
          ],
          PasswordField(
            controller: _password,
            label: 'Master password',
            autofocus: !_askSecretKey,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            validator: (v) =>
                (v ?? '').isEmpty ? 'Inserisci la master password' : null,
          ),
          const SizedBox(height: 24),
          BusyButton(busy: _busy, label: 'Sblocca', onPressed: _submit),
          if (_canUseBiometrics) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.fingerprint),
              label: Text(
                'Sblocca con ${widget.controller.quickUnlock.methodName}',
              ),
              onPressed: _busy ? null : _biometrics,
            ),
          ],
          if (!_askSecretKey) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _askSecretKey = true),
              child: const Text('Inserisci la Secret Key manualmente'),
            ),
          ],
        ],
      ),
    );
  }
}
