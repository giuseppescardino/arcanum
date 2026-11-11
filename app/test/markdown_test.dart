import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcanum/app/markdown_format.dart';
import 'package:arcanum/l10n/app_localizations.dart';
import 'package:arcanum/ui/markdown_notes.dart';

TextEditingValue v(String text, int start, [int? end]) => TextEditingValue(
  text: text,
  selection: TextSelection(baseOffset: start, extentOffset: end ?? start),
);

void main() {
  group('inline styles', () {
    test('wrap the selection and keep it selected', () {
      final r = applyInline(v('a word here', 2, 6), InlineStyle.bold);
      expect(r.text, 'a **word** here');
      expect(r.selection.textInside(r.text), 'word');
    });

    test('toggle off when already wrapped', () {
      final on = applyInline(v('a word', 2, 6), InlineStyle.italic);
      final off = applyInline(on, InlineStyle.italic);
      expect(off.text, 'a word');
      expect(off.selection.textInside(off.text), 'word');
      expect(applyInline(v('~~x~~', 0, 5), InlineStyle.strike).text, 'x');
    });

    test('with no selection put the cursor between markers', () {
      final r = applyInline(v('ab', 1), InlineStyle.bold);
      expect(r.text, 'a****b');
      expect(r.selection, const TextSelection.collapsed(offset: 3));
    });

    test('multi-line code becomes a fenced block', () {
      final r = applyInline(v('x\na\nb', 2, 5), InlineStyle.code);
      expect(r.text, 'x\n```\na\nb\n```');
    });
  });

  group('line styles', () {
    test('prefix every selected line and toggle off', () {
      final on = applyLine(v('one\ntwo\nthree', 1, 6), LineStyle.bullet);
      expect(on.text, '- one\n- two\nthree');
      expect(applyLine(on, LineStyle.bullet).text, 'one\ntwo\nthree');
    });

    test('numbered lists count, other styles are replaced', () {
      final r = applyLine(v('- a\n- b', 0, 7), LineStyle.numbered);
      expect(r.text, '1. a\n2. b');
      expect(applyLine(v('> q', 0), LineStyle.heading).text, '## q');
    });

    test('checklist is not mistaken for a bullet', () {
      final r = applyLine(v('- [ ] buy', 0), LineStyle.bullet);
      expect(r.text, '- buy');
      expect(applyLine(v('- [x] done', 0), LineStyle.checklist).text, 'done');
    });

    test('a collapsed cursor stays on its text', () {
      final r = applyLine(v('hello', 3), LineStyle.quote);
      expect(r.text, '> hello');
      expect(r.selection, const TextSelection.collapsed(offset: 5));
    });
  });

  test('links select the part to type next', () {
    final r = insertLink(v('see docs', 4, 8));
    expect(r.text, 'see [docs](https://)');
    expect(r.selection.textInside(r.text), 'https://');
    final u = insertLink(v('https://x.io', 0, 12));
    expect(u.text, '[https://x.io](https://x.io)');
    expect(insertLink(v('', 0)).selection.baseOffset, 1);
  });

  test('divider goes on its own line', () {
    expect(insertDivider(v('abc', 1)).text, 'abc\n\n---\n');
    expect(insertDivider(v('', 0)).text, '---\n');
  });

  Widget app(Widget child) => MaterialApp(
    locale: const Locale('it'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets('toolbar formats the text and the preview renders it', (
    tester,
  ) async {
    final notes = TextEditingController(text: 'pin');
    await tester.pumpWidget(
      app(MarkdownNotesField(controller: notes, label: 'Note')),
    );
    notes.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
    await tester.tap(find.byTooltip('Grassetto'));
    await tester.pump();
    expect(notes.text, '**pin**');

    await tester.tap(find.text('Anteprima'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notesField')), findsNothing);
    expect(find.textContaining('**'), findsNothing);
    expect(find.textContaining('pin', findRichText: true), findsWidgets);
  });

  testWidgets('existing notes open on the preview; images are not loaded', (
    tester,
  ) async {
    final notes = TextEditingController(
      text: '# Titolo\n\n![logo](https://tracker.example/p.png)',
    );
    await tester.pumpWidget(
      app(
        MarkdownNotesField(
          controller: notes,
          label: 'Note',
          startInPreview: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('logo', findRichText: true), findsOneWidget);
    expect(find.byKey(const Key('notesField')), findsNothing);
  });
}
