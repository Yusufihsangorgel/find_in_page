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
