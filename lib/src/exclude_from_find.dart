import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Keeps everything under [child] out of find-in-page.
///
/// A `FindInPageScope` searches the text rendered inside it, including text in
/// widgets you did not write. That is usually what you want, and sometimes it
/// is not: a navigation rail, a footer, a debug banner or a legend adds matches
/// that are technically on the page but not what the reader is looking for.
/// Wrap those and they stop being searchable.
///
/// ```dart
/// FindInPageScope(
///   child: Column(
///     children: [
///       ExcludeFromFind(child: NavigationBar(destinations: destinations)),
///       Expanded(child: Article(text: body)),
///     ],
///   ),
/// )
/// ```
///
/// It is also how a widget claims its own text. `FindableText` and
/// `FindableListView` both report their content to the controller themselves
/// and are wrapped in this, so their matches are counted once rather than twice.
/// Do the same in a custom searchable widget.
///
/// This has no effect on `Semantics`; screen readers still see the text.
final class ExcludeFromFind extends SingleChildRenderObjectWidget {
  /// Hides [child]'s text from automatic discovery.
  const ExcludeFromFind({required super.child, super.key});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderExcludeFromFind();
}

/// The marker [ExcludeFromFind] inserts. Discovery stops when it reaches one.
class RenderExcludeFromFind extends RenderProxyBox {}
