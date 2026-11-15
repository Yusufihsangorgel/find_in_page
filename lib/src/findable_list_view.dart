import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'exclude_from_find.dart';
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
typedef FindableListItemBuilder =
    Widget Function(
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
/// [scrollController] to the matched item's offset, then hands the item's
/// matches to [itemBuilder] once it is built so it can render the
/// highlight itself. The offset is the sum of the extents of the items
/// before it, which is why every item's extent has to be known without
/// building it. Pass [itemExtent] when all items are the same size, or
/// [itemExtentBuilder] when they are not.
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
/// - Every item's extent must be known up front, as [itemExtent] or as
///   [itemExtentBuilder]. The list lays items out at exactly those
///   extents, the same as `ListView.builder` does with either argument.
///   Items that size themselves from their content are not supported.
/// - `FindableListView` does not highlight matches itself; [itemBuilder]
///   gets the match offsets and renders them, since it already owns the
///   item's layout. There is no `FindableText`-style automatic span
///   rendering here.
final class FindableListView extends StatefulWidget {
  /// Creates a searchable lazy list.
  ///
  /// Exactly one of [itemExtent] and [itemExtentBuilder] must be given.
  const FindableListView({
    required this.itemCount,
    required this.findableTextOf,
    required this.itemBuilder,
    this.itemExtent,
    this.itemExtentBuilder,
    this.scrollController,
    this.findController,
    this.padding,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.physics,
    super.key,
  }) : assert(
         (itemExtent == null) != (itemExtentBuilder == null),
         'Pass exactly one of itemExtent and itemExtentBuilder.',
       );

  /// Number of items in the backing list.
  final int itemCount;

  /// The searchable text for the item at [index], read straight from the
  /// backing data. Called for every index up front, not only built ones.
  final String Function(int index) findableTextOf;

  /// Builds the item at [index]. See [FindableListItemBuilder].
  final FindableListItemBuilder itemBuilder;

  /// The fixed extent of every item along [scrollDirection].
  ///
  /// A match in item `i` is revealed at `i * itemExtent`. Leave this null
  /// and pass [itemExtentBuilder] when items differ in size.
  final double? itemExtent;

  /// The extent of each item along [scrollDirection], by index.
  ///
  /// Passed to `ListView.builder` unchanged, and summed over the items
  /// before a match to find the offset that reveals it. It is called with
  /// the list's current layout dimensions, both by the list and by the
  /// reveal. Leave this null when [itemExtent] is given.
  final ItemExtentBuilder? itemExtentBuilder;

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
        next.register(
          _records[i],
          reveal: () => _revealIndex(i),
          anchor: context,
        );
      }
    }
  }

  void _growRecordsTo(int count) {
    while (_records.length < count) {
      final index = _records.length;
      final record = FindableRecord(widget.findableTextOf(index));
      _records.add(record);
      _controller?.register(
        record,
        reveal: () => _revealIndex(index),
        anchor: context,
      );
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

  /// Where item [index] starts, measured from where item 0 starts.
  double _offsetOfIndex(int index, ScrollPosition position) {
    final fixed = widget.itemExtent;
    if (fixed != null) return index * fixed;
    final extentOf = widget.itemExtentBuilder!;
    final dimensions = SliverLayoutDimensions(
      scrollOffset: position.pixels < 0 ? 0 : position.pixels,
      precedingScrollExtent: 0,
      viewportMainAxisExtent: position.viewportDimension,
      crossAxisExtent: _crossAxisExtent(),
    );
    var offset = 0.0;
    for (var i = 0; i < index; i++) {
      // Null marks the end of the list for ListView as well.
      final extent = extentOf(i, dimensions);
      if (extent == null) break;
      offset += extent;
    }
    return offset;
  }

  /// The cross-axis extent the list's items are laid out in.
  double _crossAxisExtent() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return 0;
    final padding =
        widget.padding?.resolve(Directionality.maybeOf(context)) ??
        EdgeInsets.zero;
    return switch (widget.scrollDirection) {
      Axis.vertical => box.size.width - padding.horizontal,
      Axis.horizontal => box.size.height - padding.vertical,
    };
  }

  void _revealIndex(int index) {
    final scrollController = _scrollController;
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    final target =
        _offsetOfIndex(index, position) - position.viewportDimension * 0.3;
    scrollController.animateTo(
      target.clamp(0.0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    // Every row's text is registered up front, built or not, so discovery must
    // not also read the rows that happen to be on screen.
    return ExcludeFromFind(
      child: ListView.builder(
        controller: _scrollController,
        itemCount: widget.itemCount,
        itemExtent: widget.itemExtent,
        itemExtentBuilder: widget.itemExtentBuilder,
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
                context,
                index,
                matches,
                activeMatchIndex,
              );
            },
          );
        },
      ),
    );
  }
}
