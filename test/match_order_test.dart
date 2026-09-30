import 'package:find_in_page/find_in_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _matchTexts(FindInPageController controller) {
  final texts = <String>[];
  for (var i = 0; i < controller.matchCount; i++) {
    texts.add(controller.activeMatch!.source.findableText);
    if (i + 1 < controller.matchCount) controller.next();
  }
  return texts;
}

void main() {
  group('match order', () {
    testWidgets('AppBar and ListTile precede a registered paragraph', (
      tester,
    ) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: FindInPageScope(
            controller: controller,
            child: Scaffold(
              appBar: AppBar(title: const Text('needle title')),
              body: const Column(
                children: [
                  ListTile(title: Text('needle tile')),
                  FindableText('needle paragraph'),
                ],
              ),
            ),
          ),
        ),
      );
      controller.search('needle');
      await tester.pump();

      expect(controller.matchCount, 3);
      expect(controller.activeMatch!.source.findableText, 'needle title');
      expect(_matchTexts(controller), [
        'needle title',
        'needle tile',
        'needle paragraph',
      ]);
      expect(controller.discoveredSources, hasLength(2));
    });

    testWidgets('lazy list rows stay between surrounding paragraphs', (
      tester,
    ) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      String rowText(int index) => index == 0 || index == 1 || index == 25
          ? 'needle row $index'
          : 'row $index';

      await tester.pumpWidget(
        MaterialApp(
          home: FindInPageScope(
            controller: controller,
            child: Scaffold(
              body: Column(
                children: [
                  const Text('needle before'),
                  SizedBox(
                    height: 120,
                    child: FindableListView(
                      itemCount: 30,
                      itemExtent: 40,
                      findableTextOf: rowText,
                      itemBuilder:
                          (context, index, matches, activeMatchIndex) =>
                              Text(rowText(index)),
                    ),
                  ),
                  const Text('needle after'),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('needle row 25'), findsNothing);

      controller.search('needle');
      await tester.pump();

      expect(controller.matchCount, 5);
      expect(_matchTexts(controller), [
        'needle before',
        'needle row 0',
        'needle row 1',
        'needle row 25',
        'needle after',
      ]);
      expect(controller.discoveredSources, hasLength(2));
    });

    testWidgets('discovery off keeps registration order', (tester) async {
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
                  FindableText('needle first'),
                  FindableText('needle second'),
                ],
              ),
            ),
          ),
        ),
      );
      controller.search('needle');
      await tester.pump();

      expect(_matchTexts(controller), ['needle first', 'needle second']);
      expect(controller.discoveredSources, isEmpty);
    });

    testWidgets('a record with no anchor precedes rendered text', (
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
                children: [
                  Text('needle plain'),
                  FindableText('needle wrapped'),
                ],
              ),
            ),
          ),
        ),
      );
      controller.register(FindableRecord('needle record'));
      controller.search('needle');
      await tester.pump();

      expect(_matchTexts(controller), [
        'needle record',
        'needle plain',
        'needle wrapped',
      ]);
    });

    testWidgets('a record can anchor inside an excluded subtree', (
      tester,
    ) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      BuildContext? anchor;

      await tester.pumpWidget(
        MaterialApp(
          home: FindInPageScope(
            controller: controller,
            child: Scaffold(
              body: Column(
                children: [
                  const Text('needle before'),
                  ExcludeFromFind(
                    child: Builder(
                      builder: (context) {
                        anchor = context;
                        return const Text('visible custom text');
                      },
                    ),
                  ),
                  const Text('needle after'),
                ],
              ),
            ),
          ),
        ),
      );
      controller.register(FindableRecord('needle custom'), anchor: anchor);
      controller.search('needle');
      await tester.pump();

      expect(_matchTexts(controller), [
        'needle before',
        'needle custom',
        'needle after',
      ]);
      expect(controller.discoveredSources, hasLength(2));
    });

    testWidgets('a centred label and a taller value keep build order', (
      tester,
    ) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: FindInPageScope(
            controller: controller,
            child: const Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('needle label'),
                    Text('needle value', style: TextStyle(fontSize: 48)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      controller.search('needle');
      await tester.pump();

      // The value's top edge is above the label's. The two overlap vertically
      // and the row keeps the order it was built in.
      expect(_matchTexts(controller), ['needle label', 'needle value']);
    });

    testWidgets('bottom navigation bar text follows the body', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: FindInPageScope(
            controller: controller,
            child: const Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: Text('needle body'),
              ),
              bottomNavigationBar: SizedBox(
                height: 48,
                child: Text('needle bottom'),
              ),
            ),
          ),
        ),
      );
      controller.search('needle');
      await tester.pump();

      expect(_matchTexts(controller), ['needle body', 'needle bottom']);
    });

    testWidgets(
      'extendBodyBehindAppBar keeps body text before the app bar title '
      'because the two overlap',
      (tester) async {
        final controller = FindInPageController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: FindInPageScope(
              controller: controller,
              child: Scaffold(
                extendBodyBehindAppBar: true,
                appBar: AppBar(title: const Text('needle title')),
                body: const Align(
                  alignment: Alignment.topLeft,
                  child: Text('needle body'),
                ),
              ),
            ),
          ),
        );
        controller.search('needle');
        await tester.pump();

        // The body starts at 0 and covers the app bar. The sources overlap and
        // build order applies: body first, then the title.
        expect(_matchTexts(controller), ['needle body', 'needle title']);
      },
    );

    testWidgets('a stacked overlay keeps paint order', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: FindInPageScope(
            controller: controller,
            child: const Scaffold(
              body: Stack(
                children: [
                  SizedBox.expand(
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Text('needle content'),
                    ),
                  ),
                  Positioned(top: 0, left: 0, child: Text('needle overlay')),
                ],
              ),
            ),
          ),
        ),
      );
      controller.search('needle');
      await tester.pump();

      // The overlay is higher on the screen than the text it covers. The
      // children overlap and the stack's paint order holds.
      expect(_matchTexts(controller), ['needle content', 'needle overlay']);
    });

    for (final side in ['drawer', 'endDrawer', 'both']) {
      testWidgets('app bar title precedes the body with $side', (tester) async {
        final controller = FindInPageController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: FindInPageScope(
              controller: controller,
              child: Scaffold(
                appBar: AppBar(title: const Text('needle title')),
                drawer: side == 'endDrawer'
                    ? null
                    : const Drawer(child: Text('needle drawer')),
                endDrawer: side == 'drawer'
                    ? null
                    : const Drawer(child: Text('needle end drawer')),
                body: const Align(
                  alignment: Alignment.topLeft,
                  child: Text('needle body'),
                ),
              ),
            ),
          ),
        );
        controller.search('needle');
        await tester.pump();

        expect(_matchTexts(controller), ['needle title', 'needle body']);
      });
    }

    testWidgets('a list keeps its row order under an app bar', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: FindInPageScope(
            controller: controller,
            child: Scaffold(
              appBar: AppBar(title: const Text('needle title')),
              body: ListView(
                children: const [
                  Text('needle one'),
                  Text('needle two'),
                  Text('needle three'),
                ],
              ),
            ),
          ),
        ),
      );
      controller.search('needle');
      await tester.pump();

      // A viewport holds slivers, which are not boxes. It keeps child order.
      expect(_matchTexts(controller), [
        'needle title',
        'needle one',
        'needle two',
        'needle three',
      ]);
    });
  });
}
