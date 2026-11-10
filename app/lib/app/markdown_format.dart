/// Markdown edits for the notes toolbar. Each function takes the field's
/// current value and returns the new one, selection included, so they can
/// be tested without widgets.
library;

import 'package:flutter/services.dart';

/// Inline styles: wrap the selection in a marker pair.
enum InlineStyle {
  bold('**'),
  italic('_'),
  strike('~~'),
  code('`');

  const InlineStyle(this.marker);
  final String marker;
}

/// Line styles: a prefix at the start of every selected line.
enum LineStyle {
  heading('## '),
  bullet('- '),
  numbered('1. '),
  checklist('- [ ] '),
  quote('> ');

  const LineStyle(this.prefix);
  final String prefix;
}

TextSelection _selectionOf(TextEditingValue v) {
  final s = v.selection;
  if (!s.isValid) return TextSelection.collapsed(offset: v.text.length);
  return TextSelection(baseOffset: s.start, extentOffset: s.end);
}

/// Wraps the selection in [style]'s marker, or removes it when the
/// selection is already wrapped. With nothing selected the markers are
/// inserted and the cursor lands between them. A multi-line selection
/// styled as code becomes a fenced block.
TextEditingValue applyInline(TextEditingValue value, InlineStyle style) {
  final sel = _selectionOf(value);
  final text = value.text;
  final selected = sel.textInside(text);

  if (style == InlineStyle.code && selected.contains('\n')) {
    final before = sel.start == 0 || text[sel.start - 1] == '\n' ? '' : '\n';
    final after = sel.end == text.length || text[sel.end] == '\n' ? '' : '\n';
    final block = '$before```\n$selected\n```$after';
    return TextEditingValue(
      text: text.replaceRange(sel.start, sel.end, block),
      selection: TextSelection(
        baseOffset: sel.start + before.length + 4,
        extentOffset: sel.start + before.length + 4 + selected.length,
      ),
    );
  }

  final m = style.marker;
  // Already wrapped (markers just outside the selection): unwrap.
  if (sel.start >= m.length &&
      sel.end + m.length <= text.length &&
      text.substring(sel.start - m.length, sel.start) == m &&
      text.substring(sel.end, sel.end + m.length) == m) {
    return TextEditingValue(
      text: text
          .replaceRange(sel.end, sel.end + m.length, '')
          .replaceRange(sel.start - m.length, sel.start, ''),
      selection: TextSelection(
        baseOffset: sel.start - m.length,
        extentOffset: sel.end - m.length,
      ),
    );
  }
  // Markers selected along with the text: unwrap too.
  if (selected.length >= 2 * m.length &&
      selected.startsWith(m) &&
      selected.endsWith(m)) {
    final inner = selected.substring(m.length, selected.length - m.length);
    return TextEditingValue(
      text: text.replaceRange(sel.start, sel.end, inner),
      selection: TextSelection(
        baseOffset: sel.start,
        extentOffset: sel.start + inner.length,
      ),
    );
  }
  return TextEditingValue(
    text: text.replaceRange(sel.start, sel.end, '$m$selected$m'),
    selection: TextSelection(
      baseOffset: sel.start + m.length,
      extentOffset: sel.end + m.length,
    ),
  );
}

/// Every [LineStyle] prefix, longest first so `- [ ] ` wins over `- `.
final _linePrefix = RegExp(r'^(#{1,6} |- \[[ xX]\] |[-*+] |\d+\. |> )');

/// Toggles [style] on every line the selection touches: when all of them
/// already have it, it is removed; otherwise it replaces whatever line
/// style they had. Numbered lists are renumbered from 1.
TextEditingValue applyLine(TextEditingValue value, LineStyle style) {
  final sel = _selectionOf(value);
  final text = value.text;
  final start = sel.start == 0 ? 0 : text.lastIndexOf('\n', sel.start - 1) + 1;
  var end = text.indexOf('\n', sel.end);
  if (end < 0) end = text.length;

  final lines = text.substring(start, end).split('\n');
  bool has(String line) => style == LineStyle.numbered
      ? RegExp(r'^\d+\. ').hasMatch(line)
      : style == LineStyle.bullet
      ? RegExp(r'^[-*+] ').hasMatch(line) && !line.startsWith('- [')
      : line.startsWith(style.prefix) ||
            (style == LineStyle.checklist && line.startsWith('- [x] '));
  final remove = lines.every(has);

  var n = 0;
  final out = [
    for (final line in lines)
      if (remove)
        line.replaceFirst(_linePrefix, '')
      else
        (style == LineStyle.numbered ? '${++n}. ' : style.prefix) +
            line.replaceFirst(_linePrefix, ''),
  ].join('\n');

  final collapsed = sel.isCollapsed;
  final delta = out.length - (end - start);
  return TextEditingValue(
    text: text.replaceRange(start, end, out),
    selection: collapsed && lines.length == 1
        ? TextSelection.collapsed(
            offset: (sel.start + delta).clamp(start, start + out.length),
          )
        : TextSelection(baseOffset: start, extentOffset: start + out.length),
  );
}

/// Turns the selection into `[text](url)` and selects `url` so it can be
/// typed over. A selection that looks like an address becomes the url.
TextEditingValue insertLink(TextEditingValue value) {
  final sel = _selectionOf(value);
  final selected = sel.textInside(value.text);
  final isUrl = RegExp(r'^(https?://|mailto:)\S+$').hasMatch(selected);
  final label = selected;
  final url = isUrl ? selected : 'https://';
  final link = '[$label]($url)';
  final urlStart = sel.start + label.length + 3;
  return TextEditingValue(
    text: value.text.replaceRange(sel.start, sel.end, link),
    selection: label.isEmpty
        ? TextSelection.collapsed(offset: sel.start + 1)
        : isUrl
        // The address doubles as the label: select it to type a name.
        ? TextSelection(
            baseOffset: sel.start + 1,
            extentOffset: sel.start + 1 + label.length,
          )
        : TextSelection(
            baseOffset: urlStart,
            extentOffset: urlStart + url.length,
          ),
  );
}

/// Inserts a horizontal rule on its own line after the cursor's line.
TextEditingValue insertDivider(TextEditingValue value) {
  final sel = _selectionOf(value);
  final text = value.text;
  var end = text.indexOf('\n', sel.end);
  if (end < 0) end = text.length;
  final lead = end == 0 ? '' : '\n\n';
  final insert = '$lead---\n';
  final offset = end + insert.length;
  return TextEditingValue(
    text: text.replaceRange(end, end, insert),
    selection: TextSelection.collapsed(offset: offset),
  );
}
