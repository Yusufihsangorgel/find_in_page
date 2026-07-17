import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

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
abstract interface class FindableSource {
  /// The plain text to search in.
  String get findableText;

  /// A context inside the widget, used to scroll the active match into
  /// view. Return null when the widget is not currently mounted.
  BuildContext? get findableContext;
}

/// Drives a find-in-page session: holds the query, computes matches across
/// all registered sources, and tracks the active match.
///
/// Sources register themselves in build order, which for a typical page is
/// top-to-bottom visual order; matches and navigation follow that order.
class FindInPageController extends ChangeNotifier {
  /// Creates a controller with no active search.
  FindInPageController();

  final List<FindableSource> _sources = [];
  final List<FindMatch> _matches = [];
  final Map<FindableSource, List<FindMatch>> _matchesBySource = {};
  String _query = '';
  bool _caseSensitive = false;
  int? _activeIndex;
  bool _recomputeScheduled = false;
  bool _disposed = false;

  /// The current search query. Empty when no search is active.
  String get query => _query;

  /// Whether matching is case sensitive. Defaults to false.
  bool get caseSensitive => _caseSensitive;

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
  void search(String query, {bool? caseSensitive}) {
    _query = query;
    if (caseSensitive != null) _caseSensitive = caseSensitive;
    _recompute(resetActive: true);
  }

  /// Clears the query, all matches, and the active match.
  void clearSearch() => search('');

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
  void register(FindableSource source) {
    if (_sources.contains(source)) return;
    _sources.add(source);
    if (_query.isNotEmpty) _scheduleRecompute();
  }

  /// Removes [source] from the search domain.
  void unregister(FindableSource source) {
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
    if (_query.isNotEmpty) {
      final needle = _caseSensitive ? _query : _query.toLowerCase();
      for (final source in _sources) {
        final haystack = _caseSensitive
            ? source.findableText
            : source.findableText.toLowerCase();
        var offset = 0;
        while (true) {
          final index = haystack.indexOf(needle, offset);
          if (index < 0) break;
          final match = FindMatch._(source, index, index + needle.length);
          _matches.add(match);
          (_matchesBySource[source] ??= []).add(match);
          offset = index + needle.length;
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
      final context = match.source.findableContext;
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
