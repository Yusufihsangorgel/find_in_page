/// Ctrl+F for Flutter: highlight matches across your widgets, navigate
/// between them, and scroll the active match into view.
///
/// Wrap a page in [FindInPageScope] and press Ctrl+F (Cmd+F on macOS): the
/// scope finds the text Flutter draws on its own and highlights matches with
/// an overlay. [FindableText] is optional; it highlights inline by restyling
/// the text itself. On web that shortcut is intercepted when the browser
/// allows it; see [FindInPageScope] for what happens when it does not.
library;

export 'src/controller.dart'
    show FindInPageController, FindMatch, FindableSource;
export 'src/auto_discovery.dart'
    show ParagraphSource, ReadOnlyEditableSource, RenderedTextSource;
export 'src/exclude_from_find.dart' show ExcludeFromFind;
export 'src/find_bar.dart' show FindBar;
export 'src/findable_list_view.dart'
    show FindableListView, FindableListItemBuilder;
export 'src/findable_record.dart' show FindableRecord;
export 'src/findable_text.dart' show FindableText;
export 'src/scope.dart' show FindInPageScope;
