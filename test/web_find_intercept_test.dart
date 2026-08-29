import 'package:find_in_page/find_in_page.dart';
import 'package:find_in_page/src/web_find_intercept.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Dart half of the web Ctrl+F intercept, which is all a widget test
/// can see.
///
/// The Flutter web engine calls `keydown.preventDefault()` when a
/// `HardwareKeyboard` handler returns handled. That is the intercept:
/// these tests pin that this package's handler does return handled for
/// the find shortcut, and that it does not when the bar is disabled or
/// there is no scope. Whether a given browser then suppresses its own
/// find bar is not something `flutter test` can observe.
///
/// They also pin that this isolate is not a browser. The capture listener
/// lives behind a conditional import; on the VM it is a no-op, so a
/// desktop or mobile build does not grow a DOM dependency or start
/// swallowing keys it did not swallow before.
void main() {
  Widget app(Widget child) => MaterialApp(home: child);

  LogicalKeyboardKey findModifier() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.iOS:
        return LogicalKeyboardKey.metaLeft;
      default:
        return LogicalKeyboardKey.controlLeft;
    }
  }

  LogicalKeyboardKey otherModifier() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.iOS:
        return LogicalKeyboardKey.controlLeft;
      default:
        return LogicalKeyboardKey.metaLeft;
    }
  }

  Future<bool> sendChord(
    WidgetTester tester, {
    required LogicalKeyboardKey modifier,
  }) async {
    await tester.sendKeyDownEvent(modifier);
    final handled = await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(modifier);
    return handled;
  }

  const platforms = TargetPlatformVariant({
    TargetPlatform.android,
    TargetPlatform.macOS,
  });

  testWidgets(
    'the find shortcut is reported as handled',
    (tester) async {
      await tester.pumpWidget(app(const FindInPageScope(child: SizedBox())));

      final handled = await sendChord(tester, modifier: findModifier());
      await tester.pump();

      expect(handled, isTrue,
          reason: 'the engine maps this bit onto preventDefault on web');
      expect(find.byType(FindBar), findsOneWidget);
    },
    variant: platforms,
  );

  testWidgets(
    'showBar: false with onOpenRequested is still handled',
    (tester) async {
      var opened = 0;
      await tester.pumpWidget(app(
        FindInPageScope(
          showBar: false,
          onOpenRequested: () => opened++,
          child: const SizedBox(),
        ),
      ));

      expect(
        await sendChord(tester, modifier: findModifier()),
        isTrue,
        reason: 'a custom bar is still a replacement for the browser\'s',
      );
      expect(opened, 1);
      expect(find.byType(FindBar), findsNothing);
    },
    variant: platforms,
  );

  testWidgets(
    'does not swallow the key when the bar is disabled',
    (tester) async {
      await tester.pumpWidget(app(
        const FindInPageScope(
          showBar: false,
          child: SizedBox(),
        ),
      ));

      expect(
        await sendChord(tester, modifier: findModifier()),
        isFalse,
        reason: 'no bar and no onOpenRequested: leave the key to the browser',
      );
      expect(find.byType(FindBar), findsNothing);
    },
    variant: platforms,
  );

  testWidgets(
    'does not swallow the key when no scope is mounted',
    (tester) async {
      await tester.pumpWidget(app(const SizedBox()));

      expect(
        await sendChord(tester, modifier: findModifier()),
        isFalse,
      );
      expect(find.byType(FindBar), findsNothing);
    },
    variant: platforms,
  );

  testWidgets(
    'the other platform modifier is not find, off web',
    (tester) async {
      await tester.pumpWidget(app(const FindInPageScope(child: SizedBox())));

      expect(
        await sendChord(tester, modifier: otherModifier()),
        isFalse,
        reason: 'only web treats Control and Meta as equivalent',
      );
      expect(find.byType(FindBar), findsNothing);
    },
    variant: platforms,
  );

  test('the capture listener is not attached on the VM', () {
    expect(kIsWeb, isFalse, reason: 'flutter test is not a browser');
    expect(webFindInterceptIsAttached, isFalse);

    var invoked = false;
    bool shouldIntercept() {
      invoked = true;
      return true;
    }

    installWebFindIntercept(shouldIntercept);
    expect(webFindInterceptIsAttached, isFalse);
    expect(invoked, isFalse, reason: 'the stub never reads the callback');

    uninstallWebFindIntercept(shouldIntercept);
    expect(webFindInterceptIsAttached, isFalse);
  });

  testWidgets('mounting a scope does not attach a DOM listener on the VM',
      (tester) async {
    expect(kIsWeb, isFalse);
    await tester.pumpWidget(app(const FindInPageScope(child: SizedBox())));
    expect(webFindInterceptIsAttached, isFalse);

    await tester.pumpWidget(app(const SizedBox()));
    expect(webFindInterceptIsAttached, isFalse);
  });
}
