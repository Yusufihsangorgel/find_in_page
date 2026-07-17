## 0.1.0

Initial release.

- `FindInPageScope`: Ctrl+F / Cmd+F opens a find bar overlay, Escape
  closes it; provides the controller to descendants.
- `FindableText`: drop-in `Text` replacement with match highlighting and
  a distinct active-match color.
- `FindBar`: standalone Material search bar with a match counter and
  previous/next/close controls.
- `FindInPageController`: query, case sensitivity, match list, wrapping
  navigation, and scroll-into-view for the active match.
- `FindableSource`: interface for making custom widgets searchable.
