import 'dart:js_interop';

/// Registers a client of the web find-shortcut intercept.
///
/// The first client attaches a capture-phase `keydown` listener on
/// `window` that `preventDefault`s Ctrl/Cmd+F while any registered client
/// wants the shortcut. It does not open the in-app bar; the Dart
/// `HardwareKeyboard` handler still does that.
///
/// [shouldIntercept] is read on each matching keydown so a scope with
/// `showBar: false` and no `onOpenRequested` does not steal the key.
void installWebFindIntercept(bool Function() shouldIntercept) {
  _clients.add(shouldIntercept);
  if (_listener != null) return;
  _listener = ((JSObject raw) {
    _onKeyDown(raw as KeyboardEvent);
  }).toJS;
  window.addEventListener('keydown', _listener!, true.toJS);
}

/// Drops a client previously passed to [installWebFindIntercept].
///
/// The capture listener is removed when the last client leaves.
void uninstallWebFindIntercept(bool Function() shouldIntercept) {
  _clients.remove(shouldIntercept);
  if (_clients.isNotEmpty) return;
  final listener = _listener;
  if (listener == null) return;
  window.removeEventListener('keydown', listener, true.toJS);
  _listener = null;
}

/// Whether a capture `keydown` listener is currently attached to `window`.
bool get webFindInterceptIsAttached => _listener != null;

final List<bool Function()> _clients = <bool Function()>[];
JSFunction? _listener;

@JS()
external Window get window;

extension type Window._(JSObject _) implements JSObject {
  external void addEventListener(
    String type,
    JSFunction callback, [
    JSAny options,
  ]);
  external void removeEventListener(
    String type,
    JSFunction callback, [
    JSAny options,
  ]);
}

extension type KeyboardEvent._(JSObject _) implements JSObject {
  external String? get key;
  external String? get code;
  external bool get ctrlKey;
  external bool get metaKey;
  external void preventDefault();
}

void _onKeyDown(KeyboardEvent event) {
  final key = event.key;
  final code = event.code;
  final isF = key == 'f' || key == 'F' || code == 'KeyF';
  if (!isF) return;
  if (!event.ctrlKey && !event.metaKey) return;
  if (!_clients.any((shouldIntercept) => shouldIntercept())) return;
  event.preventDefault();
}
