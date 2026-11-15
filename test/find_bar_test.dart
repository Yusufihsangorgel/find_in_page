import 'package:find_in_page/find_in_page.dart';
import 'package:find_in_page/src/find_bar_parts.dart';
import 'package:flutter/foundation.dart';
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

/// A session that records what a bar asks of it and counts its listeners.
class _RecordingSession extends ChangeNotifier implements FindSession {
  _RecordingSession({this.query = '', this.matchCount = 0});

  final List<String> calls = [];
  int listeners = 0;

  @override
  String query;

  @override
  int matchCount;

  @override
  int? activeMatchIndex;

  @override
  bool caseSensitive = false;

  @override
  bool diacriticSensitive = false;

  @override
  bool isOpen = true;

  @override
  void search(String query, {bool? caseSensitive, bool? diacriticSensitive}) {
    calls.add('search $query');
    this.query = query;
    notifyListeners();
  }

  @override
  void next() => calls.add('next');

  @override
  void previous() => calls.add('previous');

  @override
  void selectMatch(int index) => calls.add('selectMatch $index');

  @override
  void close() => calls.add('close');

  /// Makes [index] active the way a session of its own would, without
  /// recording a call.
  void selectActive(int index) {
    activeMatchIndex = index;
    notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    listeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners--;
    super.removeListener(listener);
  }
}

/// Whether the platform the test runs as asks for large touch targets.
bool _touch() => switch (defaultTargetPlatform) {
  TargetPlatform.android ||
  TargetPlatform.fuchsia ||
  TargetPlatform.iOS => true,
  TargetPlatform.linux ||
  TargetPlatform.macOS ||
  TargetPlatform.windows => false,
};

/// The hit size of a bar button with the default style, by platform alone.
/// A browser test gets the same sizes for the platform it overrides.
double _hitSize() => switch (defaultTargetPlatform) {
  TargetPlatform.android || TargetPlatform.fuchsia => 48,
  TargetPlatform.iOS => 44,
  TargetPlatform.linux || TargetPlatform.macOS || TargetPlatform.windows => 32,
};

double _contrast(Color a, Color b) {
  final la = a.computeLuminance() + 0.05;
  final lb = b.computeLuminance() + 0.05;
  return la > lb ? la / lb : lb / la;
}

/// The bar button labelled [label].
Finder _button(String label) => find.byWidgetPredicate(
  (widget) => widget is FindBarIconButton && widget.label == label,
);

/// The box that paints the fill of [button].
Finder _fillOf(Finder button) => find.descendant(
  of: button,
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is DecoratedBox &&
        widget.position == DecorationPosition.background,
  ),
);

/// The glyph painted inside [button].
Finder _glyphOf(Finder button) => find.descendant(
  of: button,
  matching: find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter is FindBarGlyphPainter,
  ),
);

Color _fillColor(WidgetTester tester, Finder button) =>
    (tester.widget<DecoratedBox>(_fillOf(button)).decoration as BoxDecoration)
        .color!;

/// The fill and glyph colors of the button labelled [label], with the fill
/// laid over [surface].
({Color fill, Color glyph}) _buttonColors(
  WidgetTester tester,
  String label,
  Color surface,
) {
  final button = _button(label);
  final painter =
      tester.widget<CustomPaint>(_glyphOf(button)).painter!
          as FindBarGlyphPainter;
  return (
    fill: Color.alphaBlend(_fillColor(tester, button), surface),
    glyph: painter.color,
  );
}

/// A bar for [session], or an empty page when [session] is null.
Widget _sessionHost(FindSession? session) => MaterialApp(
  home: Scaffold(
    body: Column(
      children: [
        if (session != null)
          FindBar(
            key: const ValueKey('bar'),
            controller: session,
            autofocus: false,
          ),
      ],
    ),
  ),
);

/// Sends [value] from the input method and lets the bar react.
Future<void> _imeSends(WidgetTester tester, TextEditingValue value) async {
  tester.testTextInput.updateEditingValue(value);
  await tester.pump();
}

Future<void> _pressShiftEnter(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

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
  });

  group('typing and the keyboard', () {
    testWidgets('text an input method is composing is searched as it '
        'changes', (tester) async {
      final session = _RecordingSession();
      addTearDown(session.dispose);
      await tester.pumpWidget(_sessionHost(session));
      await tester.showKeyboard(_queryField);

      // A keyboard that composes each Latin word as it is typed.
      await _imeSends(
        tester,
        const TextEditingValue(
          text: 'ca',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      expect(session.calls, ['search ca']);
      await _imeSends(
        tester,
        const TextEditingValue(
          text: 'cat',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 0, end: 3),
        ),
      );
      expect(session.calls, ['search ca', 'search cat']);

      // Committing the word as it stands searches nothing new.
      await _imeSends(
        tester,
        const TextEditingValue(
          text: 'cat',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      expect(session.calls, ['search ca', 'search cat']);

      // A reading converted to a kanji on commit is searched in both forms.
      await _imeSends(
        tester,
        const TextEditingValue(
          text: 'catko',
          selection: TextSelection.collapsed(offset: 5),
          composing: TextRange(start: 3, end: 5),
        ),
      );
      await _imeSends(
        tester,
        const TextEditingValue(
          text: 'cat子',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );
      expect(session.calls, [
        'search ca',
        'search cat',
        'search catko',
        'search cat子',
      ]);
      expect(session.query, 'cat子');
    });

    testWidgets('Enter and Shift+Enter go to the input method while it '
        'composes', (tester) async {
      final session = _RecordingSession(matchCount: 3);
      addTearDown(session.dispose);
      await tester.pumpWidget(_sessionHost(session));
      await tester.enterText(_queryField, 'ca');
      await tester.pump();

      await _imeSends(
        tester,
        const TextEditingValue(
          text: 'cat',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 2, end: 3),
        ),
      );
      expect(session.calls, ['search ca', 'search cat']);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pump();
      await _pressShiftEnter(tester);
      expect(session.calls, ['search ca', 'search cat']);

      await _imeSends(
        tester,
        const TextEditingValue(
          text: 'cat',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await _pressShiftEnter(tester);
      expect(session.calls, ['search ca', 'search cat', 'next', 'previous']);
    });

    testWidgets('a commit that leaves the text equal to the query does not '
        'search again', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(controller, text: 'cat category catalog'));
      await tester.enterText(_queryField, 'ca');
      await tester.pump();
      controller.next();
      await tester.pump();
      expect(controller.activeMatchIndex, 1);

      // The input method takes the word back into a composition and commits
      // it unchanged.
      await _imeSends(
        tester,
        const TextEditingValue(
          text: 'ca',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      await _imeSends(
        tester,
        const TextEditingValue(
          text: 'ca',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      expect(controller.query, 'ca');
      expect(
        controller.activeMatchIndex,
        1,
        reason: 'a search would restart at the first match',
      );
    });

    testWidgets('typing the text a programmatic search already ran does not '
        'search again', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(controller, text: 'cat category catalog'));
      await tester.enterText(_queryField, 'ca');
      await tester.pump();

      // The field has focus and keeps what the user typed.
      controller.search('cat');
      controller.next();
      await tester.pump();
      expect(tester.widget<EditableText>(_queryField).controller.text, 'ca');
      expect(controller.activeMatchIndex, 1);

      await tester.enterText(_queryField, 'cat');
      await tester.pump();
      expect(
        controller.activeMatchIndex,
        1,
        reason: 'a search would restart at the first match',
      );
    });

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

    for (final brightness in Brightness.values) {
      testWidgets('a switched on toggle stands out from a switched off one on '
          'a $brightness system', (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final controller = FindInPageController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(_host(controller));
        final surface = _barDecoration(tester).color!;

        for (final label in ['Match case', 'Match accents']) {
          final off = _buttonColors(tester, label, surface);
          await tester.tap(find.byTooltip(label));
          await tester.pump();
          final on = _buttonColors(tester, label, surface);
          expect(
            tester.getSemantics(find.bySemanticsLabel(label)),
            isSemantics(hasToggledState: true, isToggled: true),
          );
          // WCAG 1.4.11 asks 3 to 1 of what tells the two states apart.
          expect(
            _contrast(on.fill, off.fill),
            greaterThanOrEqualTo(3),
            reason: '$label fill ${on.fill} against ${off.fill}',
          );
          expect(
            _contrast(on.glyph, on.fill),
            greaterThanOrEqualTo(4.5),
            reason: '$label glyph ${on.glyph} on ${on.fill}',
          );
          expect(
            _contrast(off.glyph, off.fill),
            greaterThanOrEqualTo(4.5),
            reason: '$label glyph ${off.glyph} on ${off.fill}',
          );
        }
      });
    }

    testWidgets('the focus ring stays apart from the fill of a switched on '
        'toggle', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(controller));
      await tester.showKeyboard(_queryField);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_focusedLabel(), 'Match case');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(controller.caseSensitive, isTrue);

      final style = FindBarTheme.resolve(tester.element(find.byType(FindBar)));
      final button = _button('Match case');
      final ring = tester.widget<DecoratedBox>(
        find.descendant(
          of: button,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.position == DecorationPosition.foreground,
          ),
        ),
      );
      final border = (ring.decoration as BoxDecoration).border! as Border;
      expect(border.top.color, style.accentColor);
      expect(border.top.width, 2);
      final painted = tester.getRect(find.byTooltip('Match case'));
      final fill = tester.getRect(_fillOf(button));
      expect(fill, painted.deflate(4), reason: 'a gap of 2 inside the ring');
      expect(_fillColor(tester, button), style.accentColor);
    });

    testWidgets(
      'buttons take taps across the touch target of the platform and keep '
      'their painted size',
      variant: TargetPlatformVariant.all(),
      (tester) async {
        final controller = FindInPageController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(_host(controller));
        await tester.enterText(_queryField, 'go');
        await tester.pump();

        final hit = _hitSize();
        for (final key in ['matchCase', 'previous', 'next', 'close']) {
          expect(
            tester.getSize(find.byKey(ValueKey(key))),
            Size.square(hit),
            reason: key,
          );
        }
        final painted = tester.getRect(find.byTooltip('Next match'));
        expect(painted.size, const Size.square(32));
        expect(
          tester.getSize(_glyphOf(_button('Next match'))),
          const Size.square(18),
        );

        // A tap just inside each edge of the hit area runs the button.
        final reach = hit / 2 - 1;
        for (final offset in [
          Offset(reach, 0),
          Offset(-reach, 0),
          Offset(0, reach),
          Offset(0, -reach),
        ]) {
          final before = controller.activeMatchIndex!;
          await tester.tapAt(painted.center + offset);
          await tester.pump();
          expect(
            controller.activeMatchIndex,
            (before + 1) % 3,
            reason: '$offset',
          );
        }
      },
    );

    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'at text scale $scale the toggles show beside a field of the minimum '
        'width when they fit there, and a touch platform shows the options '
        'button when they do not',
        variant: const TargetPlatformVariant({
          TargetPlatform.android,
          TargetPlatform.macOS,
        }),
        (tester) async {
          final controller = FindInPageController();
          addTearDown(controller.dispose);
          const style = FindBarStyle(
            padding: EdgeInsets.all(8),
            buttonSize: 32,
            minFieldWidth: 96,
          );
          var beside = 0;
          var hidden = 0;
          for (var width = 240.0; width <= 600; width += 4) {
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
            // arithmetic. A button is measured with its hit area, which is
            // wider than buttonSize on a touch platform.
            final counter = tester.getSize(
              find.byKey(const ValueKey('counter')),
            );
            final button = tester
                .getSize(find.byKey(const ValueKey('previous')))
                .width;
            final room = width - 16;
            // The counter is measured as laid out, which on a touch platform
            // is the room set aside for it.
            final fitsBeside = room >= 96 + 4 + counter.width + 5 * button;
            final showsToggles = find
                .byTooltip('Match case')
                .evaluate()
                .isNotEmpty;
            expect(showsToggles, fitsBeside, reason: 'width $width');
            expect(
              find.byTooltip('Search options').evaluate().isNotEmpty,
              _touch() && !fitsBeside,
              reason: 'the options button stands in for them, width $width',
            );
            if (!showsToggles) {
              hidden++;
              continue;
            }
            beside++;
            expect(
              tester.getRect(find.byTooltip('Match case')).center.dy,
              closeTo(tester.getRect(_queryField).center.dy, 0.5),
              reason: 'in the field row, width $width',
            );
            expect(
              tester.getSize(_queryField).width,
              greaterThanOrEqualTo(96),
              reason: 'toggles must never squeeze the field, width $width',
            );
          }
          // Both sides of the threshold were exercised.
          expect(beside, greaterThan(0));
          expect(hidden, greaterThan(0));
        },
      );
    }

    testWidgets(
      'from 200 to 400 wide at text scale 1 and 2 nothing overflows, and '
      'every button shown keeps the hit size of the platform',
      variant: TargetPlatformVariant.all(),
      (tester) async {
        final minimumHit = _hitSize();
        final controller = FindInPageController();
        addTearDown(controller.dispose);
        // Twelve matches give a counter of 1/12.
        final text = List.filled(12, 'go').join(' ');
        var stacked = 0;
        for (final scale in [1.0, 2.0]) {
          for (var width = 200.0; width <= 400; width += 20) {
            final reason = 'width $width, text scale $scale';
            await tester.pumpWidget(
              MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: width),
                      child: FindBar(controller: controller, autofocus: false),
                    ),
                    FindableText(text, controller: controller),
                  ],
                ),
              ),
            );
            if (controller.query.isEmpty) {
              await tester.enterText(_queryField, 'go');
              await tester.pump();
            }
            expect(tester.takeException(), isNull, reason: reason);
            expect(find.text('1/12'), findsOneWidget, reason: reason);

            final buttons = find.byType(FindBarIconButton).evaluate();
            expect(buttons.length, greaterThanOrEqualTo(3), reason: reason);
            for (final button in buttons) {
              final hit = (button.renderObject! as RenderBox).size;
              final label = (button.widget as FindBarIconButton).label;
              expect(
                hit.shortestSide,
                greaterThanOrEqualTo(minimumHit),
                reason: '$label, $reason',
              );
            }
            expect(
              tester.getSize(_queryField).width,
              greaterThanOrEqualTo(_touch() ? 80 : 96),
              reason: reason,
            );
            final field = tester.getRect(_queryField);
            final next = tester.getRect(find.byTooltip('Next match'));
            if (next.top >= field.bottom) stacked++;
            // A touch platform offers the toggles beside the field or behind
            // the options button.
            if (_touch()) {
              expect(
                find.byTooltip('Match case').evaluate().length +
                    find.byTooltip('Search options').evaluate().length,
                1,
                reason: reason,
              );
            }
          }
        }
        // The narrow end needs the second row, and the wide end does not.
        expect(stacked, inExclusiveRange(0, 22));
      },
    );

    // Room for one row with the options button, and too little for the
    // toggles beside the field, on Android and on iOS in the test font.
    Widget optionsHost(
      FindInPageController controller, {
      VoidCallback? onClose,
    }) => MaterialApp(
      home: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 396),
            child: FindBar(
              controller: controller,
              autofocus: false,
              onClose: onClose,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: FindableText(
                List.filled(120, 'go').join(' '),
                controller: controller,
              ),
            ),
          ),
        ],
      ),
    );

    Future<List<String?>> tabOrder(WidgetTester tester, int steps) async {
      await tester.showKeyboard(_queryField);
      final order = <String?>[_focusedLabel()];
      for (var i = 0; i < steps; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        order.add(_focusedLabel());
      }
      return order;
    }

    testWidgets(
      'on a touch platform the options button shows and hides the toggles '
      'in a second row and keeps focus where it was',
      variant: const TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
      (tester) async {
        final handle = tester.ensureSemantics();
        final controller = FindInPageController();
        addTearDown(controller.dispose);
        var closed = 0;
        await tester.pumpWidget(
          optionsHost(controller, onClose: () => closed++),
        );
        await tester.enterText(_queryField, 'go');
        await tester.pump();
        expect(find.text('1/120'), findsOneWidget);
        final oneRow = tester.getSize(find.byType(FindBar)).height;
        expect(oneRow, _hitSize() + 8, reason: 'one row');
        expect(find.byTooltip('Match case'), findsNothing);
        expect(
          tester.getSemantics(find.bySemanticsLabel('Search options')),
          isSemantics(
            isButton: true,
            hasToggledState: true,
            isToggled: false,
            hasTapAction: true,
          ),
        );
        expect(
          tester.getSize(_button('Search options')),
          Size.square(_hitSize()),
        );
        expect(await tabOrder(tester, 4), [
          'Find in page',
          'Search options',
          'Previous match',
          'Next match',
          'Close',
        ]);

        // From the keyboard. Focus stays on the button both ways.
        for (var i = 0; i < 3; i++) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await tester.pump();
        }
        expect(_focusedLabel(), 'Search options');
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(_focusedLabel(), 'Search options');
        expect(
          tester.getSemantics(find.bySemanticsLabel('Search options')),
          isSemantics(hasToggledState: true, isToggled: true),
        );
        final previous = tester.getRect(find.byTooltip('Previous match'));
        for (final label in ['Match case', 'Match accents']) {
          final toggle = tester.getRect(find.byTooltip(label));
          expect(toggle.top, greaterThan(previous.bottom), reason: label);
        }
        expect(
          tester.getSize(find.byType(FindBar)).height,
          2 * _hitSize() + 8,
          reason: 'two rows',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(_focusedLabel(), 'Search options');
        expect(find.byTooltip('Match case'), findsNothing);
        expect(tester.getSize(find.byType(FindBar)).height, oneRow);

        // By touch, with the toggles last in the tab order.
        await tester.tap(find.byTooltip('Search options'));
        await tester.pump();
        expect(await tabOrder(tester, 6), [
          'Find in page',
          'Search options',
          'Previous match',
          'Next match',
          'Close',
          'Match case',
          'Match accents',
        ]);
        await tester.tap(find.byTooltip('Match case'));
        await tester.pump();
        expect(controller.caseSensitive, isTrue);
        await tester.tap(find.byTooltip('Match accents'));
        await tester.pump();
        expect(controller.diacriticSensitive, isTrue);

        // Escape on a toggle hides the row and hands focus to the button.
        // Escape there closes the bar as usual.
        expect(_focusedLabel(), 'Match accents');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(find.byTooltip('Match case'), findsNothing);
        expect(_focusedLabel(), 'Search options');
        expect(closed, 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(closed, 1);
        expect(tester.takeException(), isNull);
        handle.dispose();
      },
    );

    testWidgets(
      'Escape on a toggle in the scope bar hides the options and leaves find '
      'open',
      variant: TargetPlatformVariant.only(TargetPlatform.android),
      (tester) async {
        tester.view.physicalSize = const Size(412, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final controller = FindInPageController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: FindInPageScope(
              controller: controller,
              child: Text(List.filled(120, 'go').join(' ')),
            ),
          ),
        );
        controller.open();
        await tester.pump();
        await tester.enterText(_queryField, 'go');
        await tester.pump();
        await tester.tap(find.byTooltip('Search options'));
        await tester.pump();
        await tabOrder(tester, 5);
        expect(_focusedLabel(), 'Match case');

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(controller.isOpen, isTrue);
        expect(find.byTooltip('Match case'), findsNothing);
        expect(_focusedLabel(), 'Search options');

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(controller.isOpen, isFalse);
        expect(find.byType(FindBar), findsNothing);
      },
    );

    testWidgets(
      'on a touch platform the first letter typed changes neither the height '
      'of the bar nor the width of the field',
      variant: const TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
      (tester) async {
        final controller = FindInPageController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(optionsHost(controller));
        final bar = tester.getSize(find.byType(FindBar));
        final field = tester.getSize(_queryField);
        expect(find.byTooltip('Search options'), findsOneWidget);

        await tester.enterText(_queryField, 'g');
        await tester.pump();
        expect(find.text('1/120'), findsOneWidget);
        expect(tester.getSize(find.byType(FindBar)), bar);
        expect(tester.getSize(_queryField), field);
        expect(find.byTooltip('Search options'), findsOneWidget);
      },
    );

    testWidgets(
      'a focused toggle keeps focus and stays on screen when the bar narrows',
      variant: TargetPlatformVariant.only(TargetPlatform.android),
      (tester) async {
        final controller = FindInPageController();
        addTearDown(controller.dispose);
        Widget sized(double width) => MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width),
              child: FindBar(controller: controller, autofocus: false),
            ),
          ),
        );
        await tester.pumpWidget(sized(800));
        await tester.showKeyboard(_queryField);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(_focusedLabel(), 'Match case');
        final focused = FocusManager.instance.primaryFocus;
        final field = tester.getRect(_queryField);
        expect(
          tester.getRect(find.byTooltip('Match case')).top,
          lessThan(field.bottom),
        );

        await tester.pumpWidget(sized(344));
        expect(
          tester.getRect(find.byTooltip('Match case')).top,
          greaterThan(tester.getRect(_queryField).bottom),
        );
        expect(FocusManager.instance.primaryFocus, same(focused));
        expect(_focusedLabel(), 'Match case');
      },
    );

    testWidgets(
      'the query field takes taps across the hit height of the platform',
      variant: TargetPlatformVariant.all(),
      (tester) async {
        final controller = FindInPageController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(_host(controller));
        final node = tester.widget<EditableText>(_queryField).focusNode;
        final line = tester.getRect(_queryField);
        final reach = _hitSize() / 2 - 1;
        expect(line.height, lessThan(2 * reach), reason: 'one line of text');
        for (final dy in [-reach, reach]) {
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          expect(node.hasFocus, isFalse);
          await tester.tapAt(Offset(line.center.dx, line.center.dy + dy));
          await tester.pump();
          expect(node.hasFocus, isTrue, reason: '$dy from the line');
        }
      },
    );

    testWidgets(
      'the narrowest bar that fits is three hit sizes plus the padding',
      variant: TargetPlatformVariant.all(),
      (tester) async {
        final minimum = 3 * _hitSize() + 16;
        expect(minimum, switch (defaultTargetPlatform) {
          TargetPlatform.android || TargetPlatform.fuchsia => 160,
          TargetPlatform.iOS => 148,
          _ => 112,
        }, reason: 'the widths the FindBar dartdoc states');
        final controller = FindInPageController();
        addTearDown(controller.dispose);
        Widget sized(double width, double scale) => MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: width),
                child: FindBar(controller: controller, autofocus: false),
              ),
              FindableText('go go go', controller: controller),
            ],
          ),
        );
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(sized(minimum, scale));
          if (controller.query.isEmpty) {
            await tester.enterText(_queryField, 'go');
            await tester.pump();
          }
          expect(tester.takeException(), isNull, reason: 'scale $scale');
          for (final button in find.byType(FindBarIconButton).evaluate()) {
            expect(
              (button.renderObject! as RenderBox).size.shortestSide,
              greaterThanOrEqualTo(_hitSize()),
            );
          }
          // A fresh tree, since a RenderFlex reports its overflow once.
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(sized(minimum - 1, scale));
          expect(
            tester.takeException(),
            isA<FlutterError>(),
            reason: 'one pixel narrower overflows, scale $scale',
          );
        }
      },
    );
  });

  group('layout', () {
    testWidgets('moving the buttons to a second row and back keeps the field '
        'and a focused button as they were', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      Widget sized(double width) => MaterialApp(
        home: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width),
              child: FindBar(controller: controller, autofocus: false),
            ),
            FindableText('go go go', controller: controller),
          ],
        ),
      );
      bool stacked() =>
          tester.getRect(find.byTooltip('Next match')).top >=
          tester.getRect(_queryField).bottom;

      await tester.pumpWidget(sized(800));
      await tester.showKeyboard(_queryField);
      await tester.enterText(_queryField, 'go');
      await tester.pump();
      final field = tester.state<EditableTextState>(_queryField);
      expect(stacked(), isFalse);

      await tester.pumpWidget(sized(200));
      expect(stacked(), isTrue);
      expect(tester.state<EditableTextState>(_queryField), same(field));
      expect(field.widget.focusNode.hasFocus, isTrue);
      expect(field.textEditingValue.text, 'go');

      // Field, options, previous, then next. The toggles are behind the
      // options button at this width.
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      }
      await tester.pump();
      expect(_focusedLabel(), 'Next match');
      final focused = FocusManager.instance.primaryFocus;

      await tester.pumpWidget(sized(800));
      expect(stacked(), isFalse);
      expect(FocusManager.instance.primaryFocus, same(focused));
      expect(_focusedLabel(), 'Next match');
      expect(tester.takeException(), isNull);
    });

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
      // A browser reports the brightness of the system it runs on.
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
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
    // On the web the browser shows its own menu over the field.
  }, skip: kIsWeb);

  group('sessions', () {
    testWidgets('a bar removed while its session lives stops listening to '
        'it', (tester) async {
      final session = _RecordingSession(query: 'go', matchCount: 3);
      addTearDown(session.dispose);
      final other = _RecordingSession();
      addTearDown(other.dispose);

      await tester.pumpWidget(_sessionHost(session));
      expect(session.listeners, greaterThan(0));

      // A new session takes the listeners over.
      await tester.pumpWidget(_sessionHost(other));
      expect(session.listeners, 0);
      expect(other.listeners, greaterThan(0));

      await tester.pumpWidget(_sessionHost(null));
      expect(other.listeners, 0);
      other.search('later');
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('matches with no active match show and announce the same '
        'numbers', (tester) async {
      final handle = tester.ensureSemantics();
      final session = _RecordingSession(query: 'go', matchCount: 3);
      addTearDown(session.dispose);
      await tester.pumpWidget(_sessionHost(session));

      expect(find.text('0/3'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Match 0 of 3')),
        isSemantics(isLiveRegion: true),
      );

      session.selectActive(1);
      await tester.pump();
      expect(find.text('2/3'), findsOneWidget);
      expect(find.bySemanticsLabel('Match 2 of 3'), findsOneWidget);
      handle.dispose();
    });
  });

  group('FindInPageScope.barBuilder', () {
    testWidgets(
      'the scope shows the built bar, hands it the controller, and closes '
      'it through the session and Escape',
      (tester) async {
        final controller = FindInPageController();
        addTearDown(controller.dispose);
        FindSession? seen;

        await tester.pumpWidget(
          _widgetsApp(
            FindInPageScope(
              controller: controller,
              barBuilder: (context, session) {
                seen = session;
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

        seen!.close();
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
            barBuilder: (context, session) => FindBar(
              controller: session,
              onClose: session.close,
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
