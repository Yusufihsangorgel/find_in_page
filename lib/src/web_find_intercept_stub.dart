/// Registers a client of the web find-shortcut intercept.
///
/// On this platform there is no browser find bar to cancel, so this is a
/// no-op. The [shouldIntercept] callback is never invoked.
void installWebFindIntercept(bool Function() shouldIntercept) {}

/// Drops a client previously passed to [installWebFindIntercept].
///
/// A no-op on this platform, including when [shouldIntercept] was never
/// installed.
void uninstallWebFindIntercept(bool Function() shouldIntercept) {}

/// Whether a capture `keydown` listener is currently attached to `window`.
///
/// Always false here: this isolate is not running in a browser.
bool get webFindInterceptIsAttached => false;
