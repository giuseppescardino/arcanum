import 'package:flutter/material.dart';

import '../app/messages.dart';
import '../app/vault_controller.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/vault.dart';
import 'widgets.dart';

/// Sets up this device from an existing account on a sync server.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.controller});

  final VaultController controller;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _server = TextEditingController();
  final _secretKey = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_server, _secretKey, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // On success the app switches to the unlocked vault and pops this
      // route by itself.
      await widget.controller.signIn(
        serverUrl: _server.text.trim(),
        password: _password.text,
        secretKey: _secretKey.text.trim(),
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
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.signInTitle)),
      body: Form(
        key: _formKey,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(context.l10n.signInIntro, style: text.bodyMedium),
                  const SizedBox(height: 24),
                  ErrorBanner(_error),
                  ServerUrlField(controller: _server, autofocus: true),
                  const SizedBox(height: 16),
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
                  PasswordField(
                    controller: _password,
                    label: context.l10n.masterPassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    validator: (v) => (v ?? '').isEmpty
                        ? context.l10n.commonEnterMasterPassword
                        : null,
                  ),
                  const SizedBox(height: 24),
                  BusyButton(
                    busy: _busy,
                    label: context.l10n.signInTitle,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
