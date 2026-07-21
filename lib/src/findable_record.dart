import 'controller.dart';

/// A [FindableSource] whose text is supplied directly instead of read from
/// a live widget, and which has no [findableContext].
///
/// Use this to register text that lives in your data model before the
/// widget that would show it has ever been built, such as an item far
/// outside the viewport of a lazy list. Register it with
/// [FindInPageController.register]'s `reveal` parameter to bring it into
/// view yourself, since there is no [findableContext] for
/// `Scrollable.ensureVisible` to use.
///
/// [FindableListView] builds one of these per item so a whole backing list
/// is searchable even when most items are not built.
final class FindableRecord implements FindableSource {
  /// Creates a data-driven source with the given text.
  FindableRecord(this.findableText);

  @override
  String findableText;

  @override
  Null get findableContext => null;
}
