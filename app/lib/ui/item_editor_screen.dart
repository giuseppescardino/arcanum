import 'package:flutter/material.dart';

import '../app/clipboard.dart';
import '../app/messages.dart';
import '../app/tools.dart';
import '../app/vault_controller.dart';
import '../src/rust/api/vault.dart';
import 'generator_dialog.dart';
import 'strength_meter.dart';
import 'totp_view.dart';
import 'widgets.dart';

/// Creates a new item when [item] is null, edits it otherwise.
class ItemEditorScreen extends StatefulWidget {
  const ItemEditorScreen({
    super.key,
    required this.controller,
    this.item,
    this.initialGroup,
  });

  final VaultController controller;
  final VaultItem? item;

  /// Group pre-filled for a new item (the one being browsed).
  final String? initialGroup;

  @override
  State<ItemEditorScreen> createState() => _ItemEditorScreenState();
}

class _ItemEditorScreenState extends State<ItemEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late VaultItemKind _kind;
  late bool _favorite;
  late final TextEditingController _title;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _urls;
  late final TextEditingController _totp;
  late final TextEditingController _notes;
  late final TextEditingController _group;
  bool _busy = false;

  bool get _isNew => widget.item == null;

  @override
  void initState() {
    super.initState();
    final f = widget.item?.fields;
    _kind = f?.kind ?? VaultItemKind.login;
    _favorite = f?.favorite ?? false;
    _title = TextEditingController(text: f?.title);
    _username = TextEditingController(text: f?.username);
    _password = TextEditingController(text: f?.password);
    _urls = TextEditingController(text: f?.urls.join('\n'));
    _totp = TextEditingController(text: f?.totp);
    _notes = TextEditingController(text: f?.notes);
    _group = TextEditingController(text: f?.group ?? widget.initialGroup ?? '');
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _username,
      _password,
      _urls,
      _totp,
      _notes,
      _group,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  ItemFields _fields() {
    final isLogin = _kind == VaultItemKind.login;
    final totp = _totp.text.trim();
    return ItemFields(
      kind: _kind,
      title: _title.text.trim(),
      username: isLogin ? _username.text.trim() : '',
      password: isLogin ? _password.text : '',
      urls: isLogin
          ? _urls.text
                .split('\n')
                .map((u) => u.trim())
                .where((u) => u.isNotEmpty)
                .toList()
          : const [],
      notes: _notes.text,
      totp: isLogin && totp.isNotEmpty ? totp : null,
      favorite: _favorite,
      group: _group.text.trim(),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failureMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generate() async {
    final value = await showPasswordGenerator(context);
    if (value != null) _password.text = value;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await _run(() => widget.controller.save(_fields(), id: widget.item?.id));
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare questo elemento?'),
        content: const Text('L\'operazione non può essere annullata.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => widget.controller.delete(widget.item!.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLogin = _kind == VaultItemKind.login;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Nuovo elemento' : 'Modifica'),
        actions: [
          IconButton(
            tooltip: _favorite ? 'Rimuovi dai preferiti' : 'Preferito',
            icon: Icon(_favorite ? Icons.star : Icons.star_border),
            onPressed: () => setState(() => _favorite = !_favorite),
          ),
          if (!_isNew)
            IconButton(
              tooltip: 'Elimina',
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy ? null : _delete,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('Salva'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_isNew) ...[
                  SegmentedButton<VaultItemKind>(
                    segments: const [
                      ButtonSegment(
                        value: VaultItemKind.login,
                        icon: Icon(Icons.key),
                        label: Text('Login'),
                      ),
                      ButtonSegment(
                        value: VaultItemKind.secureNote,
                        icon: Icon(Icons.sticky_note_2_outlined),
                        label: Text('Nota sicura'),
                      ),
                    ],
                    selected: {_kind},
                    onSelectionChanged: (s) => setState(() => _kind = s.first),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _title,
                  autofocus: _isNew,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Titolo'),
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? 'Il titolo è obbligatorio'
                      : null,
                ),
                const SizedBox(height: 16),
                GroupField(
                  controller: _group,
                  groups: widget.controller.groups,
                ),
                if (isLogin) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _username,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Nome utente / email',
                      suffixIcon: IconButton(
                        tooltip: 'Copia',
                        icon: const Icon(Icons.copy),
                        onPressed: () => copySecret(
                          context,
                          _username.text,
                          label: 'Nome utente',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  PasswordField(
                    controller: _password,
                    label: 'Password',
                    textInputAction: TextInputAction.next,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Genera',
                          icon: const Icon(Icons.casino_outlined),
                          onPressed: _generate,
                        ),
                        IconButton(
                          tooltip: 'Copia',
                          icon: const Icon(Icons.copy),
                          onPressed: () => copySecret(
                            context,
                            _password.text,
                            label: 'Password',
                          ),
                        ),
                      ],
                    ),
                  ),
                  ValueListenableBuilder(
                    valueListenable: _password,
                    builder: (_, value, _) =>
                        StrengthMeter(password: value.text),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _urls,
                    autocorrect: false,
                    keyboardType: TextInputType.multiline,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Siti web',
                      helperText: 'Uno per riga',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _totp,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Chiave 2FA (TOTP)',
                      helperText: 'Chiave segreta o URI otpauth:// del sito',
                    ),
                    validator: (v) {
                      final value = (v ?? '').trim();
                      return value.isEmpty || tools.isValidTotp(value)
                          ? null
                          : 'Chiave 2FA non valida';
                    },
                  ),
                  ValueListenableBuilder(
                    valueListenable: _totp,
                    builder: (_, value, _) {
                      final secret = value.text.trim();
                      if (secret.isEmpty || !tools.isValidTotp(secret)) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TotpView(secret: secret),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notes,
                  keyboardType: TextInputType.multiline,
                  minLines: isLogin ? 3 : 10,
                  maxLines: null,
                  decoration: const InputDecoration(
                    labelText: 'Note',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Free-text group name with suggestions from the groups already in use.
class GroupField extends StatefulWidget {
  const GroupField({super.key, required this.controller, required this.groups});

  final TextEditingController controller;
  final List<String> groups;

  @override
  State<GroupField> createState() => _GroupFieldState();
}

class _GroupFieldState extends State<GroupField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        return widget.groups.where(
          (g) => g.toLowerCase().contains(q) && g.toLowerCase() != q,
        );
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
          TextFormField(
            controller: controller,
            focusNode: focusNode,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => onSubmitted(),
            decoration: const InputDecoration(
              labelText: 'Gruppo',
              helperText: 'Scegline uno esistente o scrivine uno nuovo',
              prefixIcon: Icon(Icons.folder_outlined),
            ),
          ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 400),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final g in options)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(g),
                    onTap: () => onSelected(g),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
