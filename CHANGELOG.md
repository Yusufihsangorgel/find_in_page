## 3.0.0

The find bar no longer depends on Material. Flutter 3.50 deprecates
`package:flutter/material.dart`, and its successor `material_ui` defines its
own `Theme` and `MaterialLocalizations`. A bar built from Material widgets
breaks in one kind of app or the other. This version rebuilds the bar on the
widgets layer. No file in `lib/` imports Material, Cupertino or
`material_ui`, and a test fails if one does. The migration was first raised
in #5.

### Breaking changes

- The minimum is now Flutter 3.41.0 with Dart 3.11.0. Flutter 3.41.0 is the
  first stable release with `RawTooltip`, the widgets-layer tooltip the bar
  uses.
- The built-in bar no longer reads the Material `Theme`. Its colors, text
  styles and geometry come from the new `style` argument of `FindBar`, then
  the nearest `FindBarTheme`, then neutral defaults that follow the platform
  brightness. An app that wants the bar in its own colors passes a style. The
  recipes below build one from a Material theme.
- The query field is an `EditableText`, and the buttons paint their own
  icons. Test finders for a `TextField` or an `Icon` inside the bar no longer
  match. The migration notes below have replacements.
- The `controller` of a `FindBar` is typed as the new `FindSession`
  interface. Passing a `FindInPageController` works unchanged. Code that
  reads it back and calls a member only the controller has needs a cast.
- The bar has two new toggles, match case and match accents, between the
  query field and the match counter. They make the bar wider and come second
  and third in the tab order. They step aside when the bar is too narrow for
  them, and `showMatchCase: false` or `showMatchAccents: false` removes them.
- The `itemExtent` of a `FindableListView` is now nullable, since
  `itemExtentBuilder` can take its place.
- The controller's `setOpenCloseHandlers` and `registeredSources` are marked
  `@internal`. They connect this package's own widgets. Using them from
  another package now draws an analyzer warning.
- When the same query runs again because a source registered, unregistered or
  changed its text, the active match is kept if the same source still has a
  match at the same start offset. Otherwise the active index stays as it was,
  or moves to the last match when it is past the end. It used to keep the
  same index in every case, which pointed at a different match once matches
  before it appeared or went away.

### Added

- A `FindSession` interface, implemented by `FindInPageController`. It holds
  what a find bar reads and calls, and nothing else. New members may be added
  to it in a minor release. A class outside this package that implements it
  may have to add them when it upgrades.
- A `barBuilder` argument on `FindInPageScope`. The scope shows what it
  returns where the built-in bar would go, removes it on close, and closes it
  on Escape. The builder gets the session, which is all a bar from another
  design system needs.
- A `selectMatch` method on the controller. It makes the match at an index
  active in one step and scrolls to it. When the same query runs again, that
  match stays active as long as its source still has a match at the same
  start offset.
- Two styling classes. A `FindBarStyle` holds colors, text styles, corner
  radius, border, shadows, padding and sizes. A `FindBarTheme` hands one to
  every bar below it, including the one a scope shows.
- An `itemExtentBuilder` argument on `FindableListView`, next to
  `itemExtent`. Exactly one of the two is required. A match is revealed at the
  sum of the extents of the rows before it. The list estimates its full
  extent from the rows it has built, and when rows further down are taller
  the reveal tries a few times to reach the match. It stops as soon as a
  finger, a wheel, a drag or the app itself moves the list, a jump to the end
  included.
- Shift+Enter in the query field moves to the previous match.
- Text an input method is still composing is searched as it changes, and a
  commit that leaves the text unchanged does not search again. While a
  composition is active, Enter and Shift+Enter go to the input method and do
  not move between matches.
- A `contextMenuBuilder` argument on `FindBar`. By default iOS shows its
  system menu where the platform supports it. Other platforms get a plain
  menu of the field's actions drawn in the bar's style.
- On Android and Fuchsia each button of the bar takes taps across a 48 pixel
  square around its painted size, and on iOS across a 44 pixel square, the
  touch targets those platforms ask for. The query field takes taps across
  the same height. The platform alone decides this, the same as Flutter's
  Material tap target default. A phone browser gets the touch size of its
  platform, and desktop platforms keep the compact size.
- On a touch platform the bar is one row, one hit height tall, in the common
  case. Where the toggles do not fit beside the field, a search options
  button takes their place and shows them in a second row on demand. Escape
  on a toggle hides that row again, and the caret's selection handles stay
  hidden while it shows. The button is announced as expanded or collapsed,
  and its label comes from the new `optionsTooltip` argument of `FindBar`.
  With Roboto the toggles fit beside the field from about 411 pixels wide on
  Android and 393 on iOS. The narrowest field is 80 pixels there and 96 on
  desktop platforms. The row is laid out around a counter of three digits a
  side, typed or not, which keeps it from changing when the counter appears.
  A longer counter is scaled down to the room left, and the bar stays one
  row while that room is at least three quarters of what a three digit
  counter needs.
- A bar too narrow for the field, the counter and the previous, next and
  close buttons in one row grows a second row, one hit height tall, and
  moves those three buttons there. A large text scale can need that too. The
  narrowest bar that fits is three button hit sizes plus its padding, 160
  pixels with the default style on Android and Fuchsia, 148 on iOS and 112
  on desktop platforms.
- A switched on toggle is filled with the accent color, which sets it apart
  from a switched off one by at least 3 to 1 in both default themes. The
  focus ring keeps a gap from that fill.

### Fixed

- The built-in bar works under `CupertinoApp` and under a plain
  `WidgetsApp`. In 2.x it asserted there for lack of
  `MaterialLocalizations`, while the README said it worked.
- The query field turns off autocorrect and smart punctuation. Both could
  change what was typed, and a curly apostrophe never matches the straight
  one on the page.
- Pressing the find shortcut while the scope's bar is open moves focus back
  to its field and selects the query, as browsers do. This holds for a
  `FindBar` returned from `barBuilder` too, and with several of them it is
  the last one still showing that gets focus. It used to leave focus where it
  was.
- Revealing a match in a `FindableListView` takes the list's leading padding
  into account, in every scroll direction. The row used to land that much
  further along the list than the reveal aimed.
- `FindableText` scrolls the matched line into view, as discovered text
  already did. In a paragraph taller than the viewport the active match could
  stay offscreen. `test/tall_paragraph_reveal_test.dart` steps through four
  matches in one tall paragraph.
- A revealed match stays clear of the scope's find bar, in `FindableText` and
  in discovered text. Scrolling stops 16 pixels below the bar, or 16 pixels
  from an edge the bar does not cover, and a match already inside those
  bounds does not move. The bar is measured as it is laid out. That covers
  its second row at a large text scale, a bar placed at the bottom with
  `barAlignment`, and a bar from `barBuilder`. With `showBar: false` the
  scope cannot see the find UI and keeps 72 pixels at both edges. In a short
  scroll view the two gaps take at most half its height. Before, discovered
  text stopped at the very edge, under the bar on a page with no app bar, and
  a `FindableText` was aligned about 30% down the viewport even when the
  match was already visible. A `FindableText` in a `PageView` or under
  `NeverScrollableScrollPhysics` is still scrolled there, now to put the match
  in the middle of that view. A `FindableText` near the start of a scroll view
  nested in another can now end up under the bar, as discovered text could
  before. `test/reveal_margin_test.dart` covers text scales from 1 to 3, an
  app bar, a bar at the bottom and one from `barBuilder`, short, sideways and
  nested scroll views, and a `SelectionArea`.
  `test/fixed_scroll_view_reveal_test.dart` covers a `PageView` with and
  without `allowImplicitScrolling`, and the view the user cannot scroll.

### Migration notes

Finding the bar's parts in a widget test.

```dart
// 2.x
await tester.enterText(find.byType(TextField), 'query');
await tester.tap(find.byIcon(Icons.keyboard_arrow_down));

// 3.0.0
final field = find.descendant(
  of: find.byType(FindBar),
  matching: find.byType(EditableText),
);
await tester.enterText(field, 'query');
await tester.tap(find.byTooltip('Next match'));
```

Tooltip finders such as `find.byTooltip('Next match')` keep working, and
`find.bySemanticsLabel` finds the same buttons by name.

Material colors for the bar, in an app on `package:flutter/material.dart`.

```dart
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:find_in_page/find_in_page.dart';

FindBarStyle findBarStyleOf(ThemeData theme) => FindBarStyle(
      backgroundColor: theme.colorScheme.surfaceContainerHigh,
      foregroundColor: theme.colorScheme.onSurface,
      hintColor: theme.colorScheme.onSurfaceVariant,
      accentColor: theme.colorScheme.primary,
      textStyle: theme.textTheme.bodyLarge,
      counterStyle: theme.textTheme.bodySmall,
    );

MaterialApp(
  builder: (context, child) => FindBarTheme(
    style: findBarStyleOf(Theme.of(context)),
    child: child!,
  ),
  home: FindInPageScope(child: page),
)
```

The same in an app on `material_ui`. Only the import differs.

```dart
import 'package:material_ui/material_ui.dart';
import 'package:find_in_page/find_in_page.dart';

FindBarStyle findBarStyleOf(ThemeData theme) => FindBarStyle(
      backgroundColor: theme.colorScheme.surfaceContainerHigh,
      foregroundColor: theme.colorScheme.onSurface,
      hintColor: theme.colorScheme.onSurfaceVariant,
      accentColor: theme.colorScheme.primary,
      textStyle: theme.textTheme.bodyLarge,
      counterStyle: theme.textTheme.bodySmall,
    );

MaterialApp(
  builder: (context, child) => FindBarTheme(
    style: findBarStyleOf(Theme.of(context)),
    child: child!,
  ),
  home: FindInPageScope(child: page),
)
```

Without a style the bar follows the platform brightness, not the app's
`themeMode`. A dark app on a light system gets a light bar until it passes
one.

## 2.5.0

- Match navigation now follows the page from top to bottom when registered
  and automatically discovered text share a page. An app bar title comes
  before the body, including in a `Scaffold` with a `drawer` or `endDrawer`.
  Side-by-side or overlapping content keeps the order the widgets were built
  in. This includes a body that extends behind the app bar with
  `extendBodyBehindAppBar`. `FindableListView` rows stay together at the
  list's position, including rows that have not been built. Registered
  sources without an anchor on the page still come first. With discovery off,
  registration order is unchanged.
- `FindInPageController.register` accepts an optional `anchor` context that
  places a source on the page.
- Highlights for text you did not wrap are clipped to where the text is
  visible. A match scrolled under the app bar or out of a scroll view no
  longer paints an empty box over other content.
- On the web, a match after a letter that gets longer when lowercased, such
  as the Turkish dotted capital I (İ), came out one character late for every
  such letter before it, and a match near the end of the text could end past
  it. These offsets are now correct.
- The web demo shows a loading screen while it downloads, with a link to the
  package page if it fails to load.
- README: the custom UI example no longer throws when nothing matches, and the
  comparison no longer quotes download counts.
- README: a table says when `substring_highlight` is the better choice, and
  `doc/migrating-from-substring_highlight.md` maps its parameters to this
  package's.

## 2.4.0

- Opening the built-in bar now moves keyboard focus into its query field even
  when something else already had focus. `TextField(autofocus: true)` only
  takes focus when the enclosing `FocusScope` has none, so on a page with a
  focused field or list the bar opened unfocused and had to be clicked.
  `test/open_close_focus_test.dart` reproduces this with a focused
  `TextField`.
- Closing the bar (button, Escape, or `close()`) returns focus to the node
  that had it before opening, if that node is still attached. If the user
  moved focus elsewhere while find was open, focus stays where they put it.
  Both cases are tested through Escape and `close()`.
- Added `FindInPageController.isOpen`, `open()`, and `close()`. `isOpen`
  tracks whether find is open (the built-in bar showing, or a custom UI told
  to open) and is kept truthful whichever way find was opened or closed: the
  shortcut, the close button, Escape, and the two new methods all go through
  the same state. `open()` shows the built-in bar (and focuses it, as above)
  or calls `onOpenRequested` for a custom UI; `close()` clears the search,
  same as before, and hides the bar. Both are safe to call with no
  `FindInPageScope` mounted, and a scope that disposes while open resets
  `isOpen` on a controller it does not own. README shows using `close()`
  from a `NavigatorObserver` so an app-level scope does not stay open after
  navigating away, and watching `isOpen` elsewhere.
- `FindInPageScope`'s dartdoc no longer says the scope "never takes or moves
  focus"; that was only ever true of registering the shortcut, and is now
  stated precisely alongside what opening and closing the bar do.

## 2.3.2

- The example now builds for web and deploys to GitHub Pages, so the find bar
  can be tried without cloning anything. Library code is unchanged.

## 2.3.1

- A `SelectionArea` wrapping the page, and a `SelectableText`, already
  painted their own highlight while the find overlay painted its matches,
  and a drag-select already landed while the bar was open. The overlay
  paints after the child and does not hit-test, so the two fills live in
  different layers and neither swallows the other's gestures. That was
  untested and unstated. `test/selection_interaction_test.dart` pins it;
  the README now says so. No behaviour changed.

## 2.3.0

- On Flutter web, Ctrl+F / Cmd+F is intercepted as a best-effort
  `preventDefault` so the in-app bar can open instead of the browser's.
  That was already how the engine treats a handled key: this package has
  returned handled for the shortcut since 0.1.0, and Flutter's web
  keyboard binding already calls `preventDefault` when it does. What was
  missing was saying so, testing the handled bit, and a capture listener
  that still cancels the key if Flutter's semantics gate never delivers
  it, including when the user presses the modifier this platform would
  not have used (Ctrl on a Mac, Cmd elsewhere). It does not put text in
  the DOM, does not help a crawler or reader mode, does not intercept
  Find chosen from a browser menu or from mobile chrome, and does not
  close flutter#65504. If a browser refuses to let the page have the
  key, the user gets the browser's find bar over a canvas that has
  nothing findable in it; Firefox users who blocked "Override Keyboard
  Shortcuts" get only that native bar. F3 and Ctrl+G are left alone.
  Off web nothing changes: the listener is a stub, and only the
  platform's own modifier is handled. The scope's dartdoc now sits on
  the class; it had been attached to the default highlight colour.

## 2.2.3

- Tests for `showMatchOnScreen`, the last step of a find and the only public
  member left that no test named. The half worth having is the early return:
  a source whose render object went away between the sweep that found it and
  the scroll that would reveal it is routine in a lazy list, and throwing
  there would take down a search over one stale row. Removing that guard turns
  three red; skipping the scroll turns five. No behaviour changed.

## 2.2.2

- Tests for `setDiscovery` and `sourceTextChanged`, the two hooks a scope uses
  to drive the controller. Both carry a rule invisible from the call site:
  discovery must not report text a registered source already owns (removing
  that guard turns seven of them red), and a text change with no search running
  must not schedule work (three). No behaviour changed.

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
