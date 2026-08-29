# find_in_page

`FindInPageScope` searches the text Flutter rendered inside its `child`, including widgets you did not write (`AppBar`, `ListTile`, `DataTable`, `Text.rich`, `SelectableText`). Ctrl+F (Cmd+F on macOS and iOS) opens `FindBar`; typing highlights matches and `next` / `previous` asks the active match's source to reveal it.

Discovery only yields `ParagraphSource` (`RenderParagraph`) and `ReadOnlyEditableSource` (read-only, non-obscured `RenderEditable`). Text inside a platform view or WebView is not those types, so it is not found; neither are editable or obscured field values, paragraphs made only of icon glyphs, collapsed `ExpansionTile` children, unselected tabs, or lazy-list rows that were never built. `SelectableText` and any other non-obscured read-only `RenderEditable` are searched.

## Usage

Put `FindInPageScope` **inside** `MaterialApp` / `CupertinoApp` / `WidgetsApp` (the built-in bar needs an `Overlay` ancestor) and **around** the content it should search. The example wraps the whole `Scaffold`, not just `body`, so the `AppBar` title is included:

```dart
import 'package:find_in_page/find_in_page.dart';
import 'package:flutter/material.dart';

void main() => runApp(
      MaterialApp(
        home: FindInPageScope(
          child: Scaffold(
            appBar: AppBar(title: const Text('find_in_page example')),
            body: const Text(
              'This intro is a plain Text widget. So is the title in the app '
              'bar. Press Ctrl+F and search for "plain" or for "example" to '
              'see both highlighted without either one being wrapped.',
            ),
          ),
        ),
      ),
    );
```

`autoDiscover` defaults to true: unwrapped `Text` is enough. `FindableText` is optional and highlights by restyling spans instead of the overlay. Wrap chrome in `ExcludeFromFind` (the example does this for the mode toggle).

The same `example/` app is live at <https://yusufihsangorgel.github.io/find_in_page/>. It keeps a custom `FindBar` visible; the shortest built-in-bar integration is the snippet above.

## Contracts

**Placement.** The sweep starts at `FindInPageScope.child`. Widgets above the scope are not searched. `FindInPageScope.maybeOf` returns the nearest controller or null; `FindInPageScope.of` asserts if missing.

**Dispose.** Omit `controller` and the scope constructs and `dispose`s a `FindInPageController`. If you pass one, you own `dispose` (`ChangeNotifier`); the scope calls `setDiscovery` on it and `setDiscovery(null)` when it unmounts or the controller is swapped. Same split for `FindableListView`'s `scrollController`. `FindableText` `register`s in `didChangeDependencies` and `unregister`s in `dispose`; a custom `FindableSource` must do the same, call `sourceTextChanged` when `findableText` changes, paint from `matchesFor(this)`, and wrap its render in `ExcludeFromFind` (registration identity does not hide a `ParagraphSource` of the same text). `FindableListView` unregisters its `FindableRecord`s on dispose.

**Controller lifetime.** `search` / `next` / `previous` / `clearSearch` are the session. Matching is a case- and diacritic-insensitive substring by default (`resume` finds `résumé`). `caseSensitive` and `diacriticSensitive` are sticky: a later `search(query)` without those args keeps the last setting. `register` is safe during build; recompute is post-frame. `isActive` is `identical`, so a `FindMatch` from a previous search is never active. The example keys the scope (`ValueKey`) when swapping the page so matches do not carry over.

**First programmatic search.** Automatic discovery reads render objects after layout. If a page starts with a query, call `controller.search(query)` from a post-frame callback after the scope is mounted, as `example/lib/main.dart` does. Calling it before the first layout sees no unwrapped text, and installing discovery later does not itself rerun that query. Explicitly registered sources schedule their own post-frame recompute during build; automatically discovered text does not.

**Lazy lists.** `FindableText` is searchable only while mounted. `ListView.builder` plus `FindableText` misses unbuilt rows and `matchCount` drifts as children dispose. Use `FindableListView`: it registers every index through `findableTextOf` up front. Reveal derives the target from `index * itemExtent`, aligns it about 30% into the viewport, and clamps it to the scroll range, so `itemExtent` is required and variable-height items are unsupported. The list wraps itself in `ExcludeFromFind` and does not paint highlights; `itemBuilder` must, from that row's `matches` and `activeMatchIndex` (index into `matches`, or null; copy `_HighlightedRow` in `example/lib/main.dart`). Explicit controller param is `findController`. Off-screen data without a list: `register(record, reveal: ...)`.

**Reveal / selection.** Discovery can call `showMatchOnScreen` for the matched text box. A registered source without a custom `reveal` only gives the controller its widget context, so `Scrollable.ensureVisible` reveals that widget, not necessarily the matched line inside a widget taller than the viewport. Matches clipped by `maxLines` / `overflow` are still counted but cannot be made visible. The discovery overlay does not hit-test: a surrounding `SelectionArea` and `SelectableText` keep their selection highlight and drag gestures while find highlights are painted.

**Focus / keyboard.** While mounted, `FindInPageScope` handles the shortcut via `HardwareKeyboard` globally. The handler does not move focus; when the built-in bar opens, `FindBar` defaults `autofocus` to true. Escape is consumed only while the built-in bar is visible, and then runs `clearSearch`. `showBar: false` with no `onOpenRequested` ignores the shortcut; with it, the callback runs and Escape does not clear. `FindBar` Enter calls `next`. The bar lives in the `Overlay`, outside `child`, so the query field is not searched.

On Flutter web, returning handled is what the engine maps to `keydown.preventDefault()`, so the in-app bar can take Ctrl/Cmd+F on browsers that allow it (Chrome and Firefox usually do; Safari last measured 2020). A capture listener on `window` does the same if the key never reaches Dart. That is a keyboard intercept, not a 65504 fix: it does not put text in the DOM, does not help a crawler, and does not affect Find chosen from a browser menu. If the browser refuses the key, the user gets the browser's find bar over a canvas that has nothing findable in it. `showBar: false` with no `onOpenRequested` must not intercept. F3 / Ctrl+G are not intercepted. Off web the listener is a no-op and only the platform modifier is handled.

## Mistakes

- **Scope not an ancestor of the text.** Symptom: `matchCount == 0`, nothing highlights, no error. Fix: wrap the page (`Scaffold` in the example).
- **Scope above `MaterialApp`.** Symptom: Ctrl+F looks like a no-op (no `Overlay` for `FindBar`). Fix: scope as a descendant of the app widget.
- **`ListView.builder` of `Text` or `FindableText`.** Symptom: far rows never found; count changes while scrolling. Fix: `FindableListView`.
- **`FindableListView` `itemBuilder` ignores `matches`.** Symptom: count and scroll work, nothing is highlighted. Fix: paint from `FindMatch.start` / `FindMatch.end`. Do not nest `FindableText` in the row — that double-counts built items and the count drifts again.
- **`autoDiscover: false` with unwrapped `Text`, or `FindableText` / `FindableListView` outside a scope with no `controller` / `findController`.** Symptom: 0/0 or a list that never highlights (`maybeOf` is null). Fix: leave the default, or pass the controller you constructed.
- **Calling the initial `search` before layout.** Symptom: unwrapped text stays at 0 matches with no error. Fix: schedule the first programmatic search post-frame; keyboard and bar searches already happen after layout.
- **Expecting an editable `TextField` value to match.** Symptom: form contents never highlight. Deliberate; non-obscured read-only editables such as `SelectableText` are searched.
- **Expecting every counted match to become visible.** Symptom: navigation reaches a match hidden by `maxLines` / `overflow`, or a line inside a very tall registered widget remains offscreen. The controller cannot reveal clipped content and only has widget-level context for a custom registered source unless you pass `reveal`.
- **Chrome left searchable, or a custom `FindableSource` that still renders text.** Symptom: extra matches, or `matchCount` doubled. Fix: `ExcludeFromFind`.
- **Disposing the wrong controller.** Symptom: leaks or use-after-dispose. Call `dispose` only on a `FindInPageController` you constructed.
- **`search(q, caseSensitive: true)` then `search(other)`.** Symptom: later searches stay sensitive. Pass the flag again to change it. Same for `diacriticSensitive`. Query is a plain substring, not a regex.
- **Expecting the web intercept to make canvas text visible to the browser.** Symptom: Edit → Find, reader mode, or a crawler still sees nothing, or Safari / a blocked Firefox still opens an empty native bar. Deliberate; the intercept is the keyboard shortcut only, and it is best-effort.

## Layout

- `lib/find_in_page.dart` — public exports
- `lib/src/` — implementation
- `example/lib/main.dart` — eager page and 2,000-row `FindableListView`
- `test/` — regular suite: `flutter test --exclude-tags demo`. A bare `flutter test` also runs `test/demo_capture_test.dart`, which is tagged `demo`; run that capture deliberately with `flutter test --tags demo test/demo_capture_test.dart`
- example: `cd example && flutter run`; the web build is deployed at <https://yusufihsangorgel.github.io/find_in_page/>
