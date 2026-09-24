import 'dart:collection';

import 'package:flutter/foundation.dart' show kFlutterMemoryAllocationsEnabled;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'auto_discovery.dart';
import 'text_fold.dart';

/// A single occurrence of the query inside a registered source.
@immutable
final class FindMatch {
  const FindMatch._(this.source, this.start, this.end);

  /// The source widget state this match was found in.
  final FindableSource source;

  /// Start offset (inclusive) in the source's text.
  final int start;

  /// End offset (exclusive) in the source's text.
  final int end;
}

/// Implemented by widget states whose text participates in find-in-page.
///
/// `FindableText` implements this for you; implement it yourself to make a
/// custom widget searchable, and register it with
/// [FindInPageController.register].
///
/// Custom implementations that override `==` must provide a matching
/// `hashCode`, keeping equality and hash values stable while registered.
/// Equal sources must have equal hashes; identity-based implementations need
/// no change.
abstract interface class FindableSource {
  /// The plain text to search in.
  String get findableText;

  /// A context inside the widget, used to scroll the active match into
  /// view. Return null when the widget is not currently mounted.
  BuildContext? get findableContext;
}

/// Internal reveal path for sources that can target a text range precisely.
///
/// This interface stays inside `src`; it is not part of the package exports.
abstract interface class MatchRectangleReveal implements FindableSource {
  /// Scrolls the first text box covering [start]..[end] into view.
  void showMatchOnScreen(int start, int end);
}

/// Drives a find-in-page session: holds the query, computes matches across
/// all registered sources, and tracks the active match.
///
/// Sources register themselves in build order, which for a typical page is
/// top-to-bottom visual order; matches and navigation follow that order.
final class FindInPageController extends ChangeNotifier {
  /// Creates a controller with no active search.
  FindInPageController() {
    if (kFlutterMemoryAllocationsEnabled) {
      ChangeNotifier.maybeDispatchObjectCreation(this);
    }
  }

  final LinkedHashSet<FindableSource> _sources =
      LinkedHashSet<FindableSource>();
  final List<FindMatch> _matches = [];
  final Map<FindableSource, List<FindMatch>> _matchesBySource = {};
  final Map<FindableSource, VoidCallback> _reveals = {};
  List<FindableSource> Function()? _discover;
  List<FindableSource> _discovered = const [];
  String _query = '';
  bool _caseSensitive = false;
  bool _diacriticSensitive = false;
  int? _activeIndex;
  bool _recomputeScheduled = false;
  bool _disposed = false;
  bool _isOpen = false;
  VoidCallback? _openHandler;
  VoidCallback? _closeHandler;

  /// The current search query. Empty when no search is active.
  String get query => _query;

  /// Whether find is open: the enclosing scope's built-in bar is showing, or
  /// a custom UI was told to open through [open].
  ///
  /// Changes notify listeners, like everything else on this controller.
  bool get isOpen => _isOpen;

  /// Whether matching is case sensitive. Defaults to false.
  bool get caseSensitive => _caseSensitive;

  /// Whether a letter has to be typed with its own accent to match. Defaults
  /// to false, so `resume` finds `résumé` and `diyarbakir` finds
  /// `Diyarbakır`.
  ///
  /// The base-letter table covers Latin-1 Supplement and Latin Extended-A,
  /// with capital sharp S (`ẞ`) as the single letter outside those ranges.
  /// It drops combining marks only from U+0300 through U+036F. Casing uses
  /// Dart's `String.toLowerCase`, which does not depend on the locale. It is
  /// not general Unicode normalization or locale-specific collation. The fold
  /// also maps `ı` to `i` and expands `ß` to `ss`; neither is a diacritic.
  bool get diacriticSensitive => _diacriticSensitive;

  /// Total number of matches across all sources.
  int get matchCount => _matches.length;

  /// 0-based index of the active match, or null when there are no matches.
  int? get activeMatchIndex => _activeIndex;

  /// The active match, or null when there are no matches.
  FindMatch? get activeMatch =>
      _activeIndex == null ? null : _matches[_activeIndex!];

  /// Starts or updates a search. An empty [query] clears the session.
  ///
  /// The first match becomes active and is scrolled into view.
  ///
  /// Both flags keep their value until passed again, and they are
  /// independent axes: matching can respect case while ignoring accents, or
  /// the other way round.
  void search(String query, {bool? caseSensitive, bool? diacriticSensitive}) {
    _query = query;
    if (caseSensitive != null) _caseSensitive = caseSensitive;
    if (diacriticSensitive != null) _diacriticSensitive = diacriticSensitive;
    _recompute(resetActive: true);
  }

  /// Clears the query, all matches, and the active match.
  void clearSearch() => search('');

  /// Opens find and sets [isOpen] to true.
  ///
  /// With `FindInPageScope(showBar: true)` (the default) this shows the
  /// scope's built-in bar and moves keyboard focus into its query field, the
  /// same as pressing the find shortcut. With `showBar: false` it calls the
  /// scope's `onOpenRequested` instead, so a custom find UI gets the same
  /// signal the shortcut would have sent it. With no `FindInPageScope`
  /// mounted for this controller, it only sets [isOpen].
  void open() {
    _setOpen(true);
    _openHandler?.call();
  }

  /// Closes find: clears the search (like [clearSearch]), sets [isOpen] to
  /// false, and hides the enclosing scope's built-in bar if it is showing.
  ///
  /// Safe to call when already closed, or with no `FindInPageScope` mounted
  /// for this controller.
  void close() {
    clearSearch();
    _setOpen(false);
    _closeHandler?.call();
  }

  /// Lets the nearest `FindInPageScope` supply what [open] and [close] do
  /// beyond flipping [isOpen]: showing or hiding its bar, or calling
  /// `onOpenRequested`. The scope calls this while mounted and again with
  /// two nulls when it disposes or swaps to a different controller; passing
  /// two nulls also resets [isOpen] to false, since whatever bar this
  /// controller was showing no longer exists.
  // ignore: use_setters_to_change_properties
  void setOpenCloseHandlers(VoidCallback? onOpen, VoidCallback? onClose) {
    _openHandler = onOpen;
    _closeHandler = onClose;
    if (onOpen == null && onClose == null) _setOpen(false);
  }

  void _setOpen(bool value) {
    // A scope's dispose() calls setOpenCloseHandlers(null, null) on a
    // controller it was only handed, not necessarily one it owns; whoever
    // does own it may already have called dispose, in which case this
    // reset must stay quiet rather than hit ChangeNotifier's
    // use-after-dispose assertion.
    if (_disposed || _isOpen == value) return;
    _isOpen = value;
    notifyListeners();
  }

  /// Makes the next match active (wrapping) and scrolls it into view.
  void next() {
    if (_matches.isEmpty) return;
    _activeIndex = ((_activeIndex ?? -1) + 1) % _matches.length;
    _revealActive();
    notifyListeners();
  }

  /// Makes the previous match active (wrapping) and scrolls it into view.
  void previous() {
    if (_matches.isEmpty) return;
    _activeIndex =
        ((_activeIndex ?? 0) - 1 + _matches.length) % _matches.length;
    _revealActive();
    notifyListeners();
  }

  /// Adds [source] to the search domain.
  ///
  /// Safe to call during build; match recomputation is deferred to after
  /// the current frame.
  ///
  /// Pass [reveal] when [source] cannot provide a live `findableContext`
  /// (for example, a lazy list item that is not built yet). It is called
  /// instead of `Scrollable.ensureVisible` when one of [source]'s matches
  /// becomes active, and is responsible for bringing the source into view
  /// itself, typically by animating a `ScrollController`.
  /// `FindableListView` uses this to make off-screen items reachable.
  void register(FindableSource source, {VoidCallback? reveal}) {
    if (!_sources.add(source)) return;
    if (reveal != null) _reveals[source] = reveal;
    if (_query.isNotEmpty) _scheduleRecompute();
  }

  /// Installs the sweep that finds text nobody wrapped.
  ///
  /// `FindInPageScope` sets this to a walk of its own subtree. The callback
  /// runs at recompute time, which is after layout, so what it reports is what
  /// is on screen right now. Passing null turns automatic discovery off and
  /// leaves only explicitly registered sources, which is what
  /// `FindInPageScope(autoDiscover: false)` does.
  ///
  /// Explicit registration wins: a paragraph that belongs to a registered
  /// source is not reported twice.
  // ignore: use_setters_to_change_properties
  void setDiscovery(List<FindableSource> Function()? discover) {
    _discover = discover;
  }

  /// The sources that registered themselves, in registration order.
  ///
  /// Discovery uses this to leave their text alone: a `FindableText` both
  /// registers and renders a paragraph, and counting it twice would double
  /// every match inside it.
  List<FindableSource> get registeredSources => List.unmodifiable(_sources);

  /// The sources found by the last sweep, in visual order.
  ///
  /// The highlight overlay reads this to know what to paint.
  List<FindableSource> get discoveredSources => _discovered;

  /// Removes [source] from the search domain.
  void unregister(FindableSource source) {
    _reveals.remove(source);
    if (_sources.remove(source) && _query.isNotEmpty) _scheduleRecompute();
  }

  /// Tells the controller that [source]'s text changed.
  void sourceTextChanged(FindableSource source) {
    if (_query.isNotEmpty) _scheduleRecompute();
  }

  /// The matches inside [source], ordered by offset. Used by sources to
  /// render highlights.
  List<FindMatch> matchesFor(FindableSource source) =>
      _matchesBySource[source] ?? const [];

  /// Whether [match] is the active one.
  bool isActive(FindMatch match) => identical(activeMatch, match);

  void _scheduleRecompute() {
    if (_recomputeScheduled) return;
    _recomputeScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _recomputeScheduled = false;
      if (!_disposed) _recompute();
    });
  }

  void _recompute({bool resetActive = false}) {
    _matches.clear();
    _matchesBySource.clear();
    _discovered = _query.isEmpty || _discover == null
        ? const []
        : _discover!().where((s) => !_sources.contains(s)).toList();
    final needle = _query.isEmpty
        ? ''
        : foldForSearch(
            _query,
            caseSensitive: _caseSensitive,
            foldToBaseLetters: !_diacriticSensitive,
          ).text;
    // A query of nothing but combining marks is not empty, but folds to a
    // string that is. indexOf finds that at every offset and never advances.
    if (needle.isNotEmpty) {
      for (final source in [..._sources, ..._discovered]) {
        final haystack = foldForSearch(
          source.findableText,
          caseSensitive: _caseSensitive,
          foldToBaseLetters: !_diacriticSensitive,
        );
        var offset = 0;
        while (true) {
          final index = haystack.text.indexOf(needle, offset);
          if (index < 0) break;
          offset = index + needle.length;
          final start = haystack.sourceOffset(index);
          // Rounding up, so that a match whose end falls inside a letter that
          // folded to several covers that whole letter. Searching "Weiß" for
          // "s" highlights the eszett rather than nothing at all, and
          // "Straße" for "stras" highlights "Straß" rather than "Stra".
          final end = haystack.sourceEnd(offset);
          assert(end > start, 'a match must cover at least one character');
          // Step over the whole letter, not just the needle, so that a match
          // living inside an expansion is reported once.
          offset = haystack.resumeAfter(end);
          final match = FindMatch._(source, start, end);
          _matches.add(match);
          (_matchesBySource[source] ??= []).add(match);
        }
      }
    }
    if (_matches.isEmpty) {
      _activeIndex = null;
    } else if (resetActive || _activeIndex == null) {
      _activeIndex = 0;
      _revealActive();
    } else if (_activeIndex! >= _matches.length) {
      _activeIndex = _matches.length - 1;
    }
    notifyListeners();
  }

  void _revealActive() {
    final match = activeMatch;
    if (match == null) return;
    // After the frame, so freshly rebuilt highlights are attached.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      final reveal = _reveals[match.source];
      if (reveal != null) {
        reveal();
        return;
      }
      final source = match.source;
      if (source is RenderedTextSource) {
        // No element to hand to Scrollable.ensureVisible, and aiming at the
        // matched characters beats aiming at the whole paragraph anyway.
        source.showMatchOnScreen(match.start, match.end);
        return;
      }
      if (source is MatchRectangleReveal) {
        source.showMatchOnScreen(match.start, match.end);
        return;
      }
      final context = source.findableContext;
      if (context == null || !context.mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.3,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
