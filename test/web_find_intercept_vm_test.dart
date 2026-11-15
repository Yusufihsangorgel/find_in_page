/// The web Ctrl+F intercept as seen from outside a browser.
///
/// These tests pin that this isolate is not a browser. The capture listener
/// lives behind a conditional import. On the VM it is a no-op, and a
/// desktop or mobile build does not grow a DOM dependency or start
/// swallowing keys it did not swallow before.
@TestOn('vm')
library;

import 'package:find_in_page/find_in_page.dart';
import 'package:find_in_page/src/web_find_intercept.dart';
import 'package:flutter/foundation.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(Widget child) => MaterialApp(home: child);

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

  testWidgets('the other platform modifier is not find, off web', (
    tester,
  ) async {
    await tester.pumpWidget(app(const FindInPageScope(child: SizedBox())));

    expect(
      await sendChord(tester, modifier: otherModifier()),
      isFalse,
      reason: 'only web treats Control and Meta as equivalent',
    );
    expect(find.byType(FindBar), findsNothing);
  }, variant: platforms);

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

  testWidgets('mounting a scope does not attach a DOM listener on the VM', (
    tester,
  ) async {
    expect(kIsWeb, isFalse);
    await tester.pumpWidget(app(const FindInPageScope(child: SizedBox())));
    expect(webFindInterceptIsAttached, isFalse);

    await tester.pumpWidget(app(const SizedBox()));
    expect(webFindInterceptIsAttached, isFalse);
  });
}
