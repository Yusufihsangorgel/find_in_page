/// Web-only capture listener that `preventDefault`s Ctrl/Cmd+F.
///
/// The Dart `HardwareKeyboard` handler in `scope.dart` already returns
/// handled for that chord, and Flutter's web engine already maps handled
/// onto `keydown.preventDefault()`. This extra listener exists for the
/// two cases that path does not cover: a key the semantics gate never
/// delivers to Dart, and the modifier the current `defaultTargetPlatform`
/// would not have treated as find (Ctrl on a Mac, Meta elsewhere).
///
/// Off web this is a no-op.
library;

export 'web_find_intercept_stub.dart'
    if (dart.library.js_interop) 'web_find_intercept_web.dart';
