import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'auto_discovery.dart';
import 'controller.dart';
import 'find_bar.dart';
import 'highlight_overlay.dart';
import 'web_find_intercept.dart';

/// Translucent yellow, the colour browsers paint behind find matches.
const Color _matchFill = Color(0x80FFEB3B);

/// Translucent orange, the colour browsers paint behind the active match.
const Color _activeMatchFill = Color(0xB3FF9800);

/// Wires find-in-page into a subtree: searches the text rendered inside it,
/// opens a [FindBar] on the platform find shortcut (Cmd+F on macOS and iOS,
/// Ctrl+F elsewhere; either modifier on web), and closes it on Escape.
///
/// By default the scope finds text on its own. Every string Flutter draws is
/// searchable whether or not you wrapped it, including text inside widgets you
/// do not own such as `AppBar`, `ListTile` and `DataTable`. Wrap your page and
/// it works.
///
/// Two things automatic discovery cannot see, both by construction:
///
/// * Rows of a lazy list that have never been built, because they do not
///   exist. Use `FindableListView` for those; it and discovery compose.
/// * Text that is not on screen at all, such as a collapsed `ExpansionTile`'s
///   children or an unselected tab.
///
/// Wrapping text in `FindableText` is still supported and still useful: it
/// highlights inline by restyling the text itself, while discovered text is
/// highlighted by an overlay drawn on top. Set [autoDiscover] to false to go
/// back to registered sources only.
///
/// The shortcut is registered globally while the scope is mounted, so it
/// works no matter where keyboard focus is; it never takes or moves focus
/// itself. The bar is rendered into the nearest [Overlay] (every
/// `MaterialApp`, `CupertinoApp`, or `WidgetsApp` provides one), so it is
/// visible and tappable no matter how [child] is laid out.
///
/// For a custom find UI, pass [showBar]: false and either handle
/// [onOpenRequested] or drive the controller directly.
///
/// ## Web
///
/// While this scope is mounted and would actually open a bar (or call
/// [onOpenRequested]), the find shortcut is reported as handled. On
/// Flutter web the engine turns that into `keydown.preventDefault()`, and
/// a capture listener on `window` does the same if the event never reaches
/// Dart. Chrome and Firefox usually honour that and open this bar instead
/// of theirs. Safari did in a 2020 survey; that has not been re-checked
/// here.
///
/// That is a keyboard intercept, not a substitute for the browser's find
/// engine. It does not put text into the DOM, does not help a crawler or
/// reader mode, and does not intercept Find chosen from a browser menu or
/// from mobile-browser chrome. F3 and Ctrl/Cmd+G are also left alone.
///
/// If a browser refuses to let the page have the key — some Safari
/// versions, or Firefox with "Override Keyboard Shortcuts" set to Block —
/// the user gets the browser's find bar over a canvas that has nothing
/// findable in it. This scope still opens its own bar when the key
/// reaches Dart, so both can appear together. When the key never reaches
/// the page, only the native bar opens. There is no API that can force
/// the intercept to win.
final class FindInPageScope extends StatefulWidget {
  /// Creates a scope that makes descendant `FindableText` widgets
  /// searchable.
  const FindInPageScope({
    required this.child,
    this.controller,
    this.showBar = true,
    this.onOpenRequested,
    this.barAlignment = AlignmentDirectional.topEnd,
    this.autoDiscover = true,
    this.highlightColor,
    this.activeHighlightColor,
    super.key,
  });

  /// The subtree whose `FindableText` descendants become searchable.
  final Widget child;

  /// Explicit controller. When null the scope creates and owns one.
  final FindInPageController? controller;

  /// Whether the scope shows its own [FindBar] when the find shortcut is
  /// pressed. Set to false when building a custom find UI.
  ///
  /// When this is false and [onOpenRequested] is also null, the shortcut
  /// is not handled, so on web the browser is left to run its own find.
  final bool showBar;

  /// Called when the find shortcut is pressed while [showBar] is false.
  /// When this is null too, the shortcut is ignored and, on web, not
  /// intercepted.
  final VoidCallback? onOpenRequested;

  /// Where the built-in bar is placed. Directional, so `topEnd` follows
  /// the ambient text direction.
  final AlignmentGeometry barAlignment;

  /// Whether text that was never wrapped is searched too. Defaults to true.
  ///
  /// Turn it off to search only sources that registered themselves, which is
  /// what versions before 2.0.0 did.
  final bool autoDiscover;

  /// Fill painted behind non-active matches found by discovery.
  ///
  /// Defaults to translucent yellow, which is what Chrome and Firefox use, so
  /// the highlight reads as find-in-page rather than as selection. Matches
  /// inside a `FindableText` are styled by that widget instead and ignore this.
  final Color? highlightColor;

  /// Fill painted behind the active match found by discovery.
  ///
  /// Defaults to translucent orange, again matching the browsers.
  final Color? activeHighlightColor;

  /// The controller of the nearest enclosing scope, or null.
  static FindInPageController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_FindInPageInherited>()
      ?.controller;

  /// The controller of the nearest enclosing scope.
  static FindInPageController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null,
        'FindInPageScope.of() called with no FindInPageScope ancestor');
    return controller!;
  }

  @override
  State<FindInPageScope> createState() => _FindInPageScopeState();
}

class _FindInPageScopeState extends State<FindInPageScope> {
  FindInPageController? _ownedController;
  final OverlayPortalController _portal = OverlayPortalController();
  final GlobalKey _subtreeKey = GlobalKey();
  List<RenderedTextSource> _lastSweep = const [];
  bool _barVisible = false;

  FindInPageController get _controller =>
      widget.controller ?? (_ownedController ??= FindInPageController());

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    installWebFindIntercept(_shouldInterceptBrowserFind);
    _installDiscovery();
  }

  @override
  void didUpdateWidget(FindInPageScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.autoDiscover != widget.autoDiscover) {
      oldWidget.controller?.setDiscovery(null);
      _installDiscovery();
    }
  }

  void _installDiscovery() {
    _controller.setDiscovery(widget.autoDiscover ? _sweep : null);
  }

  /// Reads the text currently rendered inside [FindInPageScope.child].
  ///
  /// Runs after layout, from the controller's recompute, so it reports what is
  /// actually on screen. Starts at the searched subtree rather than at this
  /// state's own element, which keeps the find bar's own query text out of the
  /// results.
  List<FindableSource> _sweep() {
    final root = _subtreeKey.currentContext?.findRenderObject();
    if (root == null) return const [];
    _lastSweep = discoverTextSources(root, previous: _lastSweep);
    return _lastSweep;
  }

  @override
  void dispose() {
    uninstallWebFindIntercept(_shouldInterceptBrowserFind);
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    widget.controller?.setDiscovery(null);
    _ownedController?.dispose();
    super.dispose();
  }

  /// Whether this scope would actually take the find shortcut.
  ///
  /// Read from the web capture listener on each keydown. When false, the
  /// listener must not `preventDefault`, or a scope that has disabled its
  /// bar would still steal the key from the browser.
  bool _shouldInterceptBrowserFind() {
    if (!mounted) return false;
    return widget.showBar || widget.onOpenRequested != null;
  }

  bool _findModifierPressed() {
    final control = HardwareKeyboard.instance.isControlPressed;
    final meta = HardwareKeyboard.instance.isMetaPressed;
    if (kIsWeb) return control || meta;
    final apple = defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return apple ? meta : control;
  }

  bool _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey == LogicalKeyboardKey.keyF && _findModifierPressed()) {
      if (!widget.showBar && widget.onOpenRequested == null) return false;
      _openRequested();
      return true;
    }
    // Only consume Escape while the built-in bar is open, so dialogs and
    // other Escape handlers keep working otherwise.
    if (event.logicalKey == LogicalKeyboardKey.escape && _barVisible) {
      _close();
      return true;
    }
    return false;
  }

  void _openRequested() {
    if (!widget.showBar) {
      widget.onOpenRequested?.call();
      return;
    }
    if (!_barVisible) {
      setState(() => _barVisible = true);
      _portal.show();
    }
  }

  void _close() {
    _controller.clearSearch();
    if (_barVisible) {
      setState(() => _barVisible = false);
      _portal.hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _FindInPageInherited(
      controller: _controller,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => SafeArea(
          child: Align(
            alignment: widget.barAlignment,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: FindBar(controller: _controller, onClose: _close),
            ),
          ),
        ),
        child: HighlightOverlay(
          controller: _controller,
          color: widget.highlightColor ?? _matchFill,
          activeColor: widget.activeHighlightColor ?? _activeMatchFill,
          child: KeyedSubtree(key: _subtreeKey, child: widget.child),
        ),
      ),
    );
  }
}

class _FindInPageInherited extends InheritedWidget {
  const _FindInPageInherited({required this.controller, required super.child});

  final FindInPageController controller;

  @override
  bool updateShouldNotify(_FindInPageInherited oldWidget) =>
      controller != oldWidget.controller;
}
