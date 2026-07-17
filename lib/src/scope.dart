import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'find_bar.dart';

/// Wires find-in-page into a subtree: provides a [FindInPageController]
/// to descendant `FindableText` widgets, opens a [FindBar] on the
/// platform find shortcut (Cmd+F on macOS and iOS, Ctrl+F elsewhere),
/// and closes it on Escape.
///
/// The shortcut is registered globally while the scope is mounted, so it
/// works no matter where keyboard focus is; it never takes or moves focus
/// itself. The bar is rendered into the nearest [Overlay] (every
/// `MaterialApp`, `CupertinoApp`, or `WidgetsApp` provides one), so it is
/// visible and tappable no matter how [child] is laid out.
///
/// For a custom find UI, pass [showBar]: false and either handle
/// [onOpenRequested] or drive the controller directly.
class FindInPageScope extends StatefulWidget {
  /// Creates a scope that makes descendant `FindableText` widgets
  /// searchable.
  const FindInPageScope({
    required this.child,
    this.controller,
    this.showBar = true,
    this.onOpenRequested,
    this.barAlignment = AlignmentDirectional.topEnd,
    super.key,
  });

  /// The subtree whose `FindableText` descendants become searchable.
  final Widget child;

  /// Explicit controller. When null the scope creates and owns one.
  final FindInPageController? controller;

  /// Whether the scope shows its own [FindBar] when the find shortcut is
  /// pressed. Set to false when building a custom find UI.
  final bool showBar;

  /// Called when the find shortcut is pressed while [showBar] is false.
  /// When this is null too, the shortcut is ignored.
  final VoidCallback? onOpenRequested;

  /// Where the built-in bar is placed. Directional, so `topEnd` follows
  /// the ambient text direction.
  final AlignmentGeometry barAlignment;

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
  bool _barVisible = false;

  FindInPageController get _controller =>
      widget.controller ?? (_ownedController ??= FindInPageController());

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _ownedController?.dispose();
    super.dispose();
  }

  bool _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final apple = defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final modifierPressed = apple
        ? HardwareKeyboard.instance.isMetaPressed
        : HardwareKeyboard.instance.isControlPressed;
    if (event.logicalKey == LogicalKeyboardKey.keyF && modifierPressed) {
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
        child: widget.child,
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
