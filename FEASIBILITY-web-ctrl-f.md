# Feasibility: intercepting Ctrl+F / Cmd+F on Flutter web

**Date:** 2026-08-29
**Scope:** research only. No package code was changed. No browser, app, screenshot, or other observation of this machine was used.

## Headline

An in-app find bar **can** take over the **keyboard** shortcut on Flutter web often enough to be worth shipping, as a **best-effort intercept**, on Chrome and Firefox. Flutter’s web engine already maps “the framework handled this key” onto `keydown.preventDefault()`, and this package already returns handled for Ctrl/Cmd+F. Chrome and Firefox are documented, in multiple independent places, as honouring `preventDefault` on that combination. Safari on macOS did the same in a 2020 key-by-key survey; that result is old.

That is **not** a fix for [flutter/flutter#65504](https://github.com/flutter/flutter/issues/65504). Intercepting the shortcut does not put text into the DOM, does not make the browser’s own find bar, reader mode, or a crawler see the canvas, and cannot stop Find chosen from a browser menu or from mobile-browser chrome. The honest product is: *when the user presses the keys, open our bar instead of theirs, on browsers that allow it*.

**Confidence:** medium that this is shippable as a documented best-effort intercept on Chrome / Edge / Firefox; high that `preventDefault` on Ctrl/Cmd+F works in ordinary page JS on those browsers; medium that this package’s existing Dart handler already does that on Flutter web; low that the native bar is *guaranteed* never to appear, including on current Safari.

A live matrix in Chrome, Firefox, and Safari (macOS and iOS), with and without Flutter web semantics enabled, is still required before calling the intercept “reliable.” That test was forbidden in this pass.

---

## How to read this

Each claim is one of:

- **Verified** — taken from a source named in the same paragraph.
- **Inferred** — follows from those sources plus this repo’s code, not itself observed.
- **Could not determine** — would need a browser, a running app, or a source that was not found.

Sources that disagree, or that are more than a few years old, are called out in place.

---

## 1. Which layer has to handle it, and whether `preventDefault` works

### 1.1 The Flutter layer already has a path

**Verified (this repo).** `FindInPageScope` registers a global `HardwareKeyboard` handler and, on Ctrl+F or Cmd+F, opens the bar and **returns `true`** (`lib/src/scope.dart`, `_onKeyEvent`). Escape is consumed only while the built-in bar is visible.

**Verified (Flutter API).** [`HardwareKeyboard.addHandler`](https://api.flutter.dev/flutter/services/HardwareKeyboard/addHandler.html): every handler runs; if any returns `true`, Flutter treats the event as handled. The docs mention add-to-app propagation; on web the same handled bit is what the engine reads.

**Verified (Flutter web engine, `master` as fetched 2026-08-29).** [`keyboard_binding.dart`](https://raw.githubusercontent.com/flutter/flutter/master/engine/src/flutter/lib/web_ui/lib/src/engine/keyboard_binding.dart):

- Listens on `window` for `keydown` / `keyup` in the **capture** phase (`addEventListener(..., true)`).
- Dispatches into the framework **synchronously** (`_onKeyData` asserts the callback runs before it returns).
- After the primary `KeyData` dispatch: `if (primaryHandled) { event.preventDefault(); }`.

So the Dart handler this package already has is, on paper, the right layer: capture on `window`, sync into Flutter, `preventDefault` if handled.

**Inferred.** A *second* JS listener is not required for the event to *reach* Dart, and is not required for `preventDefault` to be *called*, if the handled bit is true. A thin web-only JS listener is still the usual belt-and-suspenders in non-Flutter web apps, and it would still fire in cases where Flutter never sees the key (see 1.4).

**Verified, dated (2021).** [Stack Overflow 67039462](https://stackoverflow.com/questions/67039462/how-do-i-disable-default-browser-shortcuts-in-flutter-web) said Flutter had no framework way to `preventDefault` and that you should paste JS into `index.html`. That matches the **old** web keyboard path, which only `preventDefault`’d Tab ([flutter/engine#12986](https://github.com/flutter/engine/pull/12986), 2019). The current `keyboard_binding.dart` path supersedes that. Do not take the 2021 answer as current.

### 1.2 The spec does not promise that find is a cancelable default action

**Verified.** [UI Events](https://w3c.github.io/uievents/) (`keydown` is cancelable; default action “Varies: … other event”). If canceled, “the associated actions MUST NOT be performed.” The spec does **not** name find-in-page as a `keydown` default action. Whether Find is canceled is a **user-agent choice**, not a spec guarantee.

**Verified.** Chromium treats this as case-by-case. Chromium IRC, quoted in [SO 59952382](https://stackoverflow.com/questions/59952382/using-preventdefault-to-override-opening-new-tab) (2020): “we decided case-by-case which shortcuts should/shouldn't be override-able”; high-priority accelerators never reach the page. [`AcceleratorManager`](https://chromium.googlesource.com/chromium/src/+/f553247ebf96528afde64b205cc4fb8733fb08ce/ui/base/accelerators/accelerator_manager.h): `kHighPriority` “prevents Chrome from sending the shortcut to the webpage.” Chrome’s browser-view accelerator table registers ordinary Chrome commands at **`kNormalPriority`** ([`browser_view.cc` `LoadAccelerators`](https://source.chromium.org/chromium/chromium/src/+/main:chrome/browser/ui/views/frame/browser_view.cc)), i.e. they *are* sent to the page.

**Could not determine** from a single Chromium listing whether `IDC_FIND` is ever registered high-priority. Indirect evidence that it is **not** reserved: Chrome’s own WebUI find helper calls `preventDefault` on Ctrl/Cmd+F ([`find_shortcut_manager.ts`](https://chromium.googlesource.com/chromium/src/+/5b2b24a000c51aefa98d18c1dd32fad89e94a929/ui/webui/resources/cr_elements/find_shortcut_manager.ts)).

Keyboard Lock (`navigator.keyboard.lock`) is the wrong tool: it is experimental, aimed at fullscreen games, and meant for keys the page **cannot** normally see ([MDN Keyboard API](https://developer.mozilla.org/en-US/docs/Web/API/Keyboard_API)).

### 1.3 Per browser: does `preventDefault` on Ctrl/Cmd+F actually stop Find?

| Browser | Shortcut | Does `preventDefault` on `keydown` stop Find? | Basis |
|---|---|---|---|
| Chrome (and Chromium Edge) | Ctrl+F / Cmd+F | **Usually yes** | Multiple independent sources, production apps, Chromium’s own WebUI |
| Firefox | Ctrl+F / Cmd+F | **Usually yes, unless the user (or policy) blocked page overrides** | Same class of evidence, plus an explicit Firefox permission |
| Safari (macOS) | Cmd+F | **Probably yes, last measured 2020** | One thorough key-by-key survey; one 2010 WebKit note that macOS *can* suppress Command-F |
| Safari (Windows) | Ctrl+F | Historically **no** | [WebKit 35849](https://bugs.webkit.org/show_bug.cgi?id=35849) (2010, UNCONFIRMED). Windows Safari is discontinued. |
| Safari / Chrome on iOS | no desktop-style Cmd+F | **Not a keyboard problem** | Find is in browser chrome / share sheet, not a page key |

#### Chrome

**Verified.**

- [SO 44998250](https://stackoverflow.com/questions/44998250/which-chrome-keyboard-shortcuts-cannot-be-overridden-with-javascript) (2018, comments through 2021): “Ctrl+S and Ctrl+F you can override. Ctrl+W you cannot.” Ctrl+N/T/W and Ctrl+Tab are the ones called reserved.
- Chrome’s own settings UI intercepts Ctrl/Cmd+F with `preventDefault` (`find_shortcut_manager.ts`, cited above).
- Production web apps that take over Find are a matter of public record: Google Docs/Sheets ([WIRED, 2024](https://www.wired.com/story/best-google-docs-keyboard-shortcuts-productivity/), [UX.SE 152228](https://ux.stackexchange.com/questions/152228/can-it-be-acceptable-to-take-over-ctrl-f-shortcut-in-web-app)), Discourse, Outlook Web, Slack. Users complain *because the intercept works* ([Super User 1038172](https://superuser.com/questions/1038172/chrome-search-in-page-when-ctrlf-shortcut-is-hijacked), still getting answers in 2025).
- [Qiita, Feb 2020](https://qiita.com/pochman/items/3aa40ad71e5320192820), author pressed every key on Mac OS 10.14 / Chrome 79: Command+F “page内を検索”, `keydown` `preventDefault` = **yes**.

**Disagreement, lower weight.** A Jan 2026 blog, [xjavascript.com](https://www.xjavascript.com/blog/available-keyboard-shortcuts-for-web-applications/), lists Ctrl/Cmd+F as “Overridable? No”. That contradicts Chrome’s own WebUI, the 2018 SO reserved-list, the 2020 Qiita table, and every “please stop hijacking Ctrl+F” thread. Treat it as wrong or over-general unless a 2026 Chrome build is shown to have changed.

**Could not determine:** whether *current* Chrome still honours this inside a Flutter canvaskit/skwasm page (hidden `<input>` for text editing, semantics host, capture listener order). Not run.

#### Firefox

**Verified.**

- Same 2020 Qiita table: Command+F, `keydown` `preventDefault` = **yes** (Firefox 72).
- Firefox 58+ has a page permission **“Override Keyboard Shortcuts”**, **allowed by default**. Users and admins can set it to Block (`permissions.default.shortcuts = 2`). Mozilla support: [“Usually sites have permission to override built-in keyboard shortcuts by default”](https://support.mozilla.org/en-US/questions/1387304); Super User [168087](https://superuser.com/questions/168087/how-to-forbid-keyboard-shortcut-stealing-by-websites-in-firefox). When blocked, the event is not delivered to the page ([bug 380637](https://bugzilla.mozilla.org/show_bug.cgi?id=380637)).
- GitHub hijacking Ctrl+F is a known Firefox userscript target ([Super User 399352](https://superuser.com/questions/399352/how-do-i-prevent-pages-i-visit-from-overriding-selected-firefox-shortcut-keys) comment, 2023).

**Inferred.** On a default Firefox profile, intercepting Find is as real as on Chrome. A user or enterprise that blocked overrides is a documented refusal case (section 4).

#### Safari

**Verified, dated.**

- Qiita 2020, Safari 13.0.4 on macOS: Command+F, `keydown` `preventDefault` = **yes**. Same for Command+G (find next). Command+N/T/W/Q/R were **no**.
- [WebKit 35849](https://bugs.webkit.org/show_bug.cgi?id=35849) (2010, UNCONFIRMED): on **Windows** WebKit, F5 and Ctrl+F could not be suppressed. The reporter wrote that **OS X Safari did suppress Command-F**. Comment 1 (ap): “I think this was done on purpose.”
- Safari remains stricter on other chords (Command+L, Command+R, Command+T, Command+,). That is consistent with the 2020 table and does **not** by itself mean Command+F is reserved.

**Could not determine:** Safari 17–26 on macOS, and Safari on iOS/iPadOS (where Find is a chrome/share-sheet action, not Cmd+F). Not run. A 2026 live check is the single most important missing measurement.

### 1.4 Why Flutter’s existing `return true` might still not be enough

These are **inferred** from engine source, not observed:

1. **Semantics gate.** `KeyboardBinding` only forwards the DOM event if `EngineSemantics.instance.receiveGlobalEvent(event)` is true. While Flutter web is still waiting to enable semantics, some keydowns are swallowed as activation attempts and never reach the framework — so `preventDefault` is never called. A JS listener that is *not* behind that gate would still run.
2. **Handled bit vs Find as chrome.** If a given browser treats Find as a chrome accelerator rather than a cancelable `keydown` default action, Flutter can “handle” the key, call `preventDefault`, and Find still opens. Chrome/Firefox evidence says that is *not* the usual case; it remains the Safari risk.
3. **Only one modifier.** The package picks Meta on Apple `defaultTargetPlatform` and Control otherwise. Flutter web’s `defaultTargetPlatform` follows the user agent, so Chrome-on-Mac should listen for Cmd+F, which is what Chrome-on-Mac uses. A Windows keyboard attached to a Mac, or a user who presses Ctrl+F on macOS Chrome, is an edge. **Could not determine** whether Chrome-on-Mac still opens Find on Ctrl+F.
4. **Leftover find-next chords.** F3, Ctrl+G, Cmd+G, Shift+F3 are also Find in various browsers. Intercepting only F leaves a way to open or step native Find. Super User 1038172: when a site hijacks Ctrl+F, F3 or Alt-then-Ctrl+F still opens Chrome’s bar; a 2025 comment says Ctrl+G still works in Outlook Web on macOS Chrome.

**Verified (Flutter).** Native Find is not only useless on canvas; it has also **broken Flutter `TextField`s**. [flutter/flutter#82708](https://github.com/flutter/flutter/issues/82708) (open): after Cmd/Ctrl+F, text fields stop accepting input. Intercepting is not only an accessibility feature; it avoids a known engine footgun.

### 1.5 What 65504 actually asked for

**Verified.** [flutter/flutter#65504](https://github.com/flutter/flutter/issues/65504) (open since 2020, P3, still the canonical thread; duplicates include [#163614](https://github.com/flutter/flutter/issues/163614) after the HTML renderer was removed, and [#172761](https://github.com/flutter/flutter/issues/172761) in 2025).

Yjbanov, 2021-03-04: many web apps “actively redirect the Ctrl+F shortcut to their custom search bars”; a custom search “might be a better fit”; mobile web cannot intercept Ctrl+F. Later: HTML renderer made on-screen text *somewhat* findable; that renderer is gone.

Guplem / framework, 2022-12-16: “As an MVP we could start with a **pure framework implementation that uses a keyboard shortcut**. Integration with browser search can be attempted as a follow-up.”

Nt4f04uNd, 2021: hijacking Ctrl+F is “considered a bad practise” on ordinary sites — because those sites have real HTML. On a canvas it is the only thing the keyboard shortcut can usefully do.

This package is exactly that MVP. It does not close 65504, which is still about the **native** bar, reader mode, and off-screen / never-built text as the **browser** sees it.

---

## 2. What suppressing native Find would owe the user — and what this package already has

Taking over Ctrl+F on a document that the browser cannot search is defensible only if the replacement is a find bar, not a site-search box. [UX.SE 152228](https://ux.stackexchange.com/questions/152228/can-it-be-acceptable-to-take-over-ctrl-f-shortcut-in-web-app) is explicit: Ctrl+F must not change page contents or fire a network search. GitHub’s a11y write-up also calls overriding Cmd/Ctrl+F “generally bad practice for screen readers” *when the DOM still contains the text* ([GitHub Blog, 2023](https://github.blog/engineering/accessibility-considerations-behind-code-search-and-code-view/)). Here the DOM does not.

WCAG 2.1.4 (Character Key Shortcuts) is about **unmodified** character keys, not Ctrl/Cmd+F. It is not a prohibition. The debt is product, not that SC.

| Native-find job | This package | Symbol |
|---|---|---|
| Open on Ctrl+F / Cmd+F | Yes (global, no focus steal) | `FindInPageScope._onKeyEvent` / `HardwareKeyboard.instance.addHandler` |
| Query field, autofocus | Yes | `FindBar` (`autofocus`, default true); `FindBar.hintText` |
| Match count | Yes | `FindInPageController.matchCount`; visible `1/n` in `FindBar` |
| Active match index | Yes | `FindInPageController.activeMatchIndex`, `activeMatch`, `isActive` |
| Next / previous (wrap) | Yes | `FindInPageController.next`, `.previous`; `FindBar` down/up buttons; Enter → `next` via `FindBar._submit` |
| Scroll active match into view | Yes | `FindInPageController._revealActive` (private, called from `search` / `next` / `previous`): `Scrollable.ensureVisible`, `RenderedTextSource.showMatchOnScreen`, or a registered `reveal` (`FindableListView`) |
| Highlight all + active | Yes | Discovery: `HighlightOverlay`; wrapped text: `FindableText`; lists: `itemBuilder` + `FindMatch.start` / `.end` |
| Escape closes and clears | Yes, only while the built-in bar is open | `FindInPageScope._onKeyEvent` → `_close` → `FindInPageController.clearSearch`; also `FindBar` `CallbackShortcuts` on Escape → `onClose` |
| Screen-reader announcement of count | Yes, live region | `FindBar.matchStatusLabel` (default `"Match 1 of 3"` / `"No matches"`); `Semantics(liveRegion: true)` around `ExcludeSemantics` of the visible `1/3`. Tests: `test/find_bar_semantics_test.dart` |
| Close control | Yes | `FindBar` close `IconButton` (`closeTooltip`) |
| Custom UI instead of built-in bar | Yes | `FindInPageScope.showBar`, `onOpenRequested` |

**Not implemented, and a native bar would have them:**

- F3 / Ctrl+G / Cmd+G / Shift+F3 (find next/previous from the keyboard without the bar focused).
- Case-sensitivity toggle in the bar (the controller has `caseSensitive` / `diacriticSensitive`, sticky, but `FindBar` does not expose them).
- Whole-word, regex (the matcher is a folded substring; README: not a regex).
- Scrollbar tick marks.
- Opening from the browser’s Edit → Find, or iOS/Android “Find on Page”.
- Searching `TextField` values (deliberate; README).
- Searching unbuilt lazy rows without `FindableListView` (documented limitation).

For a keyboard intercept, the table above is the bar a user is owed. This package already has that bar. The intercept would not need a new UI; it would need the native bar not to open **as well**.

---

## 3. How `lib/` is organised, and a web-only path that leaves other platforms alone

Current layout (no web-conditional files today):

```
lib/find_in_page.dart          public exports
lib/src/
  scope.dart                   FindInPageScope, HardwareKeyboard, OverlayPortal, FindBar
  controller.dart              FindInPageController, FindMatch, FindableSource
  find_bar.dart                FindBar
  auto_discovery.dart          ParagraphSource, ReadOnlyEditableSource, RenderedTextSource
  highlight_overlay.dart       overlay highlights for discovered text
  findable_text.dart           FindableText
  findable_list_view.dart      FindableListView
  findable_record.dart         FindableRecord
  exclude_from_find.dart       ExcludeFromFind
  text_fold.dart               case/diacritic folding
```

`pubspec.yaml`: Flutter SDK only, `sdk: ^3.4.0`, `flutter: ">=3.22.0"`, platforms include web. No `dart:html`, no `package:web`, no conditional imports.

A web-only intercept must **not** import `dart:html` from a shared library (deprecated, not Wasm-safe) and must **not** use `if (dart.library.html)` as the compile-time switch.

**Verified (Dart docs).** [Migrate to package:web](https://dart.dev/interop/js-interop/package-web): differentiate VM vs web with `dart.library.js_interop`, not `dart.library.html`.

Smallest structure that leaves Android/iOS/desktop compiles untouched:

```
lib/src/web_find_intercept.dart           // export stub if js_interop web
lib/src/web_find_intercept_stub.dart      // no-ops; used on VM
lib/src/web_find_intercept_web.dart       // package:web / dart:js_interop
```

```dart
export 'web_find_intercept_stub.dart'
    if (dart.library.js_interop) 'web_find_intercept_web.dart';
```

Call `install` from `FindInPageScopeState.initState` and `uninstall` from `dispose`. The stub is empty. The web file adds a **capture** `keydown` on `window` (same phase Flutter already uses), `preventDefault`s Ctrl/Cmd+F when the scope would handle it, and does not need to open the bar — Dart already does that.

Do **not** ask the app to paste script into `index.html`. A package cannot ship that for every host, and it is the 2021 workaround this engine path made unnecessary for Tab-like handling.

`kIsWeb` alone is not a substitute for the conditional import: a `dart:html` / `package:web` import in a file that VM compiles will fail analysis even behind `if (kIsWeb)`.

`avoid_web_libraries_in_flutter` fires on unconditional web imports in a non-plugin package. Conditional import of the web file is the documented way around that.

**Inferred.** `package:web` as a dependency is the current Dart recommendation; `dart:js_interop` externs without `package:web` also compile to Wasm. Either is fine. `dart:html` is not.

---

## 4. Smallest honest version of the feature

### What to build

1. Keep the existing `HardwareKeyboard` handler. It is the right Dart API and, on web, is the path the engine uses to `preventDefault`.
2. Add the conditional-import capture listener in §3 so `preventDefault` still happens if Flutter’s semantics gate drops the key, and so both Control and Meta can be suppressed on web regardless of `defaultTargetPlatform`.
3. Optionally, on web only, also suppress F3 and Ctrl/Cmd+G (find next) so leftover chords do not open the native bar. Out of scope for the smallest version; document the hole if skipped.
4. Do nothing on VM. No new widgets, no new public API required. If an API is added, a boolean `interceptBrowserFind` defaulting to true on web is enough.

### What it must not claim

- That this **fixes** flutter#65504.
- That the **browser’s** find bar, reader mode, or a crawler can now see canvas text. They cannot. README today is correct on that point (“This does not fix the browser’s own Ctrl+F, and nothing written in Dart can” — meaning *native* find against the canvas, not “Dart cannot call `preventDefault`”).
- That Find from the **browser menu**, iOS share sheet, or Android “Find in page” is intercepted. Pages cannot see those.
- That interception is 100% on Safari, or on Firefox with “Override Keyboard Shortcuts” set to Block.
- That `TextField` values, icon glyphs, collapsed tiles, or unbuilt `ListView.builder` rows become searchable. They do not; that is this package’s existing contract.
- That a second Ctrl+F, F3, or Alt-then-Ctrl+F will never surface the native bar ([Super User 1038172](https://superuser.com/questions/1038172/chrome-search-in-page-when-ctrlf-shortcut-is-hijacked)).

### What should happen when the browser refuses

**Inferred product behaviour; not observed.**

| Refusal | What the user sees | What the package should do |
|---|---|---|
| Chrome/Firefox honour `preventDefault` | Only the in-app bar | Normal session |
| Safari (or a future Chrome) ignores `preventDefault` | **Both** bars. Native find matches nothing useful on canvaskit/skwasm. In-app bar still works. | Keep opening the in-app bar. Do not throw. Document “you may also see the browser’s empty find UI.” |
| Firefox “Override Keyboard Shortcuts” = Block | Native bar only; Dart may not even get the key | In-app bar does not open from the shortcut. User can still be given a visible Find control. Native bar still searches an empty canvas. |
| Edit → Find / iOS Find on Page | Native bar only | Same as above. No keyboard event exists to intercept. |
| Mobile web, no keyboard | No shortcut | Existing mobile gap. 65504 already called this out. A toolbar button is the honest mobile affordance; it is not part of intercept. |

Never fight the native bar with hacks (hidden alphabet DOM, scroll-spy on the browser find highlight). Those were sketched on 65504 in 2021 and are not this package’s job.

### Docs the feature would owe

- A short “Web” section: we intercept the **keys** when the browser lets us; we do not replace the browser’s find engine.
- Point at Firefox’s permission and at menu/mobile chrome.
- Keep the existing canvas / 65504 warning. Change only the sentence that can be read as “Dart cannot intercept the shortcut.”

---

## 5. Could not determine (explicit)

A live Flutter web app was not run. The following stay open until someone does:

1. In **current** Chrome, Firefox, and Safari, with canvaskit and with skwasm, does Ctrl/Cmd+F open only `FindBar`, only the native bar, or both, with `FindInPageScope` mounted as today (Dart `return true` only, no extra JS)?
2. Same matrix with `SemanticsBinding.instance.ensureSemantics()` on, and with the default “invisible Enable accessibility button” still in the way.
3. Does Safari 18–26 on macOS still honour `preventDefault` on Command+F (last hard measurement: Safari 13, 2020)?
4. Does Chrome-on-Mac open Find on **Ctrl+F** as well as Cmd+F?
5. After intercept, does [flutter#82708](https://github.com/flutter/flutter/issues/82708) (TextField dead after native Find) stop reproducing — i.e. is intercept also a bug workaround?
6. Capture-listener order: Flutter registers at engine init; a package listener registers later. Both capture. First registered runs first. Does that matter if both call `preventDefault`? Almost certainly not; not proven.

Until (1) and (3) are answered, “reliably enough to ship” must stay a **conditional yes**: ship as best-effort, test the matrix, do not advertise a 65504 fix.

---

## Sources (primary)

- This repo: `lib/src/scope.dart`, `lib/src/find_bar.dart`, `lib/src/controller.dart`, `README.md`, `test/find_bar_semantics_test.dart`
- Flutter web engine `keyboard_binding.dart` (master): <https://raw.githubusercontent.com/flutter/flutter/master/engine/src/flutter/lib/web_ui/lib/src/engine/keyboard_binding.dart>
- `HardwareKeyboard.addHandler`: <https://api.flutter.dev/flutter/services/HardwareKeyboard/addHandler.html>
- flutter/flutter#65504 and comments (yjbanov 2021, guplem 2022): <https://github.com/flutter/flutter/issues/65504>
- UI Events `keydown`: <https://w3c.github.io/uievents/>
- Chromium reserved vs overridable: [SO 44998250](https://stackoverflow.com/questions/44998250/which-chrome-keyboard-shortcuts-cannot-be-overridden-with-javascript), [SO 59952382](https://stackoverflow.com/questions/59952382/using-preventdefault-to-override-opening-new-tab), [accelerator_manager.h](https://chromium.googlesource.com/chromium/src/+/f553247ebf96528afde64b205cc4fb8733fb08ce/ui/base/accelerators/accelerator_manager.h), [find_shortcut_manager.ts](https://chromium.googlesource.com/chromium/src/+/5b2b24a000c51aefa98d18c1dd32fad89e94a929/ui/webui/resources/cr_elements/find_shortcut_manager.ts)
- Qiita 2020 key-by-key `preventDefault` table (Safari 13 / Chrome 79 / Firefox 72, macOS): <https://qiita.com/pochman/items/3aa40ad71e5320192820>
- WebKit 35849: <https://bugs.webkit.org/show_bug.cgi?id=35849>
- Firefox override permission: <https://support.mozilla.org/en-US/questions/1387304>, <https://bugzilla.mozilla.org/show_bug.cgi?id=380637>
- Sites hijacking Find (evidence that intercept works): [Super User 1038172](https://superuser.com/questions/1038172/chrome-search-in-page-when-ctrlf-shortcut-is-hijacked)
- Flutter web `preventDefault` from Dart, 2021 (outdated): [SO 67039462](https://stackoverflow.com/questions/67039462/how-do-i-disable-default-browser-shortcuts-in-flutter-web)
- Native Find vs Flutter TextField: [flutter#82708](https://github.com/flutter/flutter/issues/82708)
- Conditional imports / Wasm: <https://dart.dev/interop/js-interop/package-web>
- Conflicting “Ctrl+F not overridable” list: <https://www.xjavascript.com/blog/available-keyboard-shortcuts-for-web-applications/>
