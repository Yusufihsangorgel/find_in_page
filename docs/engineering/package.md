# Package engineering rules: find_in_page

Rules-Version: find_in_page/de1002b3b0565cedc53a0b27d557cf801fd24a927f3a58ea6cc48c75e5ae65fe
Core-Version: 1
Core-Digest: 1825fa7ff346dca23e65b1b3bf9b2e3e06959f1414bae9952d596d2f62f09b8f
Survey-Digest: f90f45c8a172068c3ed3b9488ba5a7cb4e58efa93c380d2d9a70b399349ec35e
Evidence-Revision: 35ae699
Verified-Revision: unverified

Read CONTRIBUTING.md and docs/engineering/debt.json before editing.

## Current architecture
HEAD 35ae699 (2026-09-22), version 2.4.0, 44 commits. Flutter package (flutter >=3.22.0, sdk ^3.4.0). The only runtime dependency is the Flutter SDK. The core is a ChangeNotifier based search controller (lib/src/controller.dart). Sources register themselves through the FindableSource interface (FindableText; FindableRecord items inside FindableListView) or are discovered by the FindInPageScope render tree scan (auto_discovery.dart). Matching happens in the pure Dart folding module (text_fold.dart). Highlighting has two paths: registered text restyles its own spans, discovered text is painted by the RenderHighlightOverlay on top. The scope shortcut (HardwareKeyboard) opens the FindBar inside an OverlayPortal and connects the dart:js_interop interceptor that arrives on web through a conditional export. There is no hook/ or bin/ (no FFI or native assets). AGENTS.md is written for an agent that uses the package (Usage/Contracts/Mistakes/Layout), and llms.txt redirects to AGENTS.md. The repository contains no contribution rules.

## Layers and responsibilities
- lib/find_in_page.dart: Only a show-listed export; library level dartdoc.
- lib/src/controller.dart: FindInPageController: query, flags, match counting, active match, source registration, visibility override policy, open/close state. FindMatch value type, FindableSource interface.
- lib/src/text_fold.dart: Case and accent folding, expanding letters (ß, Æ), mapping from folded offsets to source offsets. No Flutter import; has compile time table asserts.
- lib/src/auto_discovery.dart, lib/src/exclude_from_find.dart: Walks the render tree and produces RenderedTextSource from RenderParagraph and read-only RenderEditable. Stops at the ExcludeFromFind/RenderExcludeFromFind marker.
- lib/src/scope.dart, find_bar.dart, highlight_overlay.dart, findable_text.dart, findable_list_view.dart, findable_record.dart: Scope: shortcut, controller ownership, setting up discovery, opening the bar in an OverlayPortal. FindBar: Material interface. HighlightOverlay: paints discovered matches. FindableText/FindableListView: widgets that register their own text.
- lib/src/web_find_intercept.dart, web_find_intercept_stub.dart, web_find_intercept_web.dart: Conditional export; a stub with the same signatures for non-web; on web a single reference counted window keydown listener (dart:js_interop extension types).
- tool/: README figures (lazy_list_figure, searchable_grid); not library code.
- example/: Live demo; published to GitHub Pages through .github/workflows/pages.yml. No example tests.

## Public API and dependency direction
lib/find_in_page.dart exports only a show list: FindInPageController, FindMatch, FindableSource (controller.dart); ParagraphSource, ReadOnlyEditableSource, RenderedTextSource (auto_discovery.dart); ExcludeFromFind; FindBar; FindableListView, FindableListItemBuilder; FindableRecord; FindableText; FindInPageScope. Public names in src that are not exported: discoverTextSources, RenderExcludeFromFind, HighlightOverlay, RenderHighlightOverlay, foldForSearch, FoldedText, installWebFindIntercept, uninstallWebFindIntercept, webFindInterceptIsAttached. Leak: the exported FindInPageController carries setOpenCloseHandlers, setDiscovery, registeredSources, discoveredSources. These exist only for internal wiring (controller.dart:141, 204, 213, 218).

scope.dart → {auto_discovery, controller, find_bar, highlight_overlay, web_find_intercept}. findable_text.dart and findable_list_view.dart → {controller, exclude_from_find, scope} (the list also imports findable_record). highlight_overlay.dart → {auto_discovery, controller}. find_bar.dart → controller. auto_discovery.dart → {controller, exclude_from_find}. controller.dart → {auto_discovery, text_fold}. findable_record.dart → controller. text_fold.dart imports nothing (pure Dart). web_find_intercept.dart conditionally exports either the stub or the web file. Problem: a controller.dart ↔ auto_discovery.dart cycle. The controller needs this import only for the `is RenderedTextSource` special case at :314. The core therefore depends on a concrete source type. Material appears only at find_bar.dart:1. The rest of lib uses widgets/rendering/services/scheduler/foundation. Overall flow: presentation widgets → controller → pure folding. There is a back dependency from the controller to discovery (cycle).

## Error, state and platform contracts
- Source abstraction: abstract interface FindableSource + sealed RenderedTextSource. Equality is based on the identity of the render object (auto_discovery.dart:17-72).
- Ownership: `widget.controller ?? (_owned ??= ...)`. Only the owned controller is disposed. A provided controller is detached on dispose or swap (scope.dart:157-158, 172-187, 206-216; findable_list_view.dart:126-128, 159).
- Access: static maybeOf/of + a private InheritedWidget (scope.dart:133-144, 307-315). of() is guarded only by an assert.
- Timing: changes that arrive during build are coalesced and deferred to post-frame. The _disposed flag silences calls after dispose (controller.dart:239-246, 302-307, 147-156).
- Error contract: no custom exception type. Internal consistency is enforced with asserts (controller.dart:281, scope.dart:141-142). Without a scope, open/close is a no-op. Match offsets that fall out of range after a text change are skipped (findable_text.dart:151-154).
- Configuration: widget constructor parameters. Default colors are file-local const values (scope.dart:11-15). FindBar texts are parameters for l10n. There is also a matchStatusLabel builder (find_bar.dart:14-80).
- Platform check: the shortcut modifier is chosen with kIsWeb + defaultTargetPlatform (scope.dart:228-235). The web code sits behind a conditional export and matches the stub signature (web_find_intercept.dart:13-14).
- No FFI. Browser interaction uses hand written dart:js_interop extension types (web_find_intercept_web.dart:39-61). One window listener per process, reference counted.
- Streams/cancellation: no Stream. ChangeNotifier listeners are moved or removed in didUpdateWidget and dispose. Repaint goes through ListenableBuilder.
- A widget that reports its own text is wrapped with ExcludeFromFind. Discovery stops at RenderExcludeFromFind (this prevents double counting).
- The dartdocs give a long 'why' rationale and explicit boundary lists (scope.dart:17-77, findable_list_view.dart:56-65).

## Package rules
### find_in_page/FIP-01 [MUST]
Export public API only from lib/find_in_page.dart through explicit show lists. Keep implementation helpers (discoverTextSources, foldForSearch, FoldedText, HighlightOverlay, RenderHighlightOverlay, RenderExcludeFromFind, the web intercept functions) under lib/src and unexported.
Reason: Every current export uses a show list. Public helpers in src are deliberately left out. The boundary may grow only through a deliberate show entry. Otherwise it creates leaking API debt.
Evidence: lib/find_in_page.dart:10-20; lib/src/auto_discovery.dart:154; lib/src/text_fold.dart:6, 73; lib/src/highlight_overlay.dart:16, 107; lib/src/exclude_from_find.dart:39; lib/src/web_find_intercept_stub.dart:5-16
Evidence role: current-pattern
Existing violation: none

### find_in_page/FIP-02 [MUST_NOT]
Do not add public members to FindInPageController that exist only to wire FindInPageScope or the highlight overlay. The four such members that exist today are recorded for removal in the next major version.
Reason: setOpenCloseHandlers, setDiscovery, registeredSources and discoveredSources exist only for scope and overlay according to their dartdoc. They sit on the exported class, application code can call them, and they bind semver (leaking public API).
Evidence: lib/src/controller.dart:134-145, 193-206, 208-218; lib/src/scope.dart:166-169, 177-185, 190, 210-213; lib/src/highlight_overlay.dart:52, 156
Evidence role: counterexample
Existing violation: find_in_page-D002

### find_in_page/FIP-03 [MUST]
Keep text folding and offset mapping as pure Dart in lib/src/text_fold.dart, with no Flutter import. A change to the fold tables keeps the build-time range asserts and test/fold_table_test.dart passing.
Reason: Match correctness (accents, ß and Æ expansions, back-mapping of offsets) lives in a pure module. Missing table entries are caught by compile-time asserts. If it were tied to Flutter, unit testability would be lost.
Evidence: lib/src/text_fold.dart:1-3, 40-65, 73-114, 195-229; test/fold_table_test.dart
Evidence role: current-pattern
Existing violation: none

### find_in_page/FIP-04 [MUST]
Put browser-only code behind the conditional export in lib/src/web_find_intercept.dart, backed by a stub with identical signatures. No other lib file imports dart:js_interop.
Reason: Platform isolation today rests on a single seam: conditional export plus a stub with the same signature. Scope calls only this surface.
Evidence: lib/src/web_find_intercept.dart:13-14; lib/src/web_find_intercept_stub.dart:5-16; lib/src/web_find_intercept_web.dart:1, 12-34; lib/src/scope.dart:9, 164, 208
Evidence role: current-pattern
Existing violation: none

### find_in_page/FIP-05 [MUST]
A widget that reports its own text to the controller wraps what it renders in ExcludeFromFind. Discovery stops at RenderExcludeFromFind, and that stop stays in place.
Reason: Registration and discovery together count the same text twice. The two registered widgets follow this contract and dartdoc asks the same of custom widgets.
Evidence: lib/src/findable_text.dart:138-143; lib/src/findable_list_view.dart:231-233; lib/src/exclude_from_find.dart:23-26; lib/src/auto_discovery.dart:170-174
Evidence role: current-pattern
Existing violation: none

### find_in_page/FIP-06 [MUST]
Recompute matches for build-time callers (register, unregister, sourceTextChanged) through the coalesced post-frame path. Every post-frame callback returns early once the controller is disposed.
Reason: This path prevents notifyListeners from being called during build and computes once per frame. Staying silent after dispose prevents the race that arises when the scope closes a controller it was given.
Evidence: lib/src/controller.dart:147-156, 175-191, 220-229, 239-246, 302-307, 331-335
Evidence role: current-pattern
Existing violation: none

### find_in_page/FIP-07 [MUST]
Dispose only controllers the widget created. A passed-in controller is detached on dispose or swap (open/close handlers and discovery reset to null, sources unregistered) and never disposed.
Reason: The ownership pattern is the same across the scope, list and text widgets. Dartdoc says 'When null the scope creates and owns one'.
Evidence: lib/src/scope.dart:96-97, 157-158, 172-187, 206-216; lib/src/findable_list_view.dart:97-99, 124-128, 151-178; lib/src/findable_text.dart:121-133
Evidence role: current-pattern
Existing violation: none

### find_in_page/FIP-08 [MUST]
Depend on the Flutter SDK only. Browser interop stays on hand-written dart:js_interop extension types instead of an added package.
Reason: The dependency in pubspec is flutter only; web types are defined by hand. A new dependency changes the package promise and its maintenance load.
Evidence: pubspec.yaml dependencies (flutter: sdk); lib/src/web_find_intercept_web.dart:39-61
Evidence role: current-pattern
Existing violation: none

### find_in_page/FIP-09 [SHOULD]
Define the reveal motion (duration, curve, viewport alignment) once and reuse it. Do not add another literal copy.
Reason: The same 200 ms / easeInOut / 0.3 values are hand repeated in three places (duplicate constant, J5). A fourth copy would grow the inconsistency (debt B4).
Evidence: lib/src/controller.dart:322-327; lib/src/auto_discovery.dart:57-62; lib/src/findable_list_view.dart:220-225
Evidence role: counterexample
Existing violation: find_in_page-D004

### find_in_page/FIP-10 [MUST]
Ship every behaviour change with a test under test/ that drives the public library. Import lib/src from a test only to reach an unexported internal.
Reason: Repository history follows this pattern. Only 3 of the 14 test files import src for internal types.
Evidence: git 1470797 (lib/src/controller.dart, find_bar.dart, scope.dart + test/open_close_focus_test.dart); git 0ac419e (lib/src/web_find_intercept*.dart + test/web_find_intercept_test.dart); test/selection_interaction_test.dart:2; test/show_on_screen_test.dart:1; test/web_find_intercept_test.dart:2
Evidence role: current-pattern
Existing violation: none

### find_in_page/FIP-11 [MUST]
Keep CI green on dart format --output=none --set-exit-if-changed ., flutter analyze and flutter test --exclude-tags demo. Frame-capture tests stay tagged demo.
Reason: This is the current CI gate. The demo tag separates figure generation from the normal test run.
Evidence: .github/workflows/ci.yaml (run: dart format ..., flutter analyze, flutter test --exclude-tags demo); dart_test.yaml:1-6; analysis_options.yaml:1-4
Evidence role: current-pattern
Existing violation: none

### find_in_page/FIP-12 [SHOULD]
Only lib/src/find_bar.dart imports package:flutter/material.dart. The rest of lib uses widgets, rendering, services, scheduler or foundation.
Reason: The Material dependency today sits only in the ready-made bar. Core and discovery also work in apps that do not use Material.
Evidence: lib/src/find_bar.dart:1; lib/src/controller.dart:1-2; lib/src/scope.dart:1-3; lib/src/auto_discovery.dart:1-2; lib/src/highlight_overlay.dart:1-2; lib/src/findable_text.dart:1; lib/src/findable_list_view.dart:1; lib/src/exclude_from_find.dart:1-2
Evidence role: current-pattern
Existing violation: none

### find_in_page/FIP-13 [SHOULD]
A render object that listens to a Listenable subscribes in attach and unsubscribes in detach.
Reason: This is the Flutter lifecycle contract. Today RenderHighlightOverlay subscribes in the constructor and releases in detach (debt B1). The rule is right; that location is debt.
Evidence: lib/src/highlight_overlay.dart:109-117, 124-130, 146-150
Evidence role: counterexample
Existing violation: find_in_page-D001

## Required verification
- Working directory: repository root; command: flutter pub get; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:22.
- Working directory: repository root; command: dart format --output=none --set-exit-if-changed .; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:23.
- Working directory: repository root; command: flutter analyze; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:24.
- Working directory: repository root; command: flutter test --exclude-tags demo; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:25.
- Working directory: example; command: flutter build web --base-href /find_in_page/; conditions: pages.yml job deploy; evidence: .github/workflows/pages.yml:34.
Not verified by the survey:
- flutter analyze, flutter test and dart format were not run (read only; these commands write to build/ and .dart_tool/). The inference that analysis is clean today and that tests pass comes only from the CI configuration.
- The GitHub Actions history and the pub.dev score were not measured. They require network access.
- The difference between the working tree and HEAD was not measured (git status is not on the allow list). All line evidence refers to HEAD 35ae699.
- Debt items B1 (attach/detach) and B3 were found by static reading. They were not verified by running anything.
- There is no .pubignore at the root. Whether FEASIBILITY-web-ctrl-f.md (27 KB) and the tool/ files enter the pub archive was not measured (dart pub publish --dry-run was not run).
- It was not measured whether the root flutter analyze also covers the example/ directory.
- The bodies of FEASIBILITY-web-ctrl-f.md, README.md and CHANGELOG.md were not read. Only the headings and the Layout section of AGENTS.md were read.
- Test coverage percentage was not measured.
- It was not verified that the code compiles on Flutter 3.22.0.

## Existing debt
The complete register is docs/engineering/debt.json.
- find_in_page-D001 | small | lib/src/highlight_overlay.dart:109-117, 146-150 | lifecycle bug (potential, static reading)
  Fix: Move addListener into attach (after super.attach) and keep detach symmetric. Let the setter subscribe only while attached. Test: move FindInPageScope to another parent with a GlobalKey, then call search() and verify that the overlay repaints (red first).
  Closure: RenderHighlightOverlay adds the controller listener in attach, removes it in detach and lets the setter subscribe only while attached. A test that moves FindInPageScope to another parent with a GlobalKey and calls search() shows the overlay repainting.
- find_in_page-D002 | large | lib/src/controller.dart:134-145, 193-206, 208-218 | leaking public API
  Fix: Record it and plan it for the next major release: mark the members @internal (package:meta) or move them into a wiring object inside src. Until then add the dartdoc note 'for FindInPageScope, not for application code' and add no new ones (FIP-02).
  Closure: The four wiring members are marked @internal or moved into an unexported wiring object under lib/src, and the dartdoc note is in place until then. No public member of FindInPageController exists only to wire the scope or the overlay.
- find_in_page-D003 | small | lib/src/controller.dart:4, 313-319; lib/src/auto_discovery.dart:4 | import cycle / dependency inversion principle (DIP) violation
  Fix: Define an unexported single-method 'bring match on screen' interface (in controller.dart or a separate src file). Let RenderedTextSource implement it, let the controller ask `is <interface>` and drop the auto_discovery import. Behavior does not change; test/show_on_screen_test.dart acts as the safety net.
  Closure: controller.dart no longer imports auto_discovery.dart and reaches the bring-match-on-screen behavior through an unexported interface. test/show_on_screen_test.dart passes unchanged.
- find_in_page-D004 | small | lib/src/controller.dart:322-327; lib/src/auto_discovery.dart:57-62; lib/src/findable_list_view.dart:220-225 | duplicate constant
  Fix: Define a single private constant set inside src and let the three call sites use it. Behavior does not change.
  Closure: One private constant set in lib/src defines the 200 ms duration, the easeInOut curve and the 0.3 viewport alignment, and the three call sites use it. flutter test shows no behavior change.
- find_in_page-D005 | small | lib/src/controller.dart:140, 203 | lint suppression without a reason
  Fix: Add a reason on the same line (public API; converting to a setter would be a breaking change) or remove the suppressions when debt B2 closes.
  Closure: Each ignore: use_setters_to_change_properties carries a written reason naming the public API constraint, or the suppressions disappear when the members leave the public API.
- find_in_page-D006 | small | test/fold_table_test.dart:54-55, 73, 87, 128, 151 | test noise
  Fix: Move the details into expect(..., reason: ...); delete the prints and the ignores.
  Closure: test/fold_table_test.dart contains no print calls and no avoid_print ignores. Each former print detail appears as a reason argument on an expect.
- find_in_page-D007 | small | lib/src/web_find_intercept_web.dart:36-37 | undocumented global mutable state (J6/D3b)
  Fix: Write `///` docs for both fields: install/uninstall reference counting, reads by the keydown listener, removal when the last client detaches. The code does not change.
  Closure: The _clients and _listener fields in web_find_intercept_web.dart carry /// docs stating the install and uninstall reference counting, the readers and the removal when the last client detaches.
- find_in_page-D008 | small | lib/src/text_fold.dart:226 | duplicate constant
  Fix: Use the `_firstFoldable` constant.
  Closure: text_fold.dart uses the _firstFoldable constant in place of the 0x00C0 literal at line 226. test/fold_table_test.dart still passes.
- find_in_page-D009 | medium | lib/src/controller.dart:248-300 | cognitive complexity (J2) / single responsibility
  Fix: Extract the scan loop into a pure function in text_fold.dart (folded text + needle → list of ranges) and add unit tests next to fold_table_test. Let the controller only dispatch results.
  Closure: The scan over folded text is a pure function in lib/src/text_fold.dart with unit tests beside fold_table_test.dart. _recompute only merges discovery results and applies the active index policy.
- find_in_page-D010 | small | .github/workflows/ci.yaml (tek job, channel: stable); pubspec.yaml environment | CI coverage gap
  Fix: Add 3.22.0 to the matrix as in text_autosize; let the format check run on stable only.
  Closure: The CI matrix runs the format, analyze and test gate on Flutter 3.22.0 as well as stable. The format check still runs on stable only.
