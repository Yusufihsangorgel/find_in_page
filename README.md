# find_in_page

A user is hunting through your release notes for the line about `TextScaler`,
and there is no Ctrl+F to press. Mobile has no find bar at all, and on Flutter
web the browser's own bar searches a canvas that contains no text. This package
puts one inside the app.

```dart
import 'package:find_in_page/find_in_page.dart';

FindInPageScope(child: MyPage())
```

![A release-notes page with the find bar open: typing narrows the highlights while the arrow buttons jump between matches and scroll each one into view](https://raw.githubusercontent.com/Yusufihsangorgel/find_in_page/main/doc/demo.gif)

## Why this instead of what you already have

**Instead of walking the widget tree yourself.** `RichText`
(`widgets/basic.dart:6596`) exposes no search entry point, and highlighting a
hit means constructing a `TextSelection` by hand and passing it to
`RenderParagraph.getBoxesForSelection` (`rendering/paragraph.dart:1065`).
Inside a `ListView.builder` there is a harder ceiling:
`SliverMultiBoxAdaptorElement` holds only the children currently built, which
is exactly the range `didFinishLayout` reports through
`_childElements.firstKey()` and `lastKey()` (`widgets/sliver.dart:1221`). No
tree walk can see rows Flutter never built.

**Instead of the highlighting packages.** `substring_highlight`
(`lib/substring_highlight.dart:8`) and `highlight_text`
(`lib/src/highlight_text.dart:32`) are both a `StatelessWidget` that colors
matched substrings. Neither has a match count, a current match, or a
`ScrollController`, so neither can report "3 of 17" or bring the next hit into
view. This is a quiet category rather than a contested one: they draw about
57k and 14k downloads a month, and no Ctrl+F-style incumbent exists.

**Reach for it when**

- A long document, release-notes page or settings screen needs an in-app
  Ctrl+F.
- Matches live in a lazily built `ListView` and off-screen rows still have to
  be counted and reachable.
- The bar has to search text you never wrapped, including widgets from other
  packages.

Skip it if your page is short and fully built, and what users actually want is
a search field that filters a list: filtering is simpler to build and usually
clearer to use than a find bar.

That is the whole integration. Ctrl+F (Cmd+F on macOS) opens the bar, typing
highlights every match, Enter and the arrow buttons move between them and
scroll each into view, and Escape closes and clears.

## Text you never wrapped

The scope searches the text Flutter actually rendered inside it, which is why
widgets you did not write are covered too. Nothing in this tree implements an
interface or takes a query parameter:

```dart
FindInPageScope(
  child: Column(children: [
    AppBar(title: Text('Release notes')),
    ListTile(title: Text('Release 4.0 rollout')),
    DataTable(columns: channelColumns, rows: channelRows),
    Text.rich(TextSpan(children: migrationNotice)),
  ]),
)
```

![Four cards labelled AppBar, ListTile, DataTable and Text.rich, each a stock Flutter widget with the query highlighted inside it, under a find bar reading 1/5](https://raw.githubusercontent.com/Yusufihsangorgel/find_in_page/main/doc/searchable-grid.png)

That figure comes out of a test run rather than a drawing tool.
`tool/searchable_grid.dart` builds those four widgets, types into the real find
bar, and every highlight you can see was painted by the package during the
capture. `tool/searchable_grid.sh` regenerates it.

The nearest packages on pub.dev answer a smaller question.
[`substring_highlight`] and [`highlight_text`] take a string you already have
and restyle the parts that match. You rewrite the widget, you supply the text,
and neither one counts matches across a page or moves the viewport.

[`substring_highlight`]: https://pub.dev/packages/substring_highlight
[`highlight_text`]: https://pub.dev/packages/highlight_text

## Web

On Flutter web this package takes over the **keyboard shortcut** — Ctrl+F
or Cmd+F — on browsers that allow a page to cancel that key. Chrome and
Firefox usually do. Safari did in a 2020 key-by-key survey; that result is
old and was not re-checked here. Firefox users (and some enterprises) can
deny the page permission to override shortcuts, and then the keys never
reach us.

That is all the intercept is. It does not put text into the DOM, so it
does not help a crawler, reader mode, or the browser's own find engine.
Find chosen from a browser menu, from the iOS share sheet, or from
Android "Find in page" is not a key event and is not intercepted. F3 and
Ctrl+G are also find in various browsers and are left alone.

This is not a fix for [flutter#65504]. Flutter web has two renderers
left, `canvaskit` and `skwasm`, and both paint text into a canvas. Under
either one the browser's find bar, its reader mode and a crawler looking
for a phrase all see an empty page.

If a browser refuses to let the page have the key, the user gets the
browser's find bar over a canvas that has nothing findable in it. The
in-app bar still opens when the key reaches Dart, so both can appear
together. When the key never reaches the page, only the native bar
opens. There is no API that can force the intercept to win.

Older advice was to build with `--web-renderer html`. That renderer and that
flag are both gone, and `flutter build web --help` no longer offers a renderer
choice. When you need Chrome's own Ctrl+F to find your contact address,
prerender that content as real HTML and serve it outside the canvas. An in-app
find bar cannot stand in for it.

What you get here is a find bar that behaves like the browser's, on every
platform Flutter runs on. On web, the keys open that bar when the browser
lets them.

[flutter#65504]: https://github.com/flutter/flutter/issues/65504

## What is searchable

| | |
|---|---|
| `Text`, `Text.rich`, `SelectableText` | Yes, automatically |
| Text inside widgets you do not own | Yes, automatically |
| Rows of a `ListView.builder` that were never built | Yes, via `FindableListView` |
| `TextField` and other editable fields | No, deliberately. A browser does not match inside `<input>` either |
| Icons | No. Flutter draws them as font glyphs, and those are filtered out |
| A collapsed `ExpansionTile`, an unselected tab | No. It is not rendered, so there is nothing to find |

Two escape hatches. `ExcludeFromFind(child: ...)` keeps a subtree out, which is
what a navigation rail or a footer wants, and
`FindInPageScope(autoDiscover: false, ...)` turns discovery off altogether and
searches only what registered itself, the way versions before 2.0.0 behaved.

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

`FindableText` only registers while it is built. In a `ListView.builder` that
means only the handful of items in the build and cache area are searchable;
scrolling builds and disposes items, which registers and unregisters them and
makes `matchCount` drift mid-session, and anything scrolled past without being
built is simply missed.

![Line chart of matches reported against scroll position in a 500-row list holding 43 matches. FindableListView is a flat line at 43 across all 50 positions. ListView.builder with FindableText never rises above 17, falls to 0 at 35 of the 50 positions, and the area between the two lines is shaded](https://raw.githubusercontent.com/Yusufihsangorgel/find_in_page/main/doc/lazy-list.png)

Both lines come from the same 500 rows and the same query, read at 50 scroll
positions. `tool/lazy_list_figure.sh` builds the two trees at an identical
item extent, jumps each to every position and records `matchCount`. The
shaded band is the gap between the two: matches the list holds that the
count leaves out. The generator compares the arms before it writes anything,
and a run where they agree produces no figure.

`FindableListView` closes that gap by reading each item's text straight from
the backing list up front, so the whole list is searched regardless of what
is built:

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

`matches` are that item's matches of the current query (empty when there are
none); `activeMatchIndex` is which one of them is active, or null. Rendering
the highlight from those offsets is the builder's job, the same way a plain
`ListView.builder`'s `itemBuilder` owns the whole item.

Because an off-screen match has no live widget, revealing it cannot call
`Scrollable.ensureVisible`. `FindableListView` animates a `ScrollController` to
`index * itemExtent` instead, which is why `itemExtent` is required. Every item
must therefore be the same height (or width, for a horizontal list), the same
constraint `ListView.builder(itemExtent: ...)` already carries. Variable height
items are unsupported. For other data-driven cases, register a `FindableRecord`
yourself with `FindInPageController.register(record, reveal: ...)`, where
`reveal` runs in place of `Scrollable.ensureVisible` when one of its matches
becomes active.

## Limits

- Matching is plain text and case insensitive by default; pass
  `search(query, caseSensitive: true)` for exact case. Regex is planned.
- Match order follows widget build order, which on a normal page is
  top-to-bottom visual order.
- Navigation scrolls the widget containing the active match into view. In a
  paragraph taller than the viewport the exact line can still be offscreen;
  per-line precision is planned.
- Matches clipped away by `maxLines` or `overflow` are counted and navigated
  to, but they cannot become visible.
- `FindableListView` needs a fixed `itemExtent` and renders no highlights of
  its own.
- The built-in bar needs an `Overlay` ancestor. Every `MaterialApp`,
  `CupertinoApp` and `WidgetsApp` provides one.
- On Flutter web, Ctrl+F / Cmd+F is intercepted when the browser allows
  it. That does not put text in the DOM. Find from a menu, F3, and
  Ctrl+G are not intercepted. If the browser refuses, its empty find bar
  still appears.

## License

MIT
