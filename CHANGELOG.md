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
