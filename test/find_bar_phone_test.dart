// A phone lays the bar out in its own font. The test font draws every glyph
// one em wide, about twice as wide as a Roboto digit, and a three digit
// counter in it would not leave one row on a 360 wide phone, where it fits
// in Roboto. These tests load Roboto from the Flutter SDK and lay the bar
// out in it. iOS gets Roboto too, as its system font does not ship with
// the SDK.
@TestOn('vm')
library;

import 'dart:io';

import 'package:find_in_page/find_in_page.dart';
import 'package:flutter/foundation.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _queryField = find.descendant(
  of: find.byType(FindBar),
  matching: find.byType(EditableText),
);

Directory _materialFonts() {
  var dir = File(Platform.resolvedExecutable).parent;
  while (true) {
    final fonts = Directory('${dir.path}/bin/cache/artifacts/material_fonts');
    if (fonts.existsSync()) return fonts;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('material_fonts not found above $dir');
    }
    dir = parent;
  }
}

var _robotoLoaded = false;

Future<void> _loadRoboto(WidgetTester tester) async {
  if (_robotoLoaded) return;
  await tester.runAsync(() async {
    final file = File('${_materialFonts().path}/Roboto-Regular.ttf');
    final bytes = ByteData.sublistView(await file.readAsBytes());
    await (FontLoader('Roboto')..addFont(Future.value(bytes))).load();
  });
  _robotoLoaded = true;
}

String? _focusedLabel() {
  String? label;
  FocusManager.instance.primaryFocus?.context?.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is Semantics && widget.properties.label != null) {
      label = widget.properties.label;
      return false;
    }
    return true;
  });
  return label;
}

Future<List<String?>> _tabOrder(WidgetTester tester, int steps) async {
  await tester.showKeyboard(_queryField);
  final order = <String?>[_focusedLabel()];
  for (var i = 0; i < steps; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    order.add(_focusedLabel());
  }
  return order;
}

void main() {
  testWidgets(
    'on phone widths the scope bar is one row with a three digit counter, '
    'and its toggles work beside the field or behind the options button',
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
    (tester) async {
      await _loadRoboto(tester);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final hit = defaultTargetPlatform == TargetPlatform.iOS ? 44.0 : 48.0;
      final inline = <double, bool>{};
      for (final width in [360.0, 393.0, 411.0, 430.0]) {
        final reason = '$width wide';
        tester.view.physicalSize = Size(width, 800);
        final controller = FindInPageController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          MaterialApp(
            home: FindBarTheme(
              style: const FindBarStyle(
                textStyle: TextStyle(fontFamily: 'Roboto'),
                counterStyle: TextStyle(fontFamily: 'Roboto'),
              ),
              child: Scaffold(
                body: FindInPageScope(
                  controller: controller,
                  child: SingleChildScrollView(
                    child: Text(List.filled(120, 'go').join(' ')),
                  ),
                ),
              ),
            ),
          ),
        );
        controller.open();
        await tester.pump();
        final bar = tester.getSize(find.byType(FindBar));
        final field = tester.getSize(_queryField);

        await tester.enterText(_queryField, 'g');
        await tester.pump();
        expect(find.text('1/120'), findsOneWidget, reason: reason);
        expect(tester.takeException(), isNull, reason: reason);
        expect(bar.height, hit + 8, reason: 'one row, $reason');
        expect(tester.getSize(find.byType(FindBar)), bar, reason: reason);
        expect(tester.getSize(_queryField), field, reason: reason);

        final options = find.byTooltip('Search options').evaluate().isNotEmpty;
        inline[width] = !options;
        if (options) {
          expect(await _tabOrder(tester, 4), [
            'Find in page',
            'Search options',
            'Previous match',
            'Next match',
            'Close',
          ], reason: reason);
          await tester.tap(find.byTooltip('Search options'));
          await tester.pump();
          expect(
            tester.getSize(find.byType(FindBar)).height,
            2 * hit + 8,
            reason: reason,
          );
          expect(await _tabOrder(tester, 6), [
            'Find in page',
            'Search options',
            'Previous match',
            'Next match',
            'Close',
            'Match case',
            'Match accents',
          ], reason: reason);
        } else {
          expect(await _tabOrder(tester, 5), [
            'Find in page',
            'Match case',
            'Match accents',
            'Previous match',
            'Next match',
            'Close',
          ], reason: reason);
        }
        await tester.tap(find.byTooltip('Match case'));
        await tester.pump();
        expect(controller.caseSensitive, isTrue, reason: reason);
        await tester.tap(find.byTooltip('Match accents'));
        await tester.pump();
        expect(controller.diacriticSensitive, isTrue, reason: reason);
        if (options) {
          await tester.tap(find.byTooltip('Search options'));
          await tester.pump();
          expect(find.byTooltip('Match case'), findsNothing, reason: reason);
          expect(tester.getSize(find.byType(FindBar)), bar, reason: reason);
          // Match accents had keyboard focus from the tab walk above.
          expect(_focusedLabel(), 'Search options', reason: reason);
        }
        expect(tester.takeException(), isNull, reason: reason);
        controller.close();
        await tester.pump();
      }
      // In Roboto the toggles fit beside the field from 411 wide on Android
      // and from 393 wide on iOS.
      expect(
        inline,
        defaultTargetPlatform == TargetPlatform.iOS
            ? {360.0: false, 393.0: true, 411.0: true, 430.0: true}
            : {360.0: false, 393.0: false, 411.0: true, 430.0: true},
      );
    },
  );

  testWidgets(
    'at common font sizes the bar keeps one row while the counter gets at '
    'least three quarters of its room, and the first letter typed moves '
    'nothing',
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
    (tester) async {
      await _loadRoboto(tester);
      final semantics = tester.ensureSemantics();
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final hit = defaultTargetPlatform == TargetPlatform.iOS ? 44.0 : 48.0;
      var oneRow = 0;
      var twoRows = 0;
      for (final width in [360.0, 393.0]) {
        for (final scale in [1.0, 1.1, 1.15, 1.3, 2.0]) {
          for (final count in [120, 1200]) {
            final reason = '$width wide, text scale $scale, $count matches';
            tester.view.physicalSize = Size(width, 800);
            final controller = FindInPageController();
            addTearDown(controller.dispose);
            await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(
              MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: FindBarTheme(
                  style: const FindBarStyle(
                    textStyle: TextStyle(fontFamily: 'Roboto'),
                    counterStyle: TextStyle(fontFamily: 'Roboto'),
                  ),
                  child: Scaffold(
                    body: FindInPageScope(
                      controller: controller,
                      child: SingleChildScrollView(
                        child: Text(List.filled(count, 'go').join(' ')),
                      ),
                    ),
                  ),
                ),
              ),
            );
            controller.open();
            await tester.pump();

            // The rule, worked out here from the counter style the bar
            // resolves to. The bar is 16 inside the scope's padding and its
            // own padding is 8 a side.
            final style = FindBarTheme.resolve(
              tester.element(find.byType(FindBar)),
            );
            final painter = TextPainter(
              text: TextSpan(text: '000/000', style: style.counterStyle),
              textScaler: TextScaler.linear(scale),
              textDirection: TextDirection.ltr,
            )..layout();
            final reserve = painter.width;
            painter.dispose();
            final room = width - 32;
            final fixed = 80 + 4 + 4 + 3 * hit;
            final inline = room >= fixed + reserve + 2 * hit;
            final left = room - fixed - (inline ? 2 * hit : hit);
            final stacked = left < 0.75 * reserve;

            final before = tester.getSize(find.byType(FindBar)).height;
            await tester.enterText(_queryField, 'g');
            await tester.pump();
            expect(tester.takeException(), isNull, reason: reason);
            final counter = '1/$count';
            expect(find.text(counter), findsOneWidget, reason: reason);
            expect(
              tester.getSize(find.byType(FindBar)).height,
              before,
              reason: 'no jump, $reason',
            );
            expect(
              before,
              stacked ? 2 * hit + 8 : hit + 8,
              reason: 'rows, $reason',
            );
            stacked ? twoRows++ : oneRow++;
            // The counter takes what the row leaves, never the field's
            // minimum.
            expect(
              tester.getSize(_queryField).width,
              greaterThanOrEqualTo(80 - 0.01),
              reason: reason,
            );

            // All of the counter is drawn inside its slot, scaled down where
            // the slot is narrower, and it is still announced in full.
            final drawn = tester.getRect(find.text(counter));
            final slot = tester.getRect(find.byKey(const ValueKey('counter')));
            expect(drawn.left, greaterThanOrEqualTo(slot.left - 0.01));
            expect(drawn.right, lessThanOrEqualTo(slot.right + 0.01));
            expect(
              tester
                  .renderObject<RenderParagraph>(find.text(counter))
                  .didExceedMaxLines,
              isFalse,
              reason: reason,
            );
            expect(
              tester.getSemantics(find.bySemanticsLabel('Match 1 of $count')),
              isSemantics(isLiveRegion: true),
              reason: reason,
            );
            controller.close();
            await tester.pump();
          }
        }
      }
      // Both outcomes of the rule were met.
      expect(oneRow, greaterThan(0));
      expect(twoRows, greaterThan(0));
      semantics.dispose();
    },
  );
}
