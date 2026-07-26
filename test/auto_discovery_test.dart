import 'package:find_in_page/find_in_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The page a reader actually has: text in widgets nobody wrapped.
Widget _realisticPage(FindInPageController controller) => MaterialApp(
      home: FindInPageScope(
        controller: controller,
        child: Scaffold(
          appBar: AppBar(title: const Text('acme docs')),
          body: ListView(
            children: [
              Text.rich(
                const TextSpan(
                  children: [
                    TextSpan(text: 'Support: '),
                    TextSpan(
                      text: 'acme support desk',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SelectableText('acme selectable line'),
              const ListTile(title: Text('acme Pro plan')),
              DataTable(
                columns: const [DataColumn(label: Text('Plan'))],
                rows: const [
                  DataRow(cells: [DataCell(Text('acme Pro'))]),
                ],
              ),
              TextFormField(initialValue: 'acme in a field'),
            ],
          ),
        ),
      ),
    );

void main() {
  group('automatic discovery', () {
    testWidgets('finds text in widgets the app never wrapped', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_realisticPage(controller));
      controller.search('acme');
      await tester.pump();

      // AppBar title, Text.rich, SelectableText, ListTile, DataTable cell.
      // Not the TextFormField: see the next test.
      expect(controller.matchCount, 5);
      expect(controller.activeMatchIndex, 0);
    });

    testWidgets('reads a SelectableText but not an editable field', (
      tester,
    ) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: FindInPageScope(
            controller: controller,
            child: Scaffold(
              body: Column(
                children: [
                  const SelectableText('needle in read-only text'),
                  TextFormField(initialValue: 'needle in a field'),
                ],
              ),
            ),
          ),
        ),
      );
      controller.search('needle');
      await tester.pump();

      // A browser's find bar does not match inside form controls either.
      expect(controller.matchCount, 1);
      expect(
        controller.discoveredSources.single.findableText,
        'needle in read-only text',
      );
    });

    testWidgets('does not treat icon glyphs as searchable text', (
      tester,
    ) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: FindInPageScope(
            controller: controller,
            child: const Scaffold(
              body: Column(
                children: [Icon(Icons.expand_more), Text('plain text')],
              ),
            ),
          ),
        ),
      );
      controller.search('plain');
      await tester.pump();

      // Flutter draws an Icon as a font glyph inside a paragraph, so a naive
      // sweep would register it as a one-character searchable string.
      expect(controller.matchCount, 1);
      expect(
        controller.discoveredSources.map((s) => s.findableText),
        ['plain text'],
      );
    });

    testWidgets('counts a FindableText once, not twice', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: FindInPageScope(
            controller: controller,
            child: const Scaffold(
              body: FindableText('needle needle'),
            ),
          ),
        ),
      );
      controller.search('needle');
      await tester.pump();

      // FindableText registers its own text and highlights it inline. Its
      // rendered paragraph must not be discovered on top of that.
      expect(controller.matchCount, 2);
      expect(controller.discoveredSources, isEmpty);
    });

    testWidgets('ExcludeFromFind removes a subtree', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: FindInPageScope(
            controller: controller,
            child: const Scaffold(
              body: Column(
                children: [
                  ExcludeFromFind(child: Text('needle in the chrome')),
                  Text('needle in the content'),
                ],
              ),
            ),
          ),
        ),
      );
      controller.search('needle');
      await tester.pump();

      expect(controller.matchCount, 1);
      expect(
        controller.discoveredSources.single.findableText,
        'needle in the content',
      );
    });

    testWidgets('autoDiscover false searches only registered sources', (
      tester,
    ) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: FindInPageScope(
            controller: controller,
            autoDiscover: false,
            child: const Scaffold(
              body: Column(
                children: [
                  Text('needle unwrapped'),
                  FindableText('needle wrapped'),
                ],
              ),
            ),
          ),
        ),
      );
      controller.search('needle');
      await tester.pump();

      expect(controller.matchCount, 1);
      expect(controller.discoveredSources, isEmpty);
    });

    testWidgets('clearing the search drops the discovered sources', (
      tester,
    ) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_realisticPage(controller));
      controller.search('acme');
      await tester.pump();
      expect(controller.discoveredSources, isNotEmpty);

      controller.clearSearch();
      await tester.pump();
      expect(controller.matchCount, 0);
      expect(controller.discoveredSources, isEmpty);
    });

    testWidgets('a match reports a rectangle the overlay can paint', (
      tester,
    ) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: FindInPageScope(
            controller: controller,
            child: const Scaffold(
              body: Center(child: Text('the quick acme fox')),
            ),
          ),
        ),
      );
      controller.search('acme');
      await tester.pump();

      final source = controller.discoveredSources.single as RenderedTextSource;
      final match = controller.matchesFor(source).single;
      final rects = source.boxesFor(
        match.start,
        match.end,
        tester.binding.renderViews.first,
      );

      // Highlighting text we do not own means painting over it, so a non-empty
      // rectangle in a known coordinate space is the whole mechanism.
      expect(rects, hasLength(1));
      expect(rects.single.width, greaterThan(0));
      expect(rects.single.height, greaterThan(0));
    });

    testWidgets('text added after the search is found on the next pass', (
      tester,
    ) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      var extra = false;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => FindInPageScope(
              controller: controller,
              child: Scaffold(
                body: Column(
                  children: [
                    const Text('needle one'),
                    if (extra) const Text('needle two'),
                    TextButton(
                      onPressed: () => setState(() => extra = true),
                      child: const Text('add'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      controller.search('needle');
      await tester.pump();
      expect(controller.matchCount, 1);

      await tester.tap(find.text('add'));
      await tester.pump();
      controller.search('needle');
      await tester.pump();

      // The sweep runs at recompute time, after layout, so it sees whatever is
      // on screen then rather than a snapshot from when the search started.
      expect(controller.matchCount, 2);
    });
  });
}
