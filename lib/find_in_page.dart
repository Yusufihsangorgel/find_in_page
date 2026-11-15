/// Ctrl+F for Flutter: highlight matches across your widgets, navigate
/// between them, and scroll the active match into view.
///
/// Wrap a page in [FindInPageScope], replace searchable `Text` widgets
/// with [FindableText], and press Ctrl+F (Cmd+F on macOS). On web that
/// shortcut is intercepted when the browser allows it; see
/// [FindInPageScope] for what happens when it does not.
///
/// The library imports only the widgets layer. Its [FindBar] works in a
/// `MaterialApp`, a `CupertinoApp` or a plain `WidgetsApp`, and takes its
/// look from [FindBarStyle] and [FindBarTheme].
library;

export 'src/controller.dart'
    show FindInPageController, FindMatch, FindableSource;
export 'src/auto_discovery.dart'
    show ParagraphSource, ReadOnlyEditableSource, RenderedTextSource;
export 'src/exclude_from_find.dart' show ExcludeFromFind;
export 'src/find_bar.dart' show FindBar;
export 'src/find_bar_style.dart' show FindBarStyle, FindBarTheme;
export 'src/find_session.dart' show FindBarBuilder, FindSession;
export 'src/findable_list_view.dart'
    show FindableListView, FindableListItemBuilder;
export 'src/findable_record.dart' show FindableRecord;
export 'src/findable_text.dart' show FindableText;
export 'src/scope.dart' show FindInPageScope;
