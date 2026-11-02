import 'package:flutter/material.dart';

import '../app/messages.dart';
import '../app/vault_controller.dart';
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
            'Crea il tuo vault',
            style: text.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'La master password cifra tutti i tuoi dati sul dispositivo. '
            'Nessuno, nemmeno noi, può recuperarla: sceglila lunga e memorabile.',
            style: text.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ErrorBanner(_error),
          PasswordField(
            controller: _password,
            label: 'Master password',
            autofocus: true,
            textInputAction: TextInputAction.next,
            validator: (v) => (v ?? '').length < minMasterPasswordLength
                ? 'Almeno $minMasterPasswordLength caratteri'
                : null,
          ),
          const SizedBox(height: 16),
          PasswordField(
            controller: _confirm,
            label: 'Ripeti master password',
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            validator: (v) =>
                v != _password.text ? 'Le password non coincidono' : null,
          ),
          const SizedBox(height: 24),
          BusyButton(busy: _busy, label: 'Crea vault', onPressed: _submit),
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
            child: const Text('Ho già un account: accedi'),
          ),
        ],
      ),
    );
  }
}
