## 2.2.1

- Tests for the two pieces a caller writing their own highlighted widget uses,
  neither of which was named anywhere in the suite. `FindInPageScope.maybeOf`
  returns null where `of` throws, and picks the nearest scope when they nest.
  `FindInPageController.isActive` compares by identity, so a match held from
  before a re-search does not light up again on offsets that happen to line up.
  No behaviour changed.

## 2.2.0

- Search now matches across accents, the dotless and dotted i, and the eszett:
  `resume` finds `résumé`, `isik` finds `IŞIK`, `strasse` finds `Straße`. This
  changes what a search returns, so a query that used to find nothing in
  Turkish, German or French text will now find something. Pass
  `diacriticSensitive: true` to `search` for the old exact behaviour; it is
  sticky the same way `caseSensitive` is.
- Highlight offsets stay correct when a letter folds to more than one, which
  is the part that is easy to get wrong. A match ending inside such a letter
  covers the whole letter rather than stopping one character short, and a
  match living entirely inside one is reported once rather than dropped or
  counted twice.
- `test/fold_table_test.dart` walks the whole fold table rather than sampling
  it: every expansion against every substring of what it folds to, all hundred
  adjacent pairs, and two invariants checked over 1,204 reported matches.

## 2.1.0

- The README now answers, in its first screen, why to reach for this rather
  than the zero-dependency route or the package that already owns the
  category. Both answers carry the file and line, or the issue number, that
  a reader can check. A "reach for it when" list and a sentence on when to
  skip it follow, because a page that only argues for itself is not useful
  for deciding.

## 2.0.2

- The README shows the lazy list the matcher walks, drawn by
  `tool/lazy_list_figure.dart`. Docs and tooling only.

## 2.0.1

No library code changed in this release. `lib/` is byte-identical to 2.0.0.

- The first screenshot on the package page is now `doc/searchable-grid.png`,
  which shows the headline feature: an `AppBar`, a `ListTile`, a `DataTable`
  and a `Text.rich`, none of them wrapped, each with a search match the package
  highlighted during a real run. `tool/searchable_grid.dart` builds those
  widgets, types into the find bar and captures what it painted;
  `tool/searchable_grid.sh` regenerates the file. The demo gif stays at the top
  of the README, which pub.dev serves from GitHub.
- The README opens with the situation the package exists for: mobile has no
  find bar, and on Flutter web the browser's own bar searches a canvas with no
  text in it. A new "Text you never wrapped" section shows discovery working on
  widgets the caller does not own, with the figure above and the widget tree it
  was captured from, and names the nearest packages on pub.dev along with the
  smaller question they answer.
- The web-renderer advice was stale. Readers who need the browser's Ctrl+F to
  find their content were pointed at the HTML renderer, and that renderer and
  its flag are gone from `flutter build web`. The advice now is to prerender
  that content as real HTML, and the renderer names are current: `canvaskit`
  and `skwasm`, both painting text into a canvas.
- The package description is a single-line scalar now. A folded YAML block
  joins its lines with a space, and when the fold lands inside a word the
  package page shows the split verbatim, which is how a sibling package shipped
  a caption reading "millis econds".
- README media no longer ship in the archive. pub.dev reads README images from
  GitHub through its image proxy and takes nothing from the archive but the
  `screenshots:` files. The download drops from 1004 KB to 73 KB.

## 2.0.0

**Wrap your page and it works.** Until now every string had to be wrapped in a
`FindableText` to be searchable, and a page that was not wrapped reported `0/0`
with no error and no hint. That is the first thing a new user saw, and it looked
like the package was broken. On a realistic page with an `AppBar` title, a
`Text.rich`, a `SelectableText`, a `ListTile` and a `DataTable` cell, all five
occurrences of the search term were missed.

`FindInPageScope` now finds the text rendered inside it, whether or not you
wrapped it, including text inside widgets you did not write. The same page now
reports 5 of 5. The integration is one widget:

```dart
FindInPageScope(child: MyPage())
```

Matches in discovered text are highlighted by an overlay painted on top, in the
yellow and orange a browser uses, since restyling a widget we do not own is not
possible. `FindableText` still highlights inline by restyling its own spans, and
the two compose; so does `FindableListView`, which remains the way to reach rows
of a lazy list that were never built.

### Breaking

- A scope that previously found nothing now finds the text on the page, so
  `matchCount` changes for anyone who was not wrapping their content. Pass
  `FindInPageScope(autoDiscover: false)` for the old behaviour.

### New

- `ExcludeFromFind`, which keeps a subtree out of the search. Use it for
  navigation, footers and debug banners, and inside custom widgets that report
  their own text.
- `FindInPageScope.highlightColor` and `activeHighlightColor`.
- `RenderedTextSource` and its two variants are exported, so a custom find UI
  can ask a discovered match for its rectangles.

### Deliberately not searched

- Editable fields. A browser's find bar does not match inside `<input>` values
  either; an editable field is a control, not content. `SelectableText` is
  read-only and is searched.
- Obscured fields, so a password is never matched.
- Icons. Flutter draws them as glyphs inside a paragraph, so a naive sweep
  registers every chevron as a one-character searchable string. Text made only
  of Private Use Area characters is filtered out.

### Also

- The README now says plainly, above the fold, that this does not fix the
  browser's own Ctrl+F and that nothing written in Dart can. That limit was
  true before and was not stated anywhere.

## 1.0.0

The API is stable. No behaviour changes; this freezes the surface after an
adversarial pass that drove the controller directly rather than reading it, and
pins what it found as tests.

Verified by execution and now covered by `test/controller_contract_test.dart`:
case sensitivity is opt-in and sticky across searches; matches never overlap;
the offsets a match reports index the text you supplied, not the folded copy the
case-insensitive search compares against, so a match after an emoji still slices
correctly; an empty or unmatchable query clears the session and the active index
with it; `next` and `previous` wrap in both directions; the active index never
goes stale when a source's text changes and its matches disappear; and
unregistering a source drops its matches.

`FindBar`, `FindInPageScope`, `FindableText`, `FindableListView`, `FindMatch`,
`FindableRecord` and `FindInPageController` are `final`; `FindableSource` stays
an `abstract interface` because implementing it is how you add your own source.
Flutter is the only dependency.

## 0.5.1

- Add `example/README.md` for pub.dev's Example tab. It describes both halves of
  the demo — eager `FindableText` content and a 2,000-row `FindableListView`
  where every row is searchable though only the visible ones are built — with
  the demo gif and the accurate `FindableListView` snippet. Docs only.

## 0.5.0

- Seal the four widget classes: `FindBar`, `FindInPageScope`, `FindableText`
  and `FindableListView` are now `final`. The 0.4.0 note said the controller
  was the last open type; that was wrong — these four were still open. None is
  meant to be subtyped, nothing in the package, its tests or its example
  extends any of them, and freezing them open would make every future added
  parameter a breaking change for an implementer. `FindMatch`, `FindableRecord`
  and `FindInPageController` were already `final`; `FindableSource` stays an
  `abstract interface` for callers to implement. That completes the modifier
  decision across the public surface, so nothing is left open by accident at a
  1.0.0 freeze. No behaviour change.

## 0.4.0

- Mark `FindInPageController` as `final`, ahead of a 1.0.0 freeze. It was the
  one type in the package still open: `FindMatch` and `FindableRecord` are
  already `final` and `FindableSource` is an `abstract interface` for callers
  to implement. The controller is a plain, zero-dependency object that nothing
  in the package, its tests or its example subtypes, and the regex support the
  README plans will add members to exactly this class — additions that would
  otherwise break anyone who had implemented it. Sealing after 1.0.0 would take
  a major version; unsealing later would not. Fake it in a test by
  constructing a real one rather than implementing it. No behaviour change.

## 0.3.0

- Add `FindableListView`, a `ListView.builder` whose whole backing list is
  searchable, not just the items currently built. Plain `ListView.builder` +
  `FindableText` only ever registers the handful of items in the build/cache
  area; scrolling registers and unregisters items as they build and dispose,
  so `matchCount` drifts mid-session and anything scrolled past is missed
  entirely. `FindableListView` reads each item's text straight from the
  backing data up front, so the full list counts toward `matchCount`
  regardless of what is built, and scrolling does not change it. Revealing a
  match animates a `ScrollController` to the item's index instead of
  `Scrollable.ensureVisible`, since an off-screen item has no live widget;
  see the class docs for the itemExtent requirement this implies.
- Add `FindableRecord`, the `FindableSource` used by `FindableListView`:
  text supplied directly instead of read from a live widget, with no
  `findableContext`.
- Add an optional `reveal` callback to `FindInPageController.register`, for
  sources that cannot provide a live `findableContext`. Non-breaking:
  existing `register(source)` calls are unaffected.

## 0.2.0

- The match counter is now announced to screen readers. It is the find bar's
  entire feedback loop, and it was visual only: focus stays in the query field
  while typing, so a screen reader never reached the counter and the user had
  no way to tell whether a query matched anything or which match they were on.
  `FindBar` marks it a live region and announces "Match 1 of 3" or "No matches"
  as the count and active match change, keeping the terse `1/3` out of the
  announcement since it reads badly aloud while staying on screen.
- Add `FindBar.matchStatusLabel` to localize that announcement, defaulting to
  English as the existing tooltips do.

## 0.1.3

- Docs: sharpen the pub.dev description to lead with the value and the terms people search.

## 0.1.2

- Fix the demo GIF in the README, which used a relative path and did not render
  on the pub.dev package page. It now uses the same absolute raw URL as the
  banner.

## 0.1.1

- Docs: tightened the README wording and visuals.

## 0.1.0

Initial release.

- `FindInPageScope`: Ctrl+F / Cmd+F opens a find bar overlay, Escape
  closes it; provides the controller to descendants.
- `FindableText`: `Text` replacement (supports the common `Text`
  parameters) with match highlighting and a distinct active-match color.
- `FindBar`: standalone Material search bar with a match counter and
  previous/next/close controls.
- `FindInPageController`: query, case sensitivity, match list, wrapping
  navigation, and scroll-into-view for the active match.
- `FindableSource`: interface for making custom widgets searchable.
