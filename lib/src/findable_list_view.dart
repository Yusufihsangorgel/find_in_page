import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'findable_record.dart';
import 'scope.dart';

/// Builds one item of a [FindableListView].
///
/// [matches] are that item's matches of the current query, in the same
/// [FindMatch.start]/[FindMatch.end] offsets as the text
/// [FindableListView.findableTextOf] returned for [index]; it is empty
/// when there is no search or the item has none. [activeMatchIndex] is the
/// index into [matches] that is the active match, or null when none of
/// them is.
///
/// Rendering the highlight is the builder's job, `FindableListView` only
/// hands over where the matches are; see the package README for an
/// example.
typedef FindableListItemBuilder = Widget Function(
  BuildContext context,
  int index,
  List<FindMatch> matches,
  int? activeMatchIndex,
);

/// A `ListView.builder` whose entire backing list is searchable, not just
/// the items currently built.
///
/// Plain `ListView.builder` only ever has the handful of items in its
/// build/cache area on screen; a `FindableText` inside one registers on
/// build and unregisters on dispose, so scrolling constantly changes the
/// search domain and the match count drifts. `FindableListView` instead
/// reads [findableTextOf] for every index up front and registers it
/// directly with the controller, so the whole list counts toward
/// [FindInPageController.matchCount] regardless of what is built, and
/// scrolling does not change it.
///
/// Because an off-screen match has no live widget, revealing it cannot use
/// `Scrollable.ensureVisible`. [FindableListView] instead animates
/// [scrollController] to the matched item's index, then hands the item's
/// matches to [itemBuilder] once it is built so it can render the
/// highlight itself.
///
/// ```dart
/// FindableListView(
///   itemCount: items.length,
///   itemExtent: 56,
///   findableTextOf: (index) => items[index],
///   itemBuilder: (context, index, matches, activeMatchIndex) => ListTile(
///     title: Text(items[index]),
///   ),
/// )
/// ```
///
/// ## Limits
///
/// - Every item must have the same extent, given as [itemExtent]: reveal
///   is `index * itemExtent`, which is exact only for a uniform height (or
///   width), the same constraint `ListView.builder(itemExtent: ...)`
///   already has. There is no support for variable-height items.
/// - `FindableListView` does not highlight matches itself; [itemBuilder]
///   gets the match offsets and renders them, since it already owns the
///   item's layout. There is no `FindableText`-style automatic span
///   rendering here.
final class FindableListView extends StatefulWidget {
  /// Creates a searchable lazy list.
  const FindableListView({
    required this.itemCount,
    required this.findableTextOf,
    required this.itemBuilder,
    required this.itemExtent,
    this.scrollController,
    this.findController,
    this.padding,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.physics,
    super.key,
  });

  /// Number of items in the backing list.
  final int itemCount;

  /// The searchable text for the item at [index], read straight from the
  /// backing data. Called for every index up front, not only built ones.
  final String Function(int index) findableTextOf;

  /// Builds the item at [index]. See [FindableListItemBuilder].
  final FindableListItemBuilder itemBuilder;

  /// The fixed extent of every item along [scrollDirection]. Required to
  /// turn a match's index into a scroll offset without building the item
  /// first; see the Limits section on the class.
  final double itemExtent;

  /// Animated to reveal matches. When null, `FindableListView` creates and
  /// owns one.
  final ScrollController? scrollController;

  /// Explicit controller. When null, the controller is looked up from the
  /// nearest [FindInPageScope].
  final FindInPageController? findController;

  /// See [ListView.padding].
  final EdgeInsetsGeometry? padding;

  /// See [ListView.scrollDirection].
  final Axis scrollDirection;

  /// See [ListView.reverse].
  final bool reverse;

  /// See [ListView.physics].
  final ScrollPhysics? physics;

  @override
  State<FindableListView> createState() => _FindableListViewState();
}

class _FindableListViewState extends State<FindableListView> {
  FindInPageController? _controller;
  final List<FindableRecord> _records = [];
  ScrollController? _ownedScrollController;

  ScrollController get _scrollController =>
      widget.scrollController ??
      (_ownedScrollController ??= ScrollController());

  @override
  void initState() {
    super.initState();
    _growRecordsTo(widget.itemCount);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveController();
  }

  @override
  void didUpdateWidget(FindableListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.findController != widget.findController) {
      _resolveController();
    }
    _syncRecords();
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      for (final record in _records) {
        controller.unregister(record);
      }
    }
    _ownedScrollController?.dispose();
    super.dispose();
  }

  void _resolveController() {
    final next = widget.findController ?? FindInPageScope.maybeOf(context);
    if (identical(next, _controller)) return;
    final previous = _controller;
    if (previous != null) {
      for (final record in _records) {
        previous.unregister(record);
      }
    }
    _controller = next;
    if (next != null) {
      for (var i = 0; i < _records.length; i++) {
        next.register(_records[i], reveal: () => _revealIndex(i));
      }
    }
  }

  void _growRecordsTo(int count) {
    while (_records.length < count) {
      final index = _records.length;
      final record = FindableRecord(widget.findableTextOf(index));
      _records.add(record);
      _controller?.register(record, reveal: () => _revealIndex(index));
    }
  }

  /// Keeps the registered records in step with [FindableListView.itemCount]
  /// and [FindableListView.findableTextOf] across rebuilds.
  void _syncRecords() {
    final controller = _controller;
    if (widget.itemCount < _records.length) {
      for (var i = widget.itemCount; i < _records.length; i++) {
        controller?.unregister(_records[i]);
      }
      _records.removeRange(widget.itemCount, _records.length);
    } else if (widget.itemCount > _records.length) {
      _growRecordsTo(widget.itemCount);
    }
    var textChanged = false;
    for (var i = 0; i < _records.length; i++) {
      final text = widget.findableTextOf(i);
      if (_records[i].findableText != text) {
        _records[i].findableText = text;
        textChanged = true;
      }
    }
    if (textChanged) {
      for (final record in _records) {
        controller?.sourceTextChanged(record);
      }
    }
  }

  void _revealIndex(int index) {
    final scrollController = _scrollController;
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    final target = index * widget.itemExtent - position.viewportDimension * 0.3;
    scrollController.animateTo(
      target.clamp(0.0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return ListView.builder(
      controller: _scrollController,
      itemCount: widget.itemCount,
      itemExtent: widget.itemExtent,
      padding: widget.padding,
      scrollDirection: widget.scrollDirection,
      reverse: widget.reverse,
      physics: widget.physics,
      itemBuilder: (context, index) {
        if (controller == null) {
          return widget.itemBuilder(context, index, const [], null);
        }
        return ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final matches = controller.matchesFor(_records[index]);
            int? activeMatchIndex;
            for (var i = 0; i < matches.length; i++) {
              if (controller.isActive(matches[i])) {
                activeMatchIndex = i;
                break;
              }
            }
            return widget.itemBuilder(
                context, index, matches, activeMatchIndex);
          },
        );
      },
    );
  }
}
