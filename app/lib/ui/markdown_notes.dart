import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/markdown_format.dart';
import '../l10n/l10n.dart';

/// Notes field written in Markdown: an editor with a formatting toolbar
/// and a rendered preview, switched with a segmented button.
class MarkdownNotesField extends StatefulWidget {
  const MarkdownNotesField({
    super.key,
    required this.controller,
    required this.label,
    this.minLines = 3,
    this.startInPreview = false,
  });

  final TextEditingController controller;
  final String label;
  final int minLines;

  /// Opens on the preview (existing notes) rather than the editor.
  final bool startInPreview;

  @override
  State<MarkdownNotesField> createState() => _MarkdownNotesFieldState();
}

class _MarkdownNotesFieldState extends State<MarkdownNotesField> {
  late bool _preview =
      widget.startInPreview && widget.controller.text.trim().isNotEmpty;
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _edit(TextEditingValue Function(TextEditingValue) change) {
    final c = widget.controller;
    c.value = change(c.value).copyWith(composing: TextRange.empty);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(l10n.notesEdit),
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: Text(l10n.notesPreview),
                ),
              ],
              selected: {_preview},
              onSelectionChanged: (s) => setState(() => _preview = s.first),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_preview)
          _Preview(
            text: widget.controller.text,
            minLines: widget.minLines,
            onTap: () => setState(() => _preview = false),
          )
        else ...[
          _Toolbar(onEdit: _edit),
          const SizedBox(height: 4),
          TextFormField(
            key: const Key('notesField'),
            controller: widget.controller,
            focusNode: _focus,
            keyboardType: TextInputType.multiline,
            minLines: widget.minLines,
            maxLines: null,
            decoration: InputDecoration(
              hintText: widget.label,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.onEdit});

  final void Function(TextEditingValue Function(TextEditingValue)) onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget button(
      IconData icon,
      String tooltip,
      TextEditingValue Function(TextEditingValue) change,
    ) => IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: () => onEdit(change),
    );
    Widget inline(IconData icon, String tooltip, InlineStyle s) =>
        button(icon, tooltip, (v) => applyInline(v, s));
    Widget line(IconData icon, String tooltip, LineStyle s) =>
        button(icon, tooltip, (v) => applyLine(v, s));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          inline(Icons.format_bold, l10n.notesBold, InlineStyle.bold),
          inline(Icons.format_italic, l10n.notesItalic, InlineStyle.italic),
          inline(
            Icons.format_strikethrough,
            l10n.notesStrike,
            InlineStyle.strike,
          ),
          line(Icons.title, l10n.notesHeading, LineStyle.heading),
          line(
            Icons.format_list_bulleted,
            l10n.notesBulletList,
            LineStyle.bullet,
          ),
          line(
            Icons.format_list_numbered,
            l10n.notesNumberedList,
            LineStyle.numbered,
          ),
          line(Icons.checklist, l10n.notesChecklist, LineStyle.checklist),
          line(Icons.format_quote, l10n.notesQuote, LineStyle.quote),
          inline(Icons.code, l10n.notesCode, InlineStyle.code),
          button(Icons.link, l10n.notesLink, insertLink),
          button(Icons.horizontal_rule, l10n.notesDivider, insertDivider),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.text,
    required this.minLines,
    required this.onTap,
  });

  final String text;
  final int minLines;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lineHeight =
        (theme.textTheme.bodyMedium?.fontSize ?? 14) *
        (theme.textTheme.bodyMedium?.height ?? 1.4);
    return InputDecorator(
      decoration: const InputDecoration(border: OutlineInputBorder()),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: lineHeight * minLines),
        child: text.trim().isEmpty
            ? GestureDetector(
                onTap: onTap,
                child: Text(
                  context.l10n.notesEmptyPreview,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              )
            : MarkdownNotesView(text: text),
      ),
    );
  }
}

/// Rendered notes. Images are never fetched (a remote image would tell
/// its server when the vault is opened): their description is shown
/// instead. Links open only after the user sees the full address.
class MarkdownNotesView extends StatelessWidget {
  const MarkdownNotesView({super.key, required this.text});

  final String text;

  static const _schemes = {'http', 'https', 'mailto'};

  Future<void> _openLink(BuildContext context, String? href) async {
    final uri = href == null ? null : Uri.tryParse(href);
    // Other schemes (javascript:, file:, app deep links) are ignored.
    if (uri == null || !_schemes.contains(uri.scheme.toLowerCase())) return;
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.notesOpenLinkTitle),
        content: SelectableText(uri.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.notesOpen),
          ),
        ],
      ),
    );
    if (ok == true) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MarkdownBody(
      data: text,
      selectable: true,
      softLineBreak: true,
      onTapLink: (_, href, _) => _openLink(context, href),
      imageBuilder: (uri, title, alt) => Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(
                Icons.image_not_supported_outlined,
                size: 16,
                color: theme.colorScheme.outline,
              ),
            ),
            TextSpan(text: ' ${alt ?? title ?? uri}'),
          ],
        ),
      ),
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        blockquoteDecoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          border: Border(
            left: BorderSide(color: theme.colorScheme.primary, width: 3),
          ),
        ),
        codeblockDecoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}
