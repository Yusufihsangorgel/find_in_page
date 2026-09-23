import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:find_in_page/find_in_page.dart';

class _ProbeCounters {
  int equalityCalls = 0;
  int hashCodeCalls = 0;
  int textReads = 0;

  void reset() {
    equalityCalls = 0;
    hashCodeCalls = 0;
    textReads = 0;
  }
}

class _ProbeSource implements FindableSource {
  _ProbeSource(this.id, this._counters, this._text);

  final int id;
  final _ProbeCounters _counters;
  final String _text;

  @override
  String get findableText {
    _counters.textReads++;
    return _text;
  }

  @override
  BuildContext? get findableContext => null;

  @override
  bool operator ==(Object other) {
    _counters.equalityCalls++;
    return other is _ProbeSource && other.id == id;
  }

  @override
  int get hashCode {
    _counters.hashCodeCalls++;
    return id;
  }
}

List<_ProbeSource> _makeSources(
  int count,
  _ProbeCounters counters, {
  int startId = 0,
  String text = 'unmatched row',
}) =>
    [
      for (var index = 0; index < count; index++)
        _ProbeSource(startId + index, counters, text),
    ];

void _expectWithinBudget(_ProbeCounters counters, int count) {
  expect(
    counters.equalityCalls,
    lessThanOrEqualTo(32 * count),
    reason: '${counters.equalityCalls} equality calls for $count sources',
  );
  expect(
    counters.hashCodeCalls,
    lessThanOrEqualTo(32 * count),
    reason: '${counters.hashCodeCalls} hash calls for $count sources',
  );
}

void _expectIdentityOrder(
  List<FindableSource> actual,
  List<_ProbeSource> expected,
) {
  expect(actual, hasLength(expected.length));
  for (var index = 0; index < expected.length; index++) {
    expect(identical(actual[index], expected[index]), isTrue);
  }
}

void main() {
  testWidgets('registration_operation_budget', (tester) async {
    for (final count in [512, 2048]) {
      final counters = _ProbeCounters();
      final sources = _makeSources(count, counters);
      final controller = FindInPageController();

      counters.reset();
      for (final source in sources) {
        controller.register(source);
      }

      _expectIdentityOrder(
        controller.registeredSources,
        sources,
      );
      _expectWithinBudget(counters, count);
      controller.dispose();
    }
  });

  testWidgets('reverse_unregistration_operation_budget', (tester) async {
    for (final count in [512, 2048]) {
      final counters = _ProbeCounters();
      final sources = _makeSources(count, counters);
      final controller = FindInPageController();
      for (final source in sources) {
        controller.register(source);
      }

      counters.reset();
      for (var index = sources.length - 1; index >= 0; index--) {
        controller.unregister(sources[index]);
      }

      expect(controller.registeredSources, isEmpty);
      _expectWithinBudget(counters, count);
      controller.dispose();
    }
  });

  testWidgets('discovery_membership_operation_budget', (tester) async {
    for (final count in [512, 2048]) {
      final counters = _ProbeCounters();
      final registered = _makeSources(count, counters);
      final discovered = _makeSources(
        count,
        counters,
        startId: count,
        text: 'also unmatched',
      );
      final controller = FindInPageController();
      for (final source in registered) {
        controller.register(source);
      }
      controller.setDiscovery(() => discovered);
      await tester.pump();

      counters.reset();
      controller.search('absent');
      await tester.pump();

      expect(controller.matchCount, 0);
      _expectIdentityOrder(controller.registeredSources, registered);
      _expectIdentityOrder(controller.discoveredSources, discovered);
      expect(counters.textReads, 2 * count);
      _expectWithinBudget(counters, count);
      controller.dispose();
    }
  });
}
