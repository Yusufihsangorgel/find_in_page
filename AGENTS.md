# find_in_page

`FindInPageScope` searches the text Flutter rendered inside its `child`, including widgets you did not write (`AppBar`, `ListTile`, `DataTable`, `Text.rich`, `SelectableText`). Ctrl+F (Cmd+F on macOS and iOS) opens `FindBar`; typing highlights matches and `next` / `previous` scroll the active one into view.

Discovery only yields `ParagraphSource` (`RenderParagraph`) and `ReadOnlyEditableSource` (read-only, non-obscured `RenderEditable`). It cannot see platform views or WebViews, `TextField` / editable values, icon glyphs, collapsed `ExpansionTile` children, unselected tabs, or lazy-list rows that were never built.

## Usage

Put `FindInPageScope` **inside** `MaterialApp` / `CupertinoApp` / `WidgetsApp` (the built-in bar needs an `Overlay` ancestor) and **around** the content it should search. The example wraps the whole `Scaffold`, not just `body`, so the `AppBar` title is included:

```dart
import 'package:find_in_page/find_in_page.dart';
import 'package:flutter/material.dart';

return MaterialApp(
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
);
```

`autoDiscover` defaults to true: unwrapped `Text` is enough. `FindableText` is optional and highlights by restyling spans instead of the overlay. Wrap chrome in `ExcludeFromFind` (the example does this for the mode toggle).

## Contracts

**Placement.** The sweep starts at `FindInPageScope.child`. Widgets above the scope are not searched. `FindInPageScope.maybeOf` returns the nearest controller or null; `FindInPageScope.of` asserts if missing.

**Dispose.** Omit `controller` and the scope constructs and `dispose`s a `FindInPageController`. If you pass one, you own it (`ChangeNotifier`); the scope only calls `setDiscovery(null)`. Same split for `FindableListView.scrollController`. `FindableText` `register`s in `didChangeDependencies` and `unregister`s in `dispose`; a custom `FindableSource` must do the same, call `sourceTextChanged` when `findableText` changes, paint from `matchesFor(this)`, and wrap its render in `ExcludeFromFind` (registration identity does not hide a `ParagraphSource` of the same text). `FindableListView` unregisters its `FindableRecord`s on dispose.

**Controller lifetime.** `search` / `next` / `previous` / `clearSearch` are the session. Matching is a case- and diacritic-insensitive substring by default (`resume` finds `résumé`). `caseSensitive` and `diacriticSensitive` are sticky: a later `search(query)` without those args keeps the last setting. `register` is safe during build; recompute is post-frame. `isActive` is `identical`, so a `FindMatch` from a previous search is never active. The example keys the scope (`ValueKey`) when swapping the page so matches do not carry over.

**Lazy lists.** `FindableText` is searchable only while mounted. `ListView.builder` plus `FindableText` misses unbuilt rows and `matchCount` drifts as children dispose. Use `FindableListView`: it registers every index through `findableTextOf` up front. Reveal animates `scrollController` to `index * itemExtent`, so `itemExtent` is required and variable-height items are unsupported. The list wraps itself in `ExcludeFromFind` and does not paint highlights; `itemBuilder` must, from that row's `matches` and `activeMatchIndex` (index into `matches`, or null; copy `_HighlightedRow` in `example/lib/main.dart`). Explicit controller param is `findController`. Off-screen data without a list: `register(record, reveal: ...)`.

**Focus / keyboard.** While mounted, `FindInPageScope` handles the shortcut via `HardwareKeyboard` globally; the handler itself does not steal focus (`FindBar.autofocus` defaults to true once the bar is shown). Escape is consumed only while the built-in bar is visible, and then runs `clearSearch`. `showBar: false` with no `onOpenRequested` ignores the shortcut; with it, the callback runs and Escape does not clear. `FindBar` Enter calls `next`. The bar lives in the `Overlay`, outside `child`, so the query field is not searched.

## Mistakes

- **Scope not an ancestor of the text.** Symptom: `matchCount == 0`, nothing highlights, no error. Fix: wrap the page (`Scaffold` in the example).
- **Scope above `MaterialApp`.** Symptom: Ctrl+F looks like a no-op (no `Overlay` for `FindBar`). Fix: scope as a descendant of the app widget.
- **`ListView.builder` of `Text` or `FindableText`.** Symptom: far rows never found; count changes while scrolling. Fix: `FindableListView`.
- **`FindableListView` `itemBuilder` ignores `matches`.** Symptom: count and scroll work, nothing is highlighted. Fix: paint from `FindMatch.start` / `end`. Do not nest `FindableText` in the row — that double-counts built items and the count drifts again.
- **`autoDiscover: false` with unwrapped `Text`, or `FindableText` / `FindableListView` outside a scope with no `controller` / `findController`.** Symptom: 0/0 or a list that never highlights (`maybeOf` is null). Fix: leave the default, or pass the controller you constructed.
- **Expecting `TextField` values to match.** Symptom: form contents never highlighted. Deliberate; `SelectableText` is searched.
- **Chrome left searchable, or a custom `FindableSource` that still renders text.** Symptom: extra matches, or `matchCount` doubled. Fix: `ExcludeFromFind`.
- **Disposing the wrong controller.** Symptom: leaks or use-after-dispose. Call `dispose` only on a `FindInPageController` you constructed.
- **`search(q, caseSensitive: true)` then `search(other)`.** Symptom: later searches stay sensitive. Pass the flag again to change it. Same for `diacriticSensitive`. Query is a plain substring, not a regex.

## Layout

- `lib/find_in_page.dart` — public exports
- `lib/src/` — implementation
- `example/lib/main.dart` — eager page and 2,000-row `FindableListView`
- `test/` — `flutter test` from the repo root. `test/demo_capture_test.dart` is tagged `demo` and excluded (`dart_test.yaml`); run it with `flutter test --tags demo test/demo_capture_test.dart`
- example: `cd example && flutter run`
