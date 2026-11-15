import 'package:flutter/widgets.dart';

/// The part of a find-in-page session that a find bar reads and drives.
///
/// A find bar needs the query, the match count, the active match and the
/// two matching options, and it needs to search, step between matches and
/// close. This interface is that contract and nothing more. The built-in
/// `FindBar` depends only on it, and a bar written for a design system can
/// do the same.
///
/// The `FindInPageController` class implements it. Listeners are notified
/// whenever any value read here changes.
abstract interface class FindSession implements Listenable {
  /// The current search query. Empty when no search is active.
  String get query;

  /// Total number of matches for [query].
  int get matchCount;

  /// Zero-based index of the active match, or null when nothing matches.
  int? get activeMatchIndex;

  /// Whether matching respects letter case.
  bool get caseSensitive;

  /// Whether a letter has to be typed with its own accent to match.
  bool get diacriticSensitive;

  /// Whether find is open.
  bool get isOpen;

  /// Starts or updates a search for [query].
  ///
  /// An empty [query] clears the session. Either flag keeps its current
  /// value when it is not passed. The first match becomes active.
  void search(String query, {bool? caseSensitive, bool? diacriticSensitive});

  /// Makes the next match active, wrapping after the last one.
  void next();

  /// Makes the previous match active, wrapping before the first one.
  void previous();

  /// Makes the match at [index] active in one step.
  ///
  /// The index is zero-based and must be less than [matchCount].
  void selectMatch(int index);

  /// Closes find and clears the search.
  void close();
}

/// Builds the find bar that `FindInPageScope` shows when find opens.
///
/// The [session] is the scope's controller. Calling [onClose] closes find
/// the same as the built-in bar's close button does.
typedef FindBarBuilder =
    Widget Function(
      BuildContext context,
      FindSession session,
      VoidCallback onClose,
    );
