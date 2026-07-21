/// Ctrl+F for Flutter: highlight matches across your widgets, navigate
/// between them, and scroll the active match into view.
///
/// Wrap a page in [FindInPageScope], replace searchable `Text` widgets
/// with [FindableText], and press Ctrl+F (Cmd+F on macOS).
library;

export 'src/controller.dart'
    show FindInPageController, FindMatch, FindableSource;
export 'src/find_bar.dart' show FindBar;
export 'src/findable_list_view.dart'
    show FindableListView, FindableListItemBuilder;
export 'src/findable_record.dart' show FindableRecord;
export 'src/findable_text.dart' show FindableText;
export 'src/scope.dart' show FindInPageScope;
