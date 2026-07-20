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
