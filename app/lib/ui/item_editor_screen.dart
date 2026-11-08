import 'package:flutter/material.dart';

import '../app/breach_check.dart';
import '../app/clipboard.dart';
import '../app/messages.dart';
import '../app/tools.dart';
import '../app/vault_controller.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/vault.dart';
import 'breach_status.dart';
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

  /// With the automatic check on, checks the stored password when the
  /// editor opens and a new one when the field loses focus — never while
  /// typing, so partial passwords don't reach the network.
  void _autoCheckBreach() {
    final checker = BreachScope.maybeOf(context);
    if (checker == null || !checker.enabled) return;
    if (_kind != VaultItemKind.login) return;
    checker.check(_password.text);
  }

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _autoCheckBreach();
    });
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
        title: Text(context.l10n.editorDeleteTitle),
        content: Text(context.l10n.editorDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.delete),
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
        title: Text(
          _isNew ? context.l10n.editorNewTitle : context.l10n.editorEditTitle,
        ),
        actions: [
          IconButton(
            tooltip: _favorite
                ? context.l10n.editorRemoveFavorite
                : context.l10n.editorFavorite,
            icon: Icon(_favorite ? Icons.star : Icons.star_border),
            onPressed: () => setState(() => _favorite = !_favorite),
          ),
          if (!_isNew)
            IconButton(
              tooltip: context.l10n.delete,
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy ? null : _delete,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(context.l10n.editorSave),
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
                    segments: [
                      ButtonSegment(
                        value: VaultItemKind.login,
                        icon: const Icon(Icons.key),
                        label: Text(context.l10n.editorKindLogin),
                      ),
                      ButtonSegment(
                        value: VaultItemKind.secureNote,
                        icon: const Icon(Icons.sticky_note_2_outlined),
                        label: Text(context.l10n.editorKindSecureNote),
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
                  decoration: InputDecoration(
                    labelText: context.l10n.editorTitleLabel,
                  ),
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? context.l10n.editorTitleRequired
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
                      labelText: context.l10n.editorUsernameLabel,
                      suffixIcon: IconButton(
                        tooltip: context.l10n.copy,
                        icon: const Icon(Icons.copy),
                        onPressed: () => copySecret(
                          context,
                          _username.text,
                          label: context.l10n.username,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onFocusChange: (focused) {
                      if (!focused) _autoCheckBreach();
                    },
                    child: PasswordField(
                      controller: _password,
                      label: context.l10n.password,
                      textInputAction: TextInputAction.next,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: context.l10n.editorGenerate,
                            icon: const Icon(Icons.casino_outlined),
                            onPressed: _generate,
                          ),
                          IconButton(
                            tooltip: context.l10n.copy,
                            icon: const Icon(Icons.copy),
                            onPressed: () => copySecret(
                              context,
                              _password.text,
                              label: context.l10n.password,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ValueListenableBuilder(
                    valueListenable: _password,
                    builder: (_, value, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        StrengthMeter(password: value.text),
                        BreachStatus(password: value.text),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _urls,
                    autocorrect: false,
                    keyboardType: TextInputType.multiline,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: context.l10n.editorWebsites,
                      helperText: context.l10n.editorWebsitesHelper,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _totp,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: context.l10n.editorTotpLabel,
                      helperText: context.l10n.editorTotpHelper,
                    ),
                    validator: (v) {
                      final value = (v ?? '').trim();
                      return value.isEmpty || tools.isValidTotp(value)
                          ? null
                          : context.l10n.editorTotpInvalid;
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
                  decoration: InputDecoration(
                    labelText: context.l10n.editorNotes,
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
            decoration: InputDecoration(
              labelText: context.l10n.editorGroup,
              helperText: context.l10n.editorGroupHelper,
              prefixIcon: const Icon(Icons.folder_outlined),
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
