import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'find_bar_parts.dart';
import 'find_bar_style.dart';
import 'find_session.dart';

/// A compact find bar with a query field, two matching toggles, a match
/// counter, and previous, next and close buttons.
///
/// The bar is built on the widgets layer alone. It reads no Material or
/// Cupertino theme and needs no localizations, which lets it run under a
/// `MaterialApp`, a `CupertinoApp` or a plain `WidgetsApp`. Its look comes
/// from [style], then the nearest [FindBarTheme], then neutral defaults for
/// the platform brightness.
///
/// Enter moves to the next match and Shift+Enter to the previous one, while
/// the query field has focus. Escape anywhere in the bar calls [onClose].
/// Tab moves through the field, the toggles, previous, next and close, in
/// that order and in either text direction.
///
/// The query follows the field on every edit, including text an input
/// method is still composing. Committing a composition that leaves the text
/// unchanged does not run the search again. While a composition is active,
/// Enter goes to the input method and does not move between matches.
///
/// `FindInPageScope` shows this bar out of the box. Embed it yourself for
/// custom placement, or build it from `FindInPageScope.barBuilder`.
final class FindBar extends StatefulWidget {
  /// Creates a find bar driving [controller].
  const FindBar({
    required this.controller,
    this.onClose,
    this.autofocus = true,
    this.hintText = 'Find in page',
    this.previousTooltip = 'Previous match',
    this.nextTooltip = 'Next match',
    this.closeTooltip = 'Close',
    this.matchCaseTooltip = 'Match case',
    this.matchAccentsTooltip = 'Match accents',
    this.showMatchCase = true,
    this.showMatchAccents = true,
    this.matchStatusLabel = _defaultMatchStatusLabel,
    this.style,
    this.contextMenuBuilder,
    super.key,
  });

  /// The session this bar reads and drives, usually a
  /// `FindInPageController`.
  final FindSession controller;

  /// Called when the close button or Escape is pressed. When null, the close
  /// button is disabled and Escape is left to widgets above the bar.
  final VoidCallback? onClose;

  /// Whether the query field grabs focus when the bar appears.
  ///
  /// Unlike an `autofocus` flag on a text field, which only takes focus
  /// when nothing in the enclosing `FocusScope` already has it, this moves
  /// focus into the field regardless of what was focused before. A page
  /// with a focused list or a focused text field still lands keyboard input
  /// in the query field. When this bar is later removed from the tree (the
  /// built-in bar on close, or any other widget that stops building it)
  /// while its field still has focus, Flutter returns focus to whatever held
  /// it before. That is what happens for any focused widget that disappears.
  /// If the user moved focus elsewhere first, it is left there. Pass false
  /// to leave focus alone in both directions.
  final bool autofocus;

  /// Placeholder text for the query field, and its accessible name.
  final String hintText;

  /// Tooltip and accessible name of the previous-match button.
  final String previousTooltip;

  /// Tooltip and accessible name of the next-match button.
  final String nextTooltip;

  /// Tooltip and accessible name of the close button.
  final String closeTooltip;

  /// Tooltip and accessible name of the toggle bound to
  /// [FindSession.caseSensitive].
  final String matchCaseTooltip;

  /// Tooltip and accessible name of the toggle bound to
  /// [FindSession.diacriticSensitive].
  final String matchAccentsTooltip;

  /// Whether the match case toggle is offered.
  ///
  /// Even when true, both toggles are left out while the bar is too narrow
  /// to fit them beside a field of [FindBarStyle.minFieldWidth].
  final bool showMatchCase;

  /// Whether the match accents toggle is offered.
  ///
  /// Even when true, both toggles are left out while the bar is too narrow
  /// to fit them beside a field of [FindBarStyle.minFieldWidth].
  final bool showMatchAccents;

  /// Builds what a screen reader announces when the match count changes,
  /// from the active match index (zero-based, `-1` when there is none) and
  /// the total.
  ///
  /// The counter beside the field is the whole feedback loop of a find bar.
  /// A sighted user watches it move while typing. It is announced as a live
  /// region to reach a screen reader too, since focus stays in the query
  /// field and never lands on the counter itself. The visible `3/12` is left
  /// out of the announcement because it reads badly aloud.
  ///
  /// Defaults to English, as the tooltips do. Pass a localized builder.
  ///
  /// ```dart
  /// matchStatusLabel: (active, count) => count == 0
  ///     ? l10n.noMatches
  ///     : l10n.matchOf(active + 1, count),
  /// ```
  final String Function(int activeIndex, int matchCount) matchStatusLabel;

  /// Colors, text styles and geometry, laid over the nearest [FindBarTheme].
  final FindBarStyle? style;

  /// Builds the query field's context menu.
  ///
  /// By default iOS shows its system menu where the platform supports it.
  /// Everywhere else the bar draws a plain menu of the field's actions in
  /// its own style. Pass a builder to show your design system's menu.
  final EditableTextContextMenuBuilder? contextMenuBuilder;

  static String _defaultMatchStatusLabel(int activeIndex, int matchCount) =>
      matchCount == 0
      ? 'No matches'
      : 'Match ${activeIndex + 1} of $matchCount';

  @override
  State<FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<FindBar>
    implements TextSelectionGestureDetectorBuilderDelegate {
  late final TextEditingController _text = TextEditingController(
    text: widget.controller.query,
  );
  final FocusNode _focusNode = FocusNode(debugLabel: 'FindBar query');
  final GlobalKey<EditableTextState> _editableKey =
      GlobalKey<EditableTextState>();
  late final TextSelectionGestureDetectorBuilder _gestures =
      TextSelectionGestureDetectorBuilder(delegate: this);
  bool _showSelectionHandles = false;
  FindFieldSelectionControls? _handles;
  FindBarStyle? _resolvedStyle;

  @override
  GlobalKey<EditableTextState> get editableTextKey => _editableKey;

  @override
  bool get forcePressEnabled => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  bool get selectionEnabled => true;

  FindSession get _session => widget.controller;

  @override
  void initState() {
    super.initState();
    _session.addListener(_syncFromController);
    if (widget.autofocus) {
      // An autofocus flag on the field only takes focus when the enclosing
      // FocusScope has none. Requesting it directly here always wins, which
      // is the point of the autofocus dartdoc. Restoring focus when the bar leaves
      // needs no code of ours. Disposing a FocusNode that still has primary
      // focus already asks Flutter to refocus whatever was focused before
      // it, through FocusNode.unfocus and its default
      // UnfocusDisposition.previouslyFocusedChild.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(FindBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncFromController);
      widget.controller.addListener(_syncFromController);
      _syncFromController();
    }
  }

  @override
  void dispose() {
    _session.removeListener(_syncFromController);
    // See the initState comment. If _focusNode still has primary focus here,
    // Flutter itself moves focus back to whatever held it before as part of
    // disposing a focused node.
    _text.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Reflects programmatic `search` and `close` calls in the field, without
  /// fighting the user while they are typing.
  void _syncFromController() {
    if (!_focusNode.hasFocus && _text.text != _session.query) {
      _text.text = _session.query;
    }
  }

  void _onChanged(String text) {
    // The field can already hold the query, for example after a programmatic
    // search for the same text. Searching again would restart at the first
    // match.
    if (text != _session.query) _session.search(text);
  }

  bool get _isComposing {
    final composing = _text.value.composing;
    return composing.isValid && !composing.isCollapsed;
  }

  // Enter in the field and the search action. Focus stays in the field to
  // type or step again. The buttons call the session directly, which leaves
  // focus on a button the keyboard reached.
  void _next() {
    _session.next();
    _focusNode.requestFocus();
  }

  void _previous() {
    _session.previous();
    _focusNode.requestFocus();
  }

  bool _shouldShowSelectionHandles(SelectionChangedCause? cause) {
    if (!_gestures.shouldShowSelectionToolbar) return false;
    if (cause == SelectionChangedCause.keyboard) return false;
    if (cause == SelectionChangedCause.longPress) return true;
    return _text.text.isNotEmpty;
  }

  void _handleSelectionChanged(
    TextSelection selection,
    SelectionChangedCause? cause,
  ) {
    final show = _shouldShowSelectionHandles(cause);
    if (show != _showSelectionHandles) {
      setState(() => _showSelectionHandles = show);
    }
  }

  void _handleSelectionHandleTapped() {
    if (_text.selection.isCollapsed) {
      _editableKey.currentState?.toggleToolbar();
    }
  }

  Widget _buildContextMenu(BuildContext context, EditableTextState state) {
    final custom = widget.contextMenuBuilder;
    if (custom != null) return custom(context, state);
    if (SystemContextMenu.isSupportedByField(state)) {
      return SystemContextMenu.editableText(editableTextState: state);
    }
    return FindFieldContextMenu(
      anchors: state.contextMenuAnchors,
      buttonItems: state.contextMenuButtonItems,
      style: _resolvedStyle ?? FindBarTheme.resolve(context),
    );
  }

  /// The width the bar's contents need with [toggles] toggles showing.
  ///
  /// The buttons are exactly [FindBarStyle.buttonSize] wide, and the counter
  /// is measured with the same style and text scale it is painted with.
  double _widthWithToggles(
    FindBarStyle style,
    String? counter,
    TextScaler textScaler,
    TextDirection textDirection,
    int toggles,
  ) {
    var counterWidth = 0.0;
    if (counter != null) {
      final painter = TextPainter(
        text: TextSpan(text: counter, style: style.counterStyle),
        textScaler: textScaler,
        textDirection: textDirection,
        maxLines: 1,
      )..layout();
      counterWidth = painter.width + _counterPadding.horizontal;
      painter.dispose();
    }
    return style.minFieldWidth! +
        _fieldGap +
        counterWidth +
        (toggles + 3) * style.buttonSize!;
  }

  static const double _fieldGap = 4;
  static const EdgeInsets _counterPadding = EdgeInsets.symmetric(horizontal: 6);

  @override
  Widget build(BuildContext context) {
    final style = _resolvedStyle = FindBarTheme.resolve(context, widget.style);
    final hasOverlay = Overlay.maybeOf(context, rootOverlay: true) != null;
    final accent = style.accentColor!;
    if (_handles?.color != accent) {
      _handles = FindFieldSelectionControls(accent);
    }

    return Actions(
      actions: <Type, Action<Intent>>{
        _CloseFindIntent: _BarAction<_CloseFindIntent>(
          isEnabled: () => widget.onClose != null,
          onInvoke: () => widget.onClose?.call(),
        ),
      },
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.escape): _CloseFindIntent(),
        },
        // Taps on the buttons count as taps on the field. The field keeps
        // focus, and with it the on-screen keyboard, while the user steps
        // through matches.
        child: TextFieldTapRegion(
          // Tab order is fixed by FocusTraversalOrder below. Toggles that
          // appear after the first build would otherwise be visited last.
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: style.backgroundColor,
                borderRadius: style.borderRadius,
                border: style.border,
                boxShadow: style.shadows,
              ),
              child: Padding(
                padding: style.padding!,
                child: ListenableBuilder(
                  listenable: _session,
                  builder: (context, _) =>
                      _buildRow(context, style, hasOverlay),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, FindBarStyle style, bool hasOverlay) {
    final session = _session;
    final textScaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final textDirection = Directionality.of(context);
    final count = session.matchCount;
    final active = session.activeMatchIndex;
    final counter = session.query.isEmpty
        ? null
        : (count == 0 || active == null ? '0/0' : '${active + 1}/$count');
    final toggles =
        (widget.showMatchCase ? 1 : 0) + (widget.showMatchAccents ? 1 : 0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final showToggles =
            toggles > 0 &&
            constraints.maxWidth >=
                _widthWithToggles(
                  style,
                  counter,
                  textScaler,
                  textDirection,
                  toggles,
                );
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              key: const ValueKey('field'),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: style.minFieldWidth!,
                  maxWidth: style.maxFieldWidth!,
                ),
                child: FocusTraversalOrder(
                  order: const NumericFocusOrder(0),
                  child: _buildField(style, hasOverlay),
                ),
              ),
            ),
            const SizedBox(width: _fieldGap),
            if (showToggles && widget.showMatchCase)
              _ordered(
                1,
                key: const ValueKey('matchCase'),
                glyph: FindBarGlyph.matchCase,
                label: widget.matchCaseTooltip,
                toggled: session.caseSensitive,
                style: style,
                onPressed: () => session.search(
                  session.query,
                  caseSensitive: !session.caseSensitive,
                ),
              ),
            if (showToggles && widget.showMatchAccents)
              _ordered(
                2,
                key: const ValueKey('matchAccents'),
                glyph: FindBarGlyph.matchAccents,
                label: widget.matchAccentsTooltip,
                toggled: session.diacriticSensitive,
                style: style,
                onPressed: () => session.search(
                  session.query,
                  diacriticSensitive: !session.diacriticSensitive,
                ),
              ),
            if (counter != null)
              Padding(
                key: const ValueKey('counter'),
                padding: _counterPadding,
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  label: widget.matchStatusLabel(active ?? -1, count),
                  child: ExcludeSemantics(
                    child: Text(
                      counter,
                      style: style.counterStyle,
                      maxLines: 1,
                    ),
                  ),
                ),
              ),
            _ordered(
              3,
              key: const ValueKey('previous'),
              glyph: FindBarGlyph.previous,
              label: widget.previousTooltip,
              style: style,
              onPressed: session.previous,
            ),
            _ordered(
              4,
              key: const ValueKey('next'),
              glyph: FindBarGlyph.next,
              label: widget.nextTooltip,
              style: style,
              onPressed: session.next,
            ),
            _ordered(
              5,
              key: const ValueKey('close'),
              glyph: FindBarGlyph.close,
              label: widget.closeTooltip,
              style: style,
              onPressed: widget.onClose,
            ),
          ],
        );
      },
    );
  }

  /// A bar button at a fixed place in the tab order.
  static Widget _ordered(
    double order, {
    required Key key,
    required FindBarGlyph glyph,
    required String label,
    required FindBarStyle style,
    required VoidCallback? onPressed,
    bool? toggled,
  }) {
    return FocusTraversalOrder(
      key: key,
      order: NumericFocusOrder(order),
      child: FindBarIconButton(
        glyph: glyph,
        label: label,
        style: style,
        toggled: toggled,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildField(FindBarStyle style, bool hasOverlay) {
    final base = style.textStyle!;
    final textStyle = base.copyWith(color: base.color ?? style.foregroundColor);
    final accent = style.accentColor!;
    final cupertinoCursor = switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => true,
      _ => false,
    };

    final editable = Actions(
      actions: <Type, Action<Intent>>{
        _NextMatchIntent: _BarAction<_NextMatchIntent>(
          isEnabled: () => !_isComposing,
          onInvoke: _next,
        ),
        _PreviousMatchIntent: _BarAction<_PreviousMatchIntent>(
          isEnabled: () => !_isComposing,
          onInvoke: _previous,
        ),
      },
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): _NextMatchIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): _NextMatchIntent(),
          SingleActivator(LogicalKeyboardKey.enter, shift: true):
              _PreviousMatchIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter, shift: true):
              _PreviousMatchIntent(),
        },
        child: EditableText(
          key: _editableKey,
          controller: _text,
          focusNode: _focusNode,
          style: textStyle,
          cursorColor: accent,
          backgroundCursorColor: style.hintColor!,
          selectionColor: accent.withValues(alpha: 0.32),
          cursorWidth: 2,
          cursorRadius: cupertinoCursor ? const Radius.circular(2) : null,
          cursorOpacityAnimates: cupertinoCursor,
          paintCursorAboveText: cupertinoCursor,
          maxLines: 1,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.search,
          keyboardAppearance:
              MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light,
          // A find query is matched literally. Autocorrect would rewrite
          // what was typed, and smart punctuation would turn an apostrophe
          // into a curly quote that the page does not contain.
          autocorrect: false,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          rendererIgnoresPointer: true,
          showSelectionHandles: _showSelectionHandles,
          selectionControls: hasOverlay ? _handles : null,
          contextMenuBuilder: hasOverlay ? _buildContextMenu : null,
          onChanged: _onChanged,
          // Keeps focus in the field. Without a callback here the field
          // gives up focus on the search action.
          onEditingComplete: _text.clearComposing,
          onSubmitted: (_) => _next(),
          onSelectionChanged: _handleSelectionChanged,
          onSelectionHandleTapped: _handleSelectionHandleTapped,
        ),
      ),
    );

    final field = Stack(
      alignment: AlignmentDirectional.centerStart,
      children: [
        IgnorePointer(
          child: ExcludeSemantics(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _text,
              builder: (context, value, _) => value.text.isEmpty
                  ? Text(
                      widget.hintText,
                      style: textStyle.copyWith(color: style.hintColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
        editable,
      ],
    );

    return Semantics(
      container: true,
      label: widget.hintText,
      onTap: () => _editableKey.currentState?.requestKeyboard(),
      child: _gestures.buildGestureDetector(
        behavior: HitTestBehavior.translucent,
        child: field,
      ),
    );
  }
}

class _NextMatchIntent extends Intent {
  const _NextMatchIntent();
}

class _PreviousMatchIntent extends Intent {
  const _PreviousMatchIntent();
}

class _CloseFindIntent extends Intent {
  const _CloseFindIntent();
}

/// An action that can switch itself off. A disabled one leaves the key
/// event to the widgets above, and to the input method after them.
class _BarAction<T extends Intent> extends Action<T> {
  _BarAction({required bool Function() isEnabled, required this.onInvoke})
    : _isEnabled = isEnabled;

  final bool Function() _isEnabled;
  final VoidCallback onInvoke;

  @override
  bool isEnabled(T intent) => _isEnabled();

  @override
  Object? invoke(T intent) {
    onInvoke();
    return null;
  }
}
