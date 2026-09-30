# Migrating from substring_highlight

This guide moves a screen from `substring_highlight` to `find_in_page`. It was
checked against `substring_highlight` 1.0.33 and the `find_in_page` source in
this repository.

Read "Differences" before you start. The two packages answer different
questions. `substring_highlight` paints one string with a term you hand it.
`find_in_page` holds one query for a whole page, counts the matches, and moves
between them. If painting one string is all you need, staying on
`substring_highlight` is a fair choice.

## The mental shift

With `substring_highlight` the term is a parameter of each widget. With
`find_in_page` the term is set once, on a `FindInPageController`, and every
`FindableText` under the same controller highlights it.

| Step | substring_highlight | find_in_page |
|---|---|---|
| Where the term lives | `term` on every `SubstringHighlight` | `controller.search(query)` once |
| What you wrap the page in | nothing | `FindInPageScope`, or pass a controller to each `FindableText` |
| How a row is drawn | `SubstringHighlight(text: ..., term: ...)` | `FindableText(text)` |
| Clearing the highlight | pass an empty term | `controller.clearSearch()` |

## Parameter mapping

| `SubstringHighlight` | `find_in_page` | Notes |
|---|---|---|
| `SubstringHighlight(...)` | `FindableText(...)` inside a `FindInPageScope` | Plain `Text` inside the scope is also found and highlighted with no rewrite |
| `text` (required) | `data`, the first positional argument of `FindableText` | |
| `term` | `FindInPageController.search(query)` | One query per controller. There is no per-widget term |
| `terms` | none | One query string only. See "Differences" |
| `caseSensitive` (default false) | `search(query, caseSensitive: true)` | Set on the controller, and it sticks until a later call passes it again. Default is false, as in `substring_highlight` |
| `words`, `wordDelimiters` | none | No whole-word mode |
| `textStyle` (default `TextStyle(color: Colors.black)`) | `FindableText.style` | Default is null, which inherits the ambient `DefaultTextStyle`. Set `style` if you relied on the black default |
| `textStyleHighlight` (default `TextStyle(color: Colors.red)`) | `FindableText.highlightColor` and `activeHighlightColor` | Background colors only. Defaults are `Color(0xFFFFF59D)` and `Color(0xFFFFB74D)`. A highlight that changes text color or adds an underline has no equivalent |
| `maxLines` | `FindableText.maxLines` | Same name |
| `overflow` (default `TextOverflow.clip`) | `FindableText.overflow` | Default is null, which follows `Text`. Set `TextOverflow.clip` to keep the old behavior. Matches cut off by `maxLines` or `overflow` are still counted but cannot become visible |
| `textAlign` (default `TextAlign.left`) | `FindableText.textAlign` | Default is null, which follows `Text`. Pass `TextAlign.left` to keep the old behavior |

For text that you do not wrap, the scope takes `FindInPageScope.highlightColor`
and `activeHighlightColor` instead.

## Before and after

Before, a list of suggestions where each row highlights the term the user typed:

```dart
import 'package:substring_highlight/substring_highlight.dart';

ListTile(
  title: SubstringHighlight(
    text: title,
    term: query,
    textStyle: const TextStyle(color: Colors.grey),
    textStyleHighlight: const TextStyle(
      color: Colors.black,
      decoration: TextDecoration.underline,
    ),
  ),
)
```

After, the same list with a match counter and previous and next buttons. The
file is `example/lib/migrating_from_substring_highlight.dart` and it passes
`flutter analyze`:

```dart
import 'package:find_in_page/find_in_page.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(home: TrackSearchPage()));

const _tracks = [
  'Blue in Green',
  'Green Onions',
  'Greensleeves',
  'Kind of Blue',
  'Mood Indigo',
  'Take Five',
  'Watermelon Man',
  'So What',
];

class TrackSearchPage extends StatefulWidget {
  const TrackSearchPage({super.key});

  @override
  State<TrackSearchPage> createState() => _TrackSearchPageState();
}

class _TrackSearchPageState extends State<TrackSearchPage> {
  // The page owns this controller and disposes it.
  final _find = FindInPageController();

  @override
  void dispose() {
    _find.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FindInPageScope(
      controller: _find,
      // Your own TextField is the search box. The built-in bar stays off.
      showBar: false,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // Chrome stays out of the search. Without this, the counter
              // below could match the query it reports on.
              ExcludeFromFind(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: 'Search tracks',
                          ),
                          // The term now lives on the controller, not on
                          // each row.
                          onChanged: _find.search,
                        ),
                      ),
                      ListenableBuilder(
                        listenable: _find,
                        builder: (context, _) {
                          final active = _find.activeMatchIndex;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              active == null
                                  ? '0'
                                  : '${active + 1}/${_find.matchCount}',
                            ),
                          );
                        },
                      ),
                      IconButton(
                        tooltip: 'Previous match',
                        icon: const Icon(Icons.keyboard_arrow_up),
                        onPressed: _find.previous,
                      ),
                      IconButton(
                        tooltip: 'Next match',
                        icon: const Icon(Icons.keyboard_arrow_down),
                        onPressed: _find.next,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final title in _tracks)
                      ListTile(
                        title: FindableText(
                          title,
                          style: const TextStyle(color: Colors.grey),
                          highlightColor: const Color(0xFFFFF59D),
                          activeHighlightColor: const Color(0xFFFFB74D),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

Three things changed besides the widget name:

- The highlight is a background color. The black underlined match from the
  "before" code has no counterpart here.
- `FindableText` highlights and never filters. If your list was already
  filtered by the term, keep filtering it yourself and pass the filtered
  titles. Rows that leave the list stop counting toward `matchCount`.
- If you also leave some `Text` unwrapped and start with a query set in code,
  call `controller.search` from a post-frame callback. The scope reads that
  text after layout. Typing into a `TextField`, as above, is already after
  layout.

`FindableText` needs a scope above it or a `controller` argument. With neither,
it draws plain text and never highlights.

If you need a different term in different parts of a screen, create one
`FindInPageController` per term and pass each one to its widgets through the
`controller` argument of `FindableText`.

## Differences

What `substring_highlight` does that `find_in_page` does not:

- Highlights several terms at once (`terms`). `find_in_page` searches one query
  string.
- Matches whole words only (`words` and `wordDelimiters`). Its source marks that
  option as alpha. `find_in_page` has no word mode.
- Styles a match with any `TextStyle`, such as a color, a weight or an
  underline. `find_in_page` paints a background color.
- Takes the term as a plain argument with no shared state. It is a
  `StatelessWidget` and needs no scope and no controller.

What `find_in_page` does that `substring_highlight` does not:

- Counts matches across the page, tracks an active match, and moves between
  matches with `next` and `previous`, scrolling each into view.
- Finds and highlights `Text`, `SelectableText` and other read-only text you did
  not wrap, including an `AppBar` title and `DataTable` cells.
- Searches the rows of a lazy `ListView.builder` that were never built, through
  `FindableListView`.
- Matches accented letters from an unaccented query by default. A query of
  `resume` finds `résumé`. Pass `diacriticSensitive: true` for exact accents.
  `substring_highlight` lowercases the text and looks for the term as written.
- Ships a find bar with the Ctrl+F and Cmd+F shortcut, and announces the match
  count to screen readers.
- Gives the active match its own color.

What they share: both match a plain substring, and both ignore case by default.
`find_in_page` has no regular expression support yet.
