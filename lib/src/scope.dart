import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'find_bar.dart';

/// Wires find-in-page into a subtree: provides a [FindInPageController]
/// to descendant `FindableText` widgets, opens a [FindBar] overlay on
/// Ctrl+F (Cmd+F on macOS), and closes it on Escape.
///
/// For custom bar placement or styling, build your own bar with
/// [FindBar] or drive the controller directly and pass [showBar]: false.
class FindInPageScope extends StatefulWidget {
  const FindInPageScope({
    required this.child,
    this.controller,
    this.showBar = true,
    this.barAlignment = Alignment.topRight,
    super.key,
  });

  final Widget child;

  /// Explicit controller. When null the scope creates and owns one.
  final FindInPageController? controller;

  /// Whether the scope overlays its own [FindBar] when a search is opened.
  final bool showBar;

  /// Where the built-in bar is placed inside the scope.
  final Alignment barAlignment;

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
  bool _barVisible = false;

  FindInPageController get _controller =>
      widget.controller ?? (_ownedController ??= FindInPageController());

  void _open() => setState(() => _barVisible = true);

  void _close() {
    _controller.clearSearch();
    setState(() => _barVisible = false);
  }

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _FindInPageInherited(
      controller: _controller,
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _OpenFindBarIntent(),
          SingleActivator(LogicalKeyboardKey.keyF, meta: true):
              _OpenFindBarIntent(),
          SingleActivator(LogicalKeyboardKey.escape): _CloseFindBarIntent(),
        },
        child: Actions(
          actions: {
            _OpenFindBarIntent: CallbackAction<_OpenFindBarIntent>(
              onInvoke: (_) {
                _open();
                return null;
              },
            ),
            _CloseFindBarIntent: _CloseFindBarAction(this),
          },
          child: Focus(
            autofocus: true,
            child: Stack(
              children: [
                widget.child,
                if (widget.showBar && _barVisible)
                  Positioned.fill(
                    child: Align(
                      alignment: widget.barAlignment,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: FindBar(
                          controller: _controller,
                          onClose: _close,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
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

class _OpenFindBarIntent extends Intent {
  const _OpenFindBarIntent();
}

class _CloseFindBarIntent extends Intent {
  const _CloseFindBarIntent();
}

/// Only consumes Escape while the bar is open, so dialogs and other
/// Escape handlers keep working otherwise.
class _CloseFindBarAction extends Action<_CloseFindBarIntent> {
  _CloseFindBarAction(this._state);

  final _FindInPageScopeState _state;

  @override
  bool isEnabled(_CloseFindBarIntent intent) => _state._barVisible;

  @override
  Object? invoke(_CloseFindBarIntent intent) {
    _state._close();
    return null;
  }
}
