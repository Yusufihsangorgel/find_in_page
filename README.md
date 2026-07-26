![find_in_page banner](https://raw.githubusercontent.com/Yusufihsangorgel/find_in_page/main/doc/banner.png)

# find_in_page

An in-app find bar for Flutter. Wrap your page in one widget and Ctrl+F
searches the text that is already there.

```dart
import 'package:find_in_page/find_in_page.dart';

FindInPageScope(child: MyPage())
```

That is the whole integration. Text inside `Text`, `Text.rich`,
`SelectableText`, and widgets you did not write such as `AppBar`, `ListTile`
and `DataTable` is all searchable without being wrapped or changed.

Press Ctrl+F (Cmd+F on macOS) to open the bar; type to highlight every match;
Enter or the arrow buttons move between them and scroll each into view; Escape
closes and clears.

## Read this before you install

**This does not fix the browser's own Ctrl+F, and nothing written in Dart can.**
On Flutter web with the default CanvasKit renderer your text is painted into a
canvas, so the browser's find bar, the browser's reader mode, and a crawler
looking for a phrase all still see nothing. Flutter has tracked that since 2020
in [flutter#65504] and it is not solved here.

What this package gives you is an in-app find bar that behaves like the
browser's one, on every platform Flutter runs on. If what you need is for
`Ctrl+F` in Chrome to find your contact address, this is the wrong tool and you
want the HTML renderer or a prerendered page instead.

[flutter#65504]: https://github.com/flutter/flutter/issues/65504

## What is searchable

| | |
|---|---|
| `Text`, `Text.rich`, `SelectableText` | Yes, automatically |
| Text inside widgets you do not own | Yes, automatically |
| Rows of a `ListView.builder` that were never built | Yes, via `FindableListView` |
| `TextField` and other editable fields | No, deliberately. A browser does not match inside `<input>` either |
| Icons | No. Flutter draws them as font glyphs; they are filtered out |
| A collapsed `ExpansionTile`, an unselected tab | No. It is not rendered, so there is nothing to find |

Two escape hatches:

* `ExcludeFromFind(child: ...)` keeps a subtree out, which is what you want for
  a navigation rail or a footer.
* `FindInPageScope(autoDiscover: false, ...)` turns discovery off entirely and
  searches only what registered itself, which is how versions before 2.0.0
  behaved.

## Demo

![demo](https://raw.githubusercontent.com/Yusufihsangorgel/find_in_page/main/doc/demo.gif)

## Parts

| Class | Role |
|---|---|
| `FindInPageScope` | Provides the controller, handles Ctrl+F / Escape, overlays the bar |
| `FindableText` | `Text` replacement that registers its content and renders highlights |
| `FindBar` | The search bar widget, usable standalone for custom placement |
| `FindInPageController` | Query, matches, and navigation; drive it directly for custom UIs |
| `FindableSource` | Interface to make any custom widget searchable |
| `FindableListView` | `ListView.builder` adapter that makes the whole backing list searchable, including items that are not built |
| `FindableRecord` | `FindableSource` with text supplied directly instead of read from a live widget |

## Screen readers

The match counter is the whole feedback loop of a find bar: you type, and the
`1/3` beside the field tells you whether that query found anything and where
you are in it. Focus stays in the query field, so a screen reader never lands
on that counter and the loop is silent.

`FindBar` announces it as a live region instead, saying "Match 1 of 3" or "No
matches" whenever the count or the active match changes, while the terse `1/3`
is kept out of the announcement because it reads badly aloud. The button
tooltips already carried labels.

Both default to English, like the tooltips; pass a localized builder:

```dart
FindBar(
  controller: controller,
  matchStatusLabel: (active, count) =>
      count == 0 ? l10n.noMatches : l10n.matchOf(active + 1, count),
)
```

## Custom UI

The scope's built-in bar is optional. Drive everything yourself:

```dart
final controller = FindInPageController();

FindInPageScope(
  controller: controller,
  showBar: false,
  child: ...,
);

// Anywhere:
controller.search('flutter');   // highlights all matches
controller.next();              // moves and scrolls to the next one
print('${controller.activeMatchIndex! + 1}/${controller.matchCount}');
```

Highlight colors are per-widget: `FindableText(highlightColor: ...,
activeHighlightColor: ...)`.

## Custom searchable widgets

Implement `FindableSource` in a `State` and register it:

```dart
class _MyWidgetState extends State<MyWidget> implements FindableSource {
  @override
  String get findableText => widget.caption;

  @override
  BuildContext? get findableContext => mounted ? context : null;

  // register in didChangeDependencies, unregister in dispose;
  // read controller.matchesFor(this) to render your own highlights.
}
```

## Searching a lazy list

`FindableText` only registers while it is built. In a `ListView.builder`
that means only the handful of items in the build/cache area are
searchable; scrolling builds and disposes items, which registers and
unregisters them and makes `matchCount` drift mid-session, and anything
scrolled past without being built is simply missed.

`FindableListView` fixes this by reading each item's text straight from
the backing list up front, so the whole list is searched regardless of
what is built:

```dart
FindInPageScope(
  child: FindableListView(
    itemCount: items.length,
    itemExtent: 56,
    findableTextOf: (index) => items[index],
    itemBuilder: (context, index, matches, activeMatchIndex) => ListTile(
      title: Text(items[index]),
    ),
  ),
)
```

`matches` are that item's matches of the current query (empty when there
are none); `activeMatchIndex` is which one of them is active, or null.
Rendering the highlight from those offsets is the builder's job, the same
way a plain `ListView.builder`'s `itemBuilder` owns the whole item.

Because an off-screen match has no live widget, revealing it cannot call
`Scrollable.ensureVisible`; `FindableListView` instead animates a
`ScrollController` to `index * itemExtent`, which is why `itemExtent` is
required. That means every item must be the same height (or width, for a
horizontal list) - the same constraint `ListView.builder(itemExtent: ...)`
already has. Variable height items are not supported.

`FindableRecord` is the plain `FindableSource` behind this: text supplied
directly, with no `findableContext`. Register one yourself with
`FindInPageController.register(record, reveal: ...)` for other data-driven
cases; `reveal` runs instead of `Scrollable.ensureVisible` when one of its
matches becomes active.

## Limits

- Matching is plain text and case insensitive by default
  (`search(query, caseSensitive: true)` for exact case). Regex is planned.
- `FindableListView` requires a fixed `itemExtent` and does not render
  highlights itself (see above); it is a data-driven complement to
  `FindableText`, not a drop-in replacement.
- Match order follows widget build order, which for a normal page is
  top-to-bottom visual order.
- `FindInPageScope` needs an `Overlay` ancestor for its built-in bar;
  every `MaterialApp`/`CupertinoApp`/`WidgetsApp` provides one.
- Navigation scrolls the widget containing the active match into view. In
  a paragraph taller than the viewport the exact line may still be
  offscreen; per-line precision is planned.
- Matches clipped away by `maxLines`/`overflow` are counted and navigated
  to, but cannot become visible.

## License

MIT
