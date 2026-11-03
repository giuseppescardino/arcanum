import 'package:flutter/material.dart';

import '../app/messages.dart';
import '../app/vault_controller.dart';
import '../l10n/l10n.dart';
import 'sign_in_screen.dart';
import 'widgets.dart';

const minMasterPasswordLength = 10;

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.controller});

  final VaultController controller;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.create(_password.text);
    } catch (e) {
      if (mounted) setState(() => _error = failureMessage(e));
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
          const Icon(Icons.shield_outlined, size: 56),
          const SizedBox(height: 16),
          Text(
            context.l10n.setupTitle,
            style: text.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.setupIntro,
            style: text.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ErrorBanner(_error),
          PasswordField(
            controller: _password,
            label: context.l10n.masterPassword,
            autofocus: true,
            textInputAction: TextInputAction.next,
            validator: (v) => (v ?? '').length < minMasterPasswordLength
                ? context.l10n.setupMinLength(minMasterPasswordLength)
                : null,
          ),
          const SizedBox(height: 16),
          PasswordField(
            controller: _confirm,
            label: context.l10n.setupRepeatMasterPassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            validator: (v) =>
                v != _password.text ? context.l10n.passwordsDontMatch : null,
          ),
          const SizedBox(height: 24),
          BusyButton(
            busy: _busy,
            label: context.l10n.setupCreate,
            onPressed: _submit,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          SignInScreen(controller: widget.controller),
                    ),
                  ),
            child: Text(context.l10n.setupHaveAccount),
          ),
        ],
      ),
    );
  }
}
