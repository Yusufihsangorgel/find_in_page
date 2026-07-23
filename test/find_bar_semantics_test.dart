import 'package:find_in_page/find_in_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _body = 'the cat sat on the mat, and the other cat watched the cat';

Widget _host(FindInPageController controller, {FindBar? bar}) => MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            bar ?? FindBar(controller: controller, autofocus: false),
            Expanded(
              child: FindableText(_body, controller: controller),
            ),
          ],
        ),
      ),
    );

/// The label on the counter's semantics node, or null when the counter is not
/// showing (no query yet).
String? _status(WidgetTester tester) {
  final nodes = tester
      .widgetList<Semantics>(
        find.descendant(
          of: find.byType(FindBar),
          matching: find.byType(Semantics),
        ),
      )
      .where((s) => s.properties.liveRegion ?? false);
  return nodes.isEmpty ? null : nodes.first.properties.label;
}

void main() {
  testWidgets('the match count is announced, not just drawn', (tester) async {
    final handle = tester.ensureSemantics();
    final controller = FindInPageController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    // Nothing searched yet, so there is no counter at all.
    expect(_status(tester), isNull);

    await tester.enterText(find.byType(TextField), 'cat');
    await tester.pumpAndSettle();

    // A sighted user watches "1/3" appear here; this is the same fact said
    // out loud, and as a live region so it reaches a user whose focus is
    // still in the query field.
    expect(_status(tester), 'Match 1 of 3');
    expect(find.text('1/3'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('it follows the active match as the user steps through', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final controller = FindInPageController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(controller));
    await tester.enterText(find.byType(TextField), 'cat');
    await tester.pumpAndSettle();
    expect(_status(tester), 'Match 1 of 3');

    controller.next();
    await tester.pumpAndSettle();
    expect(_status(tester), 'Match 2 of 3');

    controller.previous();
    await tester.pumpAndSettle();
    expect(_status(tester), 'Match 1 of 3');
    handle.dispose();
  });

  testWidgets('a query with no matches says so', (tester) async {
    final handle = tester.ensureSemantics();
    final controller = FindInPageController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(controller));
    await tester.enterText(find.byType(TextField), 'elephant');
    await tester.pumpAndSettle();

    expect(_status(tester), 'No matches');
    // The terse visual form stays visual.
    expect(find.text('0/0'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the visible counter is not read alongside the label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final controller = FindInPageController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(controller));
    await tester.enterText(find.byType(TextField), 'cat');
    await tester.pumpAndSettle();

    // "1/3" reads badly aloud, so it is excluded from the tree entirely and
    // only the sentence is announced. It is still drawn.
    expect(find.bySemanticsLabel('1/3'), findsNothing);
    expect(find.text('1/3'), findsOneWidget);
    expect(_status(tester), isNot(contains('1/3')));
    handle.dispose();
  });

  testWidgets('the label can be localized', (tester) async {
    final handle = tester.ensureSemantics();
    final controller = FindInPageController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(
        controller,
        bar: FindBar(
          controller: controller,
          autofocus: false,
          matchStatusLabel: (active, count) => count == 0
              ? 'Eşleşme yok'
              : '${active + 1}. eşleşme, $count adet',
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'cat');
    await tester.pumpAndSettle();

    expect(_status(tester), '1. eşleşme, 3 adet');
    handle.dispose();
  });
}
