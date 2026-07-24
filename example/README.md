# find_in_page example

The example app in `lib/main.dart` shows both halves of the package under one
`FindInPageScope`: eager content, where a plain `FindableText` already searches
everything on screen, and a lazy 2,000-row list, where `FindableListView` makes
every row searchable even though only the visible handful is built.

![The example app: searching text and jumping to matches across a long list](https://raw.githubusercontent.com/Yusufihsangorgel/find_in_page/main/doc/demo.gif)

The lazy-list case is the one to try. A plain `ListView.builder` of
`FindableText` would only ever search the rows currently built, and the match
count would drift as items scroll in and out. `FindableListView` registers every
row's text up front, so all 2,000 are searchable and the count stays put:
searching `row 1997` finds and scrolls to it even though it was never on screen.

```dart
// findableTextOf gives every row its searchable text up front — that is what
// makes all 2,000 rows findable, not just the built ones. itemBuilder hands you
// the match offsets so you render the highlights (the cost of the lazy path;
// eager content can just use FindableText and skip this).
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

See the package README for the controller API when you want to drive search from
your own UI instead of the built-in `FindBar`.
