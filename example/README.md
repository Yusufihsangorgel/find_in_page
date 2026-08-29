# find_in_page example

The example app in `lib/main.dart` is the live demo of the package. The find
bar is on the screen when the page loads, already searching, so the first
thing a visitor sees is matches highlighted inside widgets that were never
wrapped for this package.

It shows all three ways text becomes searchable under one `FindInPageScope`:

1. Nothing at all. The `AppBar` title, the `ListTile`s, the `DataTable`, and
   the `Text.rich` block are ordinary Flutter widgets. Searching `release`
   hits all of them because the scope reads the text rendered inside it.

   ```dart
   FindInPageScope(child: MyPage())
   ```

2. `FindableText`, when you want the match highlighted by restyling the text
   itself rather than by an overlay drawn on top of it.

3. `FindableListView`, for a lazy 2,000-row list, where rows that were never
   built have no rendered text to discover. The bottom navigation switches to
   that list and searches `row 1997`, which is found and scrolled to even
   though it was never on screen.

The find bar and the bottom navigation are wrapped in `ExcludeFromFind`,
because they are chrome rather than content: without that, searching `row`
would also match the destination you are about to press.

Apps usually hide the bar until Ctrl+F (Cmd+F on macOS). This example keeps
the bar visible and runs a search on the first frame so a browser visitor
does not have to know the shortcut. Ctrl+F is still intercepted on web, so
the browser's own find does not open over an empty canvas.

The section labels (`ListTile`, `DataTable`, `Text.rich`, `FindableText`) are
also `ExcludeFromFind`: they name the widget class, they are not part of the
page being searched.

![The find bar open over a release-notes page, highlighting every match of the query and scrolling the active one into view](https://raw.githubusercontent.com/Yusufihsangorgel/find_in_page/main/doc/demo.gif)

That capture comes from `test/demo_capture_test.dart` in the package repository
rather than from this app, and the app behaves the same way.

```dart
// findableTextOf gives every row its searchable text up front. That is what
// makes all 2,000 rows findable rather than only the built ones. itemBuilder
// hands you the match offsets so you render the highlights (the cost of the
// lazy path; eager content can just use FindableText and skip this).
FindableListView(
  itemCount: rows.length,
  itemExtent: 88,
  findableTextOf: (index) => rows[index],
  itemBuilder: (context, index, matches, activeMatchIndex) => _HighlightedRow(
    text: rows[index],
    matches: matches,
    activeMatchIndex: activeMatchIndex,
  ),
);
```

Run it:

```
cd example
flutter run
```

On web, from the same directory: `flutter run -d chrome`.

See the package README for the controller API when you want to drive search from
your own UI instead of the built-in `FindBar`.
