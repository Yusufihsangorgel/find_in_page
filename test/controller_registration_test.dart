import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:find_in_page/find_in_page.dart';

class _EqualSource implements FindableSource {
  _EqualSource(this.id, this.findableText);

  final String id;

  @override
  final String findableText;

  @override
  BuildContext? get findableContext => null;

  @override
  bool operator ==(Object other) => other is _EqualSource && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

// Post-frame callbacks run only inside a frame, and no widget tree here
// schedules one.
Future<void> _pumpFrame(WidgetTester tester) async {
  tester.binding.scheduleFrame();
  await tester.pump();
}

void main() {
  testWidgets('registration_order_equality_and_snapshot_contract',
      (tester) async {
    final first = _EqualSource('shared', 'needle needle');
    final second = _EqualSource('second', 'needle');
    final equal = _EqualSource('shared', 'needle replacement');
    final discoveredEqual = _EqualSource('shared', 'needle discovered copy');
    final discovered = _EqualSource('discovered', 'needle discovered');
    final controller = FindInPageController();
    var firstRevealCalls = 0;
    var duplicateRevealCalls = 0;
    var discoveryCalls = 0;

    controller
      ..register(first, reveal: () => firstRevealCalls++)
      ..register(second)
      ..setDiscovery(() {
        discoveryCalls++;
        return [discoveredEqual, discovered];
      });
    final snapshot = controller.registeredSources;

    controller.search('needle');
    expect(controller.matchCount, 4);
    expect(identical(controller.activeMatch!.source, first), isTrue);
    expect(controller.discoveredSources, [discovered]);
    await _pumpFrame(tester);
    expect(firstRevealCalls, 1);

    controller.next();
    expect(identical(controller.activeMatch!.source, first), isTrue);
    await _pumpFrame(tester);
    expect(firstRevealCalls, 2);
    controller.next();
    expect(identical(controller.activeMatch!.source, second), isTrue);
    controller.next();
    expect(identical(controller.activeMatch!.source, discovered), isTrue);

    expect(snapshot, hasLength(2));
    expect(identical(snapshot[0], first), isTrue);
    expect(identical(snapshot[1], second), isTrue);
    expect(() => snapshot.add(equal), throwsUnsupportedError);

    var notifications = 0;
    void listener() => notifications++;

    controller.addListener(listener);
    final discoveryCallsBeforeDuplicate = discoveryCalls;
    controller.register(equal, reveal: () => duplicateRevealCalls++);
    await _pumpFrame(tester);
    expect(notifications, 0);
    expect(discoveryCalls, discoveryCallsBeforeDuplicate);
    expect(controller.registeredSources, hasLength(2));
    expect(identical(controller.registeredSources[0], first), isTrue);

    controller.removeListener(listener);
    controller.next();
    await _pumpFrame(tester);
    expect(firstRevealCalls, 3);
    expect(duplicateRevealCalls, 0);

    controller.unregister(equal);
    await _pumpFrame(tester);
    expect(controller.registeredSources, hasLength(1));
    expect(identical(controller.registeredSources.single, second), isTrue);
    expect(controller.discoveredSources, [discoveredEqual, discovered]);

    controller.register(equal);
    await _pumpFrame(tester);
    final afterReregistration = controller.registeredSources;
    expect(afterReregistration, hasLength(2));
    expect(identical(afterReregistration[0], second), isTrue);
    expect(identical(afterReregistration[1], equal), isTrue);
    expect(controller.discoveredSources, [discovered]);

    expect(snapshot, hasLength(2));
    expect(identical(snapshot[0], first), isTrue);
    expect(identical(snapshot[1], second), isTrue);
    controller.dispose();
  });
}
