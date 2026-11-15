import 'dart:io';

import 'package:find_in_page/find_in_page.dart';
// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart'
    show CupertinoApp, CupertinoPageScaffold;
// ignore: deprecated_member_use
import 'package:flutter/material.dart' show MaterialApp, Scaffold;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The query field inside the bar.
final _queryField = find.descendant(
  of: find.byType(FindBar),
  matching: find.byType(EditableText),
);

/// The bar's outer decoration, the first box drawn inside [FindBar].
BoxDecoration _barDecoration(WidgetTester tester) =>
    tester
            .widget<DecoratedBox>(
              find
                  .descendant(
                    of: find.byType(FindBar),
                    matching: find.byType(DecoratedBox),
                  )
                  .first,
            )
            .decoration
        as BoxDecoration;

/// The accessible name of whatever has keyboard focus, read from the nearest
/// [Semantics] above the focused node.
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

Future<void> _pressCtrlF(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

/// A bar above some findable text, in a MaterialApp, with nothing from
/// Material inside the bar itself.
Widget _host(
  FindInPageController controller, {
  String text = 'go go go',
  FindBar? bar,
  VoidCallback? onClose,
  TextDirection? textDirection,
  double? textScale,
}) {
  Widget page = Column(
    children: [
      bar ??
          FindBar(controller: controller, autofocus: false, onClose: onClose),
      FindableText(text, controller: controller),
    ],
  );
  if (textDirection != null) {
    page = Directionality(textDirection: textDirection, child: page);
  }
  return MaterialApp(
    builder: textScale == null
        ? null
        : (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
    home: Scaffold(body: page),
  );
}

/// A WidgetsApp with a navigator, which is what gives it an Overlay.
Widget _widgetsApp(Widget home) => WidgetsApp(
  color: const Color(0xFF000000),
  pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
      PageRouteBuilder<T>(
        settings: settings,
        pageBuilder: (context, _, _) => builder(context),
      ),
  home: home,
);

void main() {
  group('outside Material', () {
    Future<void> openTypeAndStep(
      WidgetTester tester,
      FindInPageController controller,
    ) async {
      await _pressCtrlF(tester);
      expect(find.byType(FindBar), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.enterText(_queryField, 'go');
      await tester.pump();
      expect(controller.matchCount, 3);
      expect(find.text('1/3'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(controller.activeMatchIndex, 1);

      await tester.tap(find.byTooltip('Next match'));
      await tester.pump();
      expect(controller.activeMatchIndex, 2);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(FindBar), findsNothing);
      expect(controller.isOpen, isFalse);
      expect(tester.takeException(), isNull);
    }

    testWidgets('the scope bar works under a bare WidgetsApp', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _widgetsApp(
          FindInPageScope(
            controller: controller,
            child: const Column(children: [Text('go go go')]),
          ),
        ),
      );
      await openTypeAndStep(tester, controller);
    });

    testWidgets('the scope bar works under a CupertinoApp', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: FindInPageScope(
              controller: controller,
              child: const Center(child: Text('go go go')),
            ),
          ),
        ),
      );
      await openTypeAndStep(tester, controller);
    });

    testWidgets('a bar with no Overlay above it still types and navigates, '
        'without tooltips or a selection menu', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        WidgetsApp(
          color: const Color(0xFF000000),
          builder: (context, _) => Column(
            children: [
              FindBar(controller: controller, autofocus: false),
              FindableText('go go go', controller: controller),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(RawTooltip), findsNothing);

      await tester.enterText(_queryField, 'go');
      await tester.pump();
      expect(controller.matchCount, 3);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(controller.activeMatchIndex, 1);
      expect(tester.takeException(), isNull);
    });

    test('no file under lib/ imports Material, Cupertino or material_ui', () {
      final directive = RegExp(
        r'''^\s*(import|export)\s+['"][^'"]*'''
        r'''(material\.dart|cupertino\.dart|material_ui)''',
        multiLine: true,
      );
      // The guard has to be able to fail, or a pass means nothing.
      expect(
        directive.hasMatch("import 'package:flutter/material.dart';"),
        isTrue,
      );
      expect(
        directive.hasMatch("import 'package:material_ui/material_ui.dart';"),
        isTrue,
      );
      expect(
        directive.hasMatch("export 'package:flutter/cupertino.dart' show X;"),
        isTrue,
      );
      expect(
        directive.hasMatch("import 'package:flutter/widgets.dart';"),
        isFalse,
      );

      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList();
      expect(files.length, greaterThanOrEqualTo(15));
      final offenders = [
        for (final file in files)
          if (directive.hasMatch(file.readAsStringSync())) file.path,
      ];
      expect(offenders, isEmpty);
    });
  });

  group('typing and the keyboard', () {
    testWidgets(
      'composing text is searched as it changes, and a commit that keeps '
      'the text does not restart at the first match',
      (tester) async {
        final controller = FindInPageController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _host(controller, text: 'cat category catalog'),
        );
        await tester.showKeyboard(_queryField);

        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'ca',
            selection: TextSelection.collapsed(offset: 2),
            composing: TextRange(start: 0, end: 2),
          ),
        );
        await tester.pump();
        // Pinned behaviour: the query follows the composing text.
        expect(controller.query, 'ca');
        expect(controller.matchCount, 3);

        controller.next();
        await tester.pump();
        expect(controller.activeMatchIndex, 1);

        // Enter during a composition belongs to the input method.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(controller.activeMatchIndex, 1);

        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'ca',
            selection: TextSelection.collapsed(offset: 2),
          ),
        );
        await tester.pump();
        expect(controller.query, 'ca');
        expect(
          controller.activeMatchIndex,
          1,
          reason: 'the committed text is the query that already ran',
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(controller.activeMatchIndex, 2);
      },
    );

    testWidgets('Enter, Shift+Enter, the search action and Escape', (
      tester,
    ) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      var closed = 0;
      await tester.pumpWidget(_host(controller, onClose: () => closed++));
      await tester.enterText(_queryField, 'go');
      await tester.pump();
      expect(controller.activeMatchIndex, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(controller.activeMatchIndex, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pump();
      expect(controller.activeMatchIndex, 2);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(controller.activeMatchIndex, 1);

      // A software keyboard sends its action button instead of a key.
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(controller.activeMatchIndex, 2);
      expect(
        tester.widget<EditableText>(_queryField).focusNode.hasFocus,
        isTrue,
        reason: 'the field keeps focus to type or step again',
      );

      expect(closed, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(closed, 1);
    });

    testWidgets(
      'Escape is left alone when the bar has no onClose, and the close '
      'button is disabled',
      (tester) async {
        final handle = tester.ensureSemantics();
        final controller = FindInPageController();
        addTearDown(controller.dispose);
        var escapes = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    escapes++,
              },
              child: Scaffold(body: FindBar(controller: controller)),
            ),
          ),
        );
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(escapes, 1);

        expect(
          tester.getSemantics(find.bySemanticsLabel('Close')),
          isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
        );
        handle.dispose();
      },
    );

    testWidgets('Tab goes field, toggles, previous, next, close', (
      tester,
    ) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      Widget sized(double width) => _host(
        controller,
        bar: FindBar(
          controller: controller,
          autofocus: false,
          onClose: () {},
          style: FindBarStyle(maxFieldWidth: width),
        ),
      );
      // Start too narrow for the toggles, then widen. The toggles join the
      // bar after the other controls already exist, and still come second.
      tester.view.physicalSize = const Size(250, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(sized(96));
      expect(find.byTooltip('Match case'), findsNothing);
      tester.view.physicalSize = const Size(800, 600);
      await tester.pumpWidget(sized(180));
      expect(find.byTooltip('Match case'), findsOneWidget);

      await tester.showKeyboard(_queryField);
      await tester.pump();

      final order = <String?>[_focusedLabel()];
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        order.add(_focusedLabel());
      }
      expect(order, [
        'Find in page',
        'Match case',
        'Match accents',
        'Previous match',
        'Next match',
        'Close',
      ]);
    });

    testWidgets('a focused button activates with Enter and Space', (
      tester,
    ) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(controller));
      await tester.enterText(_queryField, 'go');
      await tester.pump();
      // Field, then match case, match accents, previous, next.
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(_focusedLabel(), 'Next match');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(controller.activeMatchIndex, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(controller.activeMatchIndex, 2);
    });
  });

  group('semantics', () {
    testWidgets(
      'the field is named by its hint, buttons are labelled buttons, and '
      'the counter is a live region',
      (tester) async {
        final handle = tester.ensureSemantics();
        final controller = FindInPageController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(_host(controller, onClose: () {}));
        await tester.enterText(_queryField, 'go');
        await tester.pump();

        expect(
          tester.getSemantics(_queryField),
          isSemantics(
            label: 'Find in page',
            value: 'go',
            isTextField: true,
            isFocused: true,
          ),
        );
        for (final label in ['Previous match', 'Next match', 'Close']) {
          expect(
            tester.getSemantics(find.bySemanticsLabel(label)),
            isSemantics(
              label: label,
              isButton: true,
              hasEnabledState: true,
              isEnabled: true,
              isFocusable: true,
              hasTapAction: true,
            ),
            reason: label,
          );
        }
        for (final label in ['Match case', 'Match accents']) {
          expect(
            tester.getSemantics(find.bySemanticsLabel(label)),
            isSemantics(
              label: label,
              isButton: true,
              hasToggledState: true,
              isToggled: false,
              hasTapAction: true,
            ),
            reason: label,
          );
        }
        expect(
          tester.getSemantics(find.bySemanticsLabel('Match 1 of 3')),
          isSemantics(isLiveRegion: true),
        );
        // The tooltip text is not read a second time on top of the label.
        expect(
          tester.getSemantics(find.bySemanticsLabel('Next match')).tooltip,
          isEmpty,
        );
        handle.dispose();
      },
    );

    testWidgets('the semantics tap action of a button runs it', (tester) async {
      final handle = tester.ensureSemantics();
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(controller));
      await tester.enterText(_queryField, 'go');
      await tester.pump();

      tester.semantics.tap(find.semantics.byLabel('Next match'));
      await tester.pump();
      expect(controller.activeMatchIndex, 1);
      handle.dispose();
    });
  });

  group('toggles', () {
    testWidgets('toggles and the controller flags follow each other', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(controller, text: 'résumé Résumé resume RESUME'),
      );
      await tester.enterText(_queryField, 'resume');
      await tester.pump();
      expect(controller.matchCount, 4);

      await tester.tap(find.byTooltip('Match case'));
      await tester.pump();
      expect(controller.caseSensitive, isTrue);
      expect(controller.matchCount, 2, reason: 'résumé and resume');
      expect(
        tester.getSemantics(find.bySemanticsLabel('Match case')),
        isSemantics(hasToggledState: true, isToggled: true),
      );

      await tester.tap(find.byTooltip('Match accents'));
      await tester.pump();
      expect(controller.diacriticSensitive, isTrue);
      expect(controller.matchCount, 1, reason: 'resume alone');
      expect(
        tester.getSemantics(find.bySemanticsLabel('Match accents')),
        isSemantics(hasToggledState: true, isToggled: true),
      );

      // And back the other way: the controller drives the toggles.
      controller.search('resume', caseSensitive: false);
      await tester.pump();
      expect(controller.matchCount, 2, reason: 'resume and RESUME');
      expect(
        tester.getSemantics(find.bySemanticsLabel('Match case')),
        isSemantics(hasToggledState: true, isToggled: false),
      );
      controller.search('resume', diacriticSensitive: false);
      await tester.pump();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Match accents')),
        isSemantics(hasToggledState: true, isToggled: false),
      );
      expect(controller.matchCount, 4);
      handle.dispose();
    });

    testWidgets('constructor flags switch each toggle off', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      Future<void> pumpWith({required bool matchCase, required bool accents}) {
        return tester.pumpWidget(
          _host(
            controller,
            bar: FindBar(
              controller: controller,
              autofocus: false,
              showMatchCase: matchCase,
              showMatchAccents: accents,
            ),
          ),
        );
      }

      await pumpWith(matchCase: false, accents: true);
      expect(find.byTooltip('Match case'), findsNothing);
      expect(find.byTooltip('Match accents'), findsOneWidget);

      await pumpWith(matchCase: true, accents: false);
      expect(find.byTooltip('Match case'), findsOneWidget);
      expect(find.byTooltip('Match accents'), findsNothing);

      await pumpWith(matchCase: false, accents: false);
      expect(find.byTooltip('Match case'), findsNothing);
      expect(find.byTooltip('Match accents'), findsNothing);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'at text scale $scale the toggles show exactly when they fit beside '
        'a field of the minimum width',
        (tester) async {
          final controller = FindInPageController();
          addTearDown(controller.dispose);
          const style = FindBarStyle(
            padding: EdgeInsets.all(8),
            buttonSize: 32,
            minFieldWidth: 96,
          );
          var shown = 0;
          var hidden = 0;
          for (var width = 240.0; width <= 520; width += 4) {
            await tester.pumpWidget(
              MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: width),
                    child: FindBar(
                      controller: controller,
                      autofocus: false,
                      style: style,
                    ),
                  ),
                ),
              ),
            );
            if (controller.query.isEmpty) {
              await tester.enterText(_queryField, 'q');
              await tester.pump();
            }
            expect(tester.takeException(), isNull, reason: 'width $width');

            // Measured from the laid-out tree, independently of the bar's own
            // arithmetic: the counter as painted, and buttons of buttonSize.
            final counter = tester.getSize(
              find.byKey(const ValueKey('counter')),
            );
            final room = width - 16;
            final fits = room >= 96 + 4 + counter.width + 5 * 32;
            final showsToggles = find
                .byTooltip('Match case')
                .evaluate()
                .isNotEmpty;
            expect(showsToggles, fits, reason: 'width $width');
            if (showsToggles) {
              shown++;
              expect(
                tester.getSize(_queryField).width,
                greaterThanOrEqualTo(96),
                reason: 'toggles must never squeeze the field, width $width',
              );
            } else {
              hidden++;
            }
          }
          // Both sides of the threshold were exercised.
          expect(shown, greaterThan(0));
          expect(hidden, greaterThan(0));
        },
      );
    }
  });

  group('layout', () {
    testWidgets('the bar mirrors under right-to-left text', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          controller,
          text: 'שלום עולם שלום',
          textDirection: TextDirection.rtl,
        ),
      );
      // The placeholder sits at the start of the field, which is its right.
      final field = tester.getRect(_queryField);
      final hint = tester.getRect(find.text('Find in page'));
      expect((field.right - hint.right).abs(), lessThan(1));

      await tester.enterText(_queryField, 'שלום');
      await tester.pump();
      expect(controller.matchCount, 2);
      expect(
        tester
            .state<EditableTextState>(_queryField)
            .renderEditable
            .textDirection,
        TextDirection.rtl,
      );

      final close = tester.getCenter(find.byTooltip('Close'));
      final next = tester.getCenter(find.byTooltip('Next match'));
      final matchCase = tester.getCenter(find.byTooltip('Match case'));
      expect(close.dx, lessThan(next.dx));
      expect(next.dx, lessThan(matchCase.dx));
      expect(matchCase.dx, lessThan(tester.getCenter(_queryField).dx));

      // Tab order stays logical: the field comes first.
      await tester.showKeyboard(_queryField);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_focusedLabel(), 'Match case');
    });

    testWidgets('textScaler 2.0 scales the text and nothing overflows', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      Future<({double fieldHeight, double counterHeight})> measure(
        double scale,
      ) async {
        final controller = FindInPageController();
        addTearDown(controller.dispose);
        // A fresh tree keeps the last run's text out of the field.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          _host(controller, text: 'word word', textScale: scale),
        );
        await tester.enterText(_queryField, 'word');
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'scale $scale');
        expect(find.text('1/2'), findsOneWidget);
        return (
          fieldHeight: tester.getSize(_queryField).height,
          counterHeight: tester.getSize(find.text('1/2')).height,
        );
      }

      final normal = await measure(1.0);
      final large = await measure(2.0);
      expect(large.counterHeight, closeTo(normal.counterHeight * 2, 1));
      expect(large.fieldHeight, closeTo(normal.fieldHeight * 2, 1));
      expect(
        tester.renderObject<RenderParagraph>(find.text('1/2')).textScaler,
        const TextScaler.linear(2.0),
      );
    });
  });

  group('style', () {
    testWidgets('defaults follow the platform brightness', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(controller));
      expect(
        _barDecoration(tester).color,
        FindBarStyle.fallback(Brightness.light).backgroundColor,
      );

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pump();
      expect(
        _barDecoration(tester).color,
        FindBarStyle.fallback(Brightness.dark).backgroundColor,
      );
    });

    double contrast(Color a, Color b) {
      final la = a.computeLuminance() + 0.05;
      final lb = b.computeLuminance() + 0.05;
      return la > lb ? la / lb : lb / la;
    }

    /// The colors the bar actually paints its text in, against its surface.
    Future<void> expectReadable(WidgetTester tester, String reason) async {
      final surface = _barDecoration(tester).color!;
      final painted = <String, Color>{
        'query': tester.widget<EditableText>(_queryField).style.color!,
        'placeholder': tester
            .widget<Text>(find.text('Find in page'))
            .style!
            .color!,
      };
      await tester.enterText(_queryField, 'go');
      await tester.pump();
      painted['counter'] = tester.widget<Text>(find.text('1/3')).style!.color!;
      for (final MapEntry(:key, :value) in painted.entries) {
        expect(
          contrast(value, surface),
          greaterThanOrEqualTo(4.5),
          reason: '$reason $key $value on $surface',
        );
      }
      final resolved = FindBarTheme.resolve(
        tester.element(find.byType(FindBar)),
        tester.widget<FindBar>(find.byType(FindBar)).style,
      );
      expect(
        contrast(resolved.tooltipTextStyle!.color!, resolved.tooltipColor!),
        greaterThanOrEqualTo(4.5),
        reason: '$reason tooltip',
      );
    }

    for (final brightness in Brightness.values) {
      testWidgets('default colors are readable on a $brightness system', (
        tester,
      ) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final controller = FindInPageController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(_host(controller));
        await expectReadable(tester, '$brightness');
      });
    }

    testWidgets(
      'a style that sets only the surface and foreground keeps the rest '
      'readable against them',
      (tester) async {
        final controller = FindInPageController();
        addTearDown(controller.dispose);
        const ink = Color(0xFFF8FAFC);
        await tester.pumpWidget(
          FindBarTheme(
            style: const FindBarStyle(
              backgroundColor: Color(0xFF0F172A),
              foregroundColor: ink,
              hintColor: Color(0xFF94A3B8),
            ),
            child: _host(controller),
          ),
        );
        expect(tester.widget<EditableText>(_queryField).style.color, ink);
        await expectReadable(tester, 'custom');
        final resolved = FindBarTheme.resolve(
          tester.element(find.byType(FindBar)),
        );
        expect(resolved.hoverColor, ink.withValues(alpha: 0.10));
        expect(resolved.tooltipColor, ink);
      },
    );

    testWidgets('the bar style wins over FindBarTheme, which wins over the '
        'defaults', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      const themed = Color(0xFF102030);
      const own = Color(0xFF405060);
      const themeBorder = Border.fromBorderSide(
        BorderSide(color: Color(0xFFAA0000)),
      );

      await tester.pumpWidget(
        FindBarTheme(
          style: const FindBarStyle(
            backgroundColor: themed,
            border: themeBorder,
          ),
          child: _host(controller),
        ),
      );
      expect(_barDecoration(tester).color, themed);
      expect(_barDecoration(tester).border, themeBorder);

      await tester.pumpWidget(
        FindBarTheme(
          style: const FindBarStyle(
            backgroundColor: themed,
            border: themeBorder,
          ),
          child: _host(
            controller,
            bar: FindBar(
              controller: controller,
              autofocus: false,
              style: const FindBarStyle(backgroundColor: own),
            ),
          ),
        ),
      );
      expect(_barDecoration(tester).color, own);
      expect(_barDecoration(tester).border, themeBorder);
      expect(
        _barDecoration(tester).borderRadius,
        FindBarStyle.fallback(Brightness.light).borderRadius,
      );
    });

    test('merge lays text styles over each other', () {
      final merged = FindBarStyle.fallback(
        Brightness.light,
      ).merge(const FindBarStyle(textStyle: TextStyle(fontSize: 20)));
      expect(merged.textStyle!.fontSize, 20);
      expect(merged.textStyle!.fontWeight, FontWeight.w400);
      expect(merged.textStyle!.inherit, isFalse);
    });
  });

  group('context menu', () {
    testWidgets('a long press offers the field\'s actions where the platform '
        'has no menu of its own', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(controller));
      await tester.enterText(_queryField, 'hello world');
      await tester.pump();

      await tester.longPress(_queryField);
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Select all'), findsOneWidget);

      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      final selection = tester
          .widget<EditableText>(_queryField)
          .controller
          .selection;
      expect(selection.start, 0);
      expect(selection.end, 11);
    });

    testWidgets(
      'iOS shows the system menu where it is supported',
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      (tester) async {
        final calls = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            calls.add(call.method);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final controller = FindInPageController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(supportsShowingSystemContextMenu: true),
              child: child!,
            ),
            home: Scaffold(body: FindBar(controller: controller)),
          ),
        );
        await tester.enterText(_queryField, 'hello');
        await tester.pump();
        tester.state<EditableTextState>(_queryField).showToolbar();
        await tester.pump();

        expect(find.byType(SystemContextMenu), findsOneWidget);
        expect(calls, contains('ContextMenu.showSystemContextMenu'));
      },
    );
  });

  group('FindInPageScope.barBuilder', () {
    testWidgets(
      'the scope shows the built bar, hands it the controller, and closes '
      'it through onClose and Escape',
      (tester) async {
        final controller = FindInPageController();
        addTearDown(controller.dispose);
        FindSession? seen;
        VoidCallback? close;

        await tester.pumpWidget(
          _widgetsApp(
            FindInPageScope(
              controller: controller,
              barBuilder: (context, session, onClose) {
                seen = session;
                close = onClose;
                return const SizedBox(key: ValueKey('custom bar'), width: 40);
              },
              child: const Text('go go go'),
            ),
          ),
        );
        expect(find.byKey(const ValueKey('custom bar')), findsNothing);

        controller.open();
        await tester.pump();
        expect(find.byKey(const ValueKey('custom bar')), findsOneWidget);
        expect(find.byType(FindBar), findsNothing);
        expect(identical(seen, controller), isTrue);

        close!();
        await tester.pump();
        expect(find.byKey(const ValueKey('custom bar')), findsNothing);
        expect(controller.isOpen, isFalse);

        controller.open();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(find.byKey(const ValueKey('custom bar')), findsNothing);
        expect(controller.isOpen, isFalse);
      },
    );

    testWidgets('a builder can return a restyled FindBar for the session', (
      tester,
    ) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      const fill = Color(0xFF223344);
      await tester.pumpWidget(
        _widgetsApp(
          FindInPageScope(
            controller: controller,
            barBuilder: (context, session, onClose) => FindBar(
              controller: session,
              onClose: onClose,
              style: const FindBarStyle(backgroundColor: fill),
            ),
            child: const Text('go go go'),
          ),
        ),
      );
      await _pressCtrlF(tester);
      expect(_barDecoration(tester).color, fill);
      await tester.enterText(_queryField, 'go');
      await tester.pump();
      expect(controller.matchCount, 3);
    });
  });
}
