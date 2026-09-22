import 'package:find_in_page/find_in_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

Future<void> _pressCtrlF(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

/// The [EditableText] backing the built-in bar's query field, however it
/// got onto the screen.
EditableText _barField(WidgetTester tester) => tester.widget<EditableText>(
      find.descendant(
        of: find.byType(FindBar),
        matching: find.byType(EditableText),
      ),
    );

void main() {
  group('opening moves focus', () {
    testWidgets(
        'opening the bar moves focus into its field even when another '
        'node already has focus', (tester) async {
      // Regression test for the reported bug: a plain TextField(autofocus:
      // true) only takes focus when the enclosing FocusScope has none, so
      // with another field already focused, opening the bar used to leave
      // focus exactly where it was and the user had to click into the
      // field by hand.
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final fieldFocus = FocusNode();
      addTearDown(fieldFocus.dispose);

      await tester.pumpWidget(_app(
        FindInPageScope(
          controller: controller,
          child: Column(
            children: [
              TextField(focusNode: fieldFocus),
              const FindableText('content'),
            ],
          ),
        ),
      ));

      fieldFocus.requestFocus();
      await tester.pump();
      expect(fieldFocus.hasFocus, isTrue,
          reason: 'setup: the field is focused');

      await _pressCtrlF(tester);

      expect(find.byType(FindBar), findsOneWidget);
      expect(_barField(tester).focusNode.hasFocus, isTrue,
          reason: 'opening the bar should move focus into its field');
      expect(fieldFocus.hasFocus, isFalse);
    });

    testWidgets('autofocus: false does not move focus', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final fieldFocus = FocusNode();
      addTearDown(fieldFocus.dispose);

      await tester.pumpWidget(_app(
        Column(
          children: [
            TextField(focusNode: fieldFocus),
            FindBar(controller: controller, autofocus: false),
          ],
        ),
      ));

      fieldFocus.requestFocus();
      await tester.pump();
      expect(fieldFocus.hasFocus, isTrue);

      // Give any (wrongly scheduled) focus request a chance to run.
      await tester.pump();
      expect(fieldFocus.hasFocus, isTrue,
          reason: 'autofocus: false must not steal focus');
    });
  });

  group('closing restores focus', () {
    testWidgets('Escape returns focus to the node focused before opening',
        (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final fieldFocus = FocusNode();
      addTearDown(fieldFocus.dispose);

      await tester.pumpWidget(_app(
        FindInPageScope(
          controller: controller,
          child: Column(
            children: [
              TextField(focusNode: fieldFocus),
              const FindableText('content'),
            ],
          ),
        ),
      ));
      fieldFocus.requestFocus();
      await tester.pump();

      await _pressCtrlF(tester);
      expect(_barField(tester).focusNode.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.byType(FindBar), findsNothing);
      expect(fieldFocus.hasFocus, isTrue,
          reason: 'focus should return to the field that had it before');
    });

    testWidgets('controller.close() returns focus the same way',
        (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final fieldFocus = FocusNode();
      addTearDown(fieldFocus.dispose);

      await tester.pumpWidget(_app(
        FindInPageScope(
          controller: controller,
          child: Column(
            children: [
              TextField(focusNode: fieldFocus),
              const FindableText('content'),
            ],
          ),
        ),
      ));
      fieldFocus.requestFocus();
      await tester.pump();

      await _pressCtrlF(tester);
      expect(_barField(tester).focusNode.hasFocus, isTrue);

      controller.close();
      await tester.pump();

      expect(find.byType(FindBar), findsNothing);
      expect(fieldFocus.hasFocus, isTrue);
    });

    testWidgets(
        'a node focused before opening that is removed from the tree '
        'while find stays open does not crash on close', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final fieldFocus = FocusNode();
      addTearDown(fieldFocus.dispose);
      var showField = true;
      late StateSetter setLocalState;

      await tester.pumpWidget(_app(
        FindInPageScope(
          controller: controller,
          child: StatefulBuilder(
            builder: (context, setState) {
              setLocalState = setState;
              return Column(
                children: [
                  if (showField) TextField(focusNode: fieldFocus),
                  const FindableText('content'),
                ],
              );
            },
          ),
        ),
      ));

      fieldFocus.requestFocus();
      await tester.pump();
      await _pressCtrlF(tester);
      expect(_barField(tester).focusNode.hasFocus, isTrue);

      // The node that had focus before find opened is gone by the time find
      // closes.
      setLocalState(() => showField = false);
      await tester.pump();

      controller.close();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(FindBar), findsNothing);
    });

    testWidgets(
        'focus moved elsewhere while the bar was open is not yanked back '
        'on close', (tester) async {
      // The bar only takes over what it itself still holds. A user who
      // clicked into a different field while find stayed open has moved on
      // deliberately; closing the bar must not pull focus away from there
      // and back to whatever was focused before find opened.
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final focusA = FocusNode();
      addTearDown(focusA.dispose);
      final focusB = FocusNode();
      addTearDown(focusB.dispose);

      await tester.pumpWidget(_app(
        FindInPageScope(
          controller: controller,
          child: Column(
            children: [
              TextField(focusNode: focusA),
              TextField(focusNode: focusB),
              const FindableText('content'),
            ],
          ),
        ),
      ));

      focusA.requestFocus();
      await tester.pump();
      await _pressCtrlF(tester);
      expect(_barField(tester).focusNode.hasFocus, isTrue);

      // The user clicks into a different field while find stays open.
      focusB.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.byType(FindBar), findsNothing);
      expect(focusB.hasFocus, isTrue,
          reason: 'closing must leave focus where the user put it');
      expect(focusA.hasFocus, isFalse);
    });
  });

  group('FindInPageController.isOpen', () {
    testWidgets('the find shortcut opens it and notifies listeners',
        (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      await tester.pumpWidget(_app(
        FindInPageScope(
          controller: controller,
          child: const FindableText('content'),
        ),
      ));
      expect(controller.isOpen, isFalse);

      await _pressCtrlF(tester);

      expect(controller.isOpen, isTrue);
      expect(notifications, greaterThan(0));
    });

    testWidgets('the close button closes it', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(
        FindInPageScope(
          controller: controller,
          child: const FindableText('content'),
        ),
      ));
      await _pressCtrlF(tester);
      expect(controller.isOpen, isTrue);

      var notifications = 0;
      controller.addListener(() => notifications++);
      await tester.tap(find.byTooltip('Close'));
      await tester.pump();

      expect(controller.isOpen, isFalse);
      expect(notifications, greaterThan(0));
    });

    testWidgets('Escape closes it', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(
        FindInPageScope(
          controller: controller,
          child: const FindableText('content'),
        ),
      ));
      await _pressCtrlF(tester);
      expect(controller.isOpen, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(controller.isOpen, isFalse);
    });

    testWidgets('open() shows the built-in bar and sets isOpen',
        (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(
        FindInPageScope(
          controller: controller,
          child: const FindableText('content'),
        ),
      ));
      expect(find.byType(FindBar), findsNothing);

      controller.open();
      await tester.pump();

      expect(controller.isOpen, isTrue);
      expect(find.byType(FindBar), findsOneWidget);
    });

    testWidgets('close() hides the built-in bar and sets isOpen false',
        (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(
        FindInPageScope(
          controller: controller,
          child: const FindableText('content'),
        ),
      ));
      controller.open();
      await tester.pump();
      expect(find.byType(FindBar), findsOneWidget);

      controller.close();
      await tester.pump();

      expect(controller.isOpen, isFalse);
      expect(find.byType(FindBar), findsNothing);
    });

    testWidgets('close() clears the search', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(
        FindInPageScope(
          controller: controller,
          child: const FindableText('one match here'),
        ),
      ));
      controller.search('match');
      await tester.pump();
      expect(controller.matchCount, 1);

      controller.close();
      await tester.pump();

      expect(controller.query, isEmpty);
      expect(controller.matchCount, 0);
    });

    testWidgets(
        'showBar: false routes open() to onOpenRequested and still sets '
        'isOpen', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      var opened = 0;

      await tester.pumpWidget(_app(
        FindInPageScope(
          controller: controller,
          showBar: false,
          onOpenRequested: () => opened++,
          child: const FindableText('content'),
        ),
      ));

      controller.open();
      await tester.pump();

      expect(opened, 1);
      expect(controller.isOpen, isTrue);
      expect(find.byType(FindBar), findsNothing,
          reason: 'showBar: false never shows the built-in bar');
    });

    testWidgets(
        'Escape is not consumed when find is closed, so an ancestor '
        'Escape handler still fires', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      var ancestorEscapes = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  ancestorEscapes++,
            },
            child: Scaffold(
              body: FindInPageScope(
                controller: controller,
                child: Column(
                  children: [
                    Focus(autofocus: true, child: const SizedBox()),
                    const FindableText('content'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(controller.isOpen, isFalse, reason: 'setup: find is not open yet');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(ancestorEscapes, 1,
          reason: 'this scope must not swallow Escape while it is closed');
    });

    testWidgets('scope dispose while open resets isOpen', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(
        FindInPageScope(
          controller: controller,
          child: const FindableText('content'),
        ),
      ));
      controller.open();
      await tester.pump();
      expect(controller.isOpen, isTrue);

      // Replace the tree so the scope (and its bar) are gone, but the
      // controller — passed in, so owned by the caller — survives.
      await tester.pumpWidget(_app(const SizedBox()));
      await tester.pump();

      expect(controller.isOpen, isFalse);
    });

    testWidgets(
        'a controller disposed before its scope unmounts does not crash '
        'the scope', (tester) async {
      // Regression: the scope's dispose() resets isOpen through the same
      // controller it was handed, and whoever owns that controller may
      // dispose it in either order relative to the scope leaving the tree.
      final controller = FindInPageController();

      await tester.pumpWidget(_app(
        FindInPageScope(
          controller: controller,
          child: const FindableText('content'),
        ),
      ));
      controller.open();
      await tester.pump();
      expect(controller.isOpen, isTrue);

      controller.dispose();
      await tester.pumpWidget(_app(const SizedBox()));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('with no scope mounted, open() and close() only flip isOpen',
        (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);

      controller.open();
      expect(controller.isOpen, isTrue);
      expect(tester.takeException(), isNull);

      controller.close();
      expect(controller.isOpen, isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
