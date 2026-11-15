import 'dart:math' as math;

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
/// Text an input method is still composing is searched as it changes, and a
/// commit that leaves the text unchanged does not search again. While a
/// composition is active, Enter and Shift+Enter go to the input method and
/// do not move between matches.
///
/// On Android, Fuchsia and iOS the buttons and the query field take taps
/// across the touch target size of the platform, and the bar is one row of
/// that height. When the toggles do not fit beside the field there, a
/// search options button takes their place. Activating it shows the toggles
/// in a second row, and activating it again, or Escape on a toggle, hides
/// them. Tab then goes from the field to the options button, previous, next
/// and close, and on to the toggles. The width set aside for the counter
/// fits three digits on each side of the slash, which keeps the row steady
/// when the counter first appears.
///
/// A bar too narrow for the field, the counter and the previous, next and
/// close buttons in one row grows a second row, one hit height tall, and
/// moves previous, next and close into it. A large text scale can need that
/// too. The narrowest bar that fits is three button hit sizes plus its
/// horizontal padding, which is 160 pixels with the default style on
/// Android and Fuchsia, 148 on iOS and 112 on desktop platforms. A narrower
/// bar overflows.
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
    this.optionsTooltip = 'Search options',
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

  /// Tooltip and accessible name of the button that shows and hides the
  /// toggles on a touch platform, when they do not fit beside the field.
  final String optionsTooltip;

  /// Whether the match case toggle is offered.
  ///
  /// The toggles sit beside the field when they fit beside a field of
  /// [FindBarStyle.minFieldWidth]. When they do not, a desktop bar leaves
  /// them out and a touch bar shows a search options button that brings
  /// them up in a second row.
  final bool showMatchCase;

  /// Whether the match accents toggle is offered.
  ///
  /// It is placed and left out together with the match case toggle. See
  /// [showMatchCase].
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
  final GlobalKey _matchCaseKey = GlobalKey(debugLabel: 'match case');
  final GlobalKey _matchAccentsKey = GlobalKey(debugLabel: 'match accents');
  final FocusNode _matchCaseFocus = FocusNode(debugLabel: 'FindBar case');
  final FocusNode _matchAccentsFocus = FocusNode(debugLabel: 'FindBar accents');
  final FocusNode _optionsFocus = FocusNode(debugLabel: 'FindBar options');

  /// Whether the options button has the toggles row open.
  bool _optionsOpen = false;

  /// Whether the last layout showed the toggles row.
  bool _optionsRowShown = false;
  bool _showSelectionHandles = false;
  FindFieldSelectionControls? _handles;
  FindBarStyle? _resolvedStyle;
  FindBarFocusRequests? _focusRequests;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The scope that shows this bar asks it for focus again when the find
    // shortcut is pressed while it is open.
    final requests = FindBarFocusScope.maybeOf(context);
    if (!identical(requests, _focusRequests)) {
      _focusRequests?._unregister(this);
      _focusRequests = requests?.._register(this);
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
    _focusRequests?._unregister(this);
    _session.removeListener(_syncFromController);
    // See the initState comment. If _focusNode still has primary focus here,
    // Flutter itself moves focus back to whatever held it before as part of
    // disposing a focused node.
    _text.dispose();
    _focusNode.dispose();
    _matchCaseFocus.dispose();
    _matchAccentsFocus.dispose();
    _optionsFocus.dispose();
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

  /// Moves focus into the query field and selects the query.
  void _focusQuery() {
    _text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _text.text.length,
    );
    _focusNode.requestFocus();
  }

  bool get _toggleHasFocus =>
      _matchCaseFocus.hasFocus || _matchAccentsFocus.hasFocus;

  void _toggleOptions() {
    // A toggle about to be hidden hands focus to the button that hides it.
    if (_optionsOpen && _toggleHasFocus) _optionsFocus.requestFocus();
    setState(() => _optionsOpen = !_optionsOpen);
  }

  /// Hides the toggles row when one of its toggles has focus, and moves
  /// focus to the options button that showed it. Reports whether it did.
  bool _dismissOptionsFromKeyboard() {
    if (!_optionsRowShown || !_toggleHasFocus) return false;
    setState(() => _optionsOpen = false);
    _optionsFocus.requestFocus();
    return true;
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

  /// The width of [text] in the counter style, at the text scale the counter
  /// is painted with.
  static double _textWidth(
    FindBarStyle style,
    String text,
    TextScaler textScaler,
    TextDirection textDirection,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style.counterStyle),
      textScaler: textScaler,
      textDirection: textDirection,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  static const double _fieldGap = 4;

  /// Space on each side of the counter. A touch bar keeps it narrow, since
  /// the hit area of the next button already sets the counter apart.
  static EdgeInsets _counterPaddingFor({required bool touch}) =>
      EdgeInsets.symmetric(horizontal: touch ? 2 : 6);

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
    // The same numbers the announced label gets. A session can report
    // matches with none of them active, which shows as 0 of the count.
    final counter = session.query.isEmpty
        ? null
        : (count == 0 ? '0/0' : '${(active ?? -1) + 1}/$count');
    final toggles =
        (widget.showMatchCase ? 1 : 0) + (widget.showMatchAccents ? 1 : 0);

    final extent = FindBarIconButton.extentOf(style);
    final touch = FindBarIconButton.touchTargetSize > 0;
    final minField = style.minFieldWidth!;
    final counterPadding = _counterPaddingFor(touch: touch);
    final counterText = counter == null
        ? 0.0
        : _textWidth(style, counter, textScaler, textDirection);
    // A touch bar sets aside room for the widest counter of three digits a
    // side, or of as many as the match count has, before a counter shows.
    // The row then holds still when the first letter is typed.
    final digits = math.max(3, '$count'.length);
    final reservedText = touch
        ? math.max(
            counterText,
            _textWidth(
              style,
              '${'0' * digits}/${'0' * digits}',
              textScaler,
              textDirection,
            ),
          )
        : counterText;
    final showCounterSlot = touch || counter != null;
    final counterSlot = showCounterSlot
        ? reservedText + counterPadding.horizontal
        : 0.0;

    // The toggles, wherever the layout puts them. Their global keys carry
    // focus and hover state across a move between the rows.
    List<Widget> toggleButtons({required bool inline}) => [
      if (widget.showMatchCase)
        _ordered(
          inline ? 1 : 6,
          key: const ValueKey('matchCase'),
          buttonKey: _matchCaseKey,
          focusNode: _matchCaseFocus,
          glyph: FindBarGlyph.matchCase,
          label: widget.matchCaseTooltip,
          toggled: session.caseSensitive,
          style: style,
          onPressed: () => session.search(
            session.query,
            caseSensitive: !session.caseSensitive,
          ),
        ),
      if (widget.showMatchAccents)
        _ordered(
          inline ? 2 : 7,
          key: const ValueKey('matchAccents'),
          buttonKey: _matchAccentsKey,
          focusNode: _matchAccentsFocus,
          glyph: FindBarGlyph.matchAccents,
          label: widget.matchAccentsTooltip,
          toggled: session.diacriticSensitive,
          style: style,
          onPressed: () => session.search(
            session.query,
            diacriticSensitive: !session.diacriticSensitive,
          ),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxWidth;
        // The field at its narrowest, the counter, and previous, next and
        // close at their full hit size.
        final oneRow = minField + _fieldGap + counterSlot + 3 * extent;
        final togglesInline = toggles > 0 && room >= oneRow + toggles * extent;
        // Where the toggles do not fit beside the field, a touch bar offers
        // them through an options button and a desktop bar leaves them out.
        final options = touch && toggles > 0 && !togglesInline;
        final optionsExtent = options ? extent : 0.0;
        // Too narrow for one row. Previous, next and close move below the
        // field and keep their full hit size.
        final stacked = room < oneRow + optionsExtent;
        // A toggle that has focus stays on screen when the bar narrows.
        if (options && !_optionsOpen && _toggleHasFocus) _optionsOpen = true;
        final optionsRow = options && _optionsOpen;
        _optionsRowShown = optionsRow;
        // Beside the field in a stacked bar, the counter only gets what
        // leaves the field at its narrowest. A longer one is scaled down.
        final counterMax = stacked
            ? math.max(
                0.0,
                room -
                    _fieldGap -
                    minField -
                    optionsExtent -
                    counterPadding.horizontal,
              )
            : double.infinity;

        // The same widgets in every layout, which keeps the field and a
        // focused button in place when the bar switches between them.
        final controls = Flex(
          direction: stacked ? Axis.vertical : Axis.horizontal,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: stacked
              ? CrossAxisAlignment.stretch
              : CrossAxisAlignment.center,
          children: [
            Flexible(
              // A flex of 0 lays the row out at its own height in a column.
              flex: stacked ? 0 : 1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    key: const ValueKey('field'),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: minField,
                        maxWidth: style.maxFieldWidth!,
                      ),
                      child: FocusTraversalOrder(
                        order: const NumericFocusOrder(0),
                        child: _buildField(style, hasOverlay, extent),
                      ),
                    ),
                  ),
                  const SizedBox(width: _fieldGap),
                  if (togglesInline) ...toggleButtons(inline: true),
                  if (showCounterSlot)
                    Padding(
                      key: const ValueKey('counter'),
                      padding: counterPadding,
                      child: SizedBox(
                        width: math.min(reservedText, counterMax),
                        child: counter == null
                            ? null
                            : Semantics(
                                container: true,
                                liveRegion: true,
                                label: widget.matchStatusLabel(
                                  active ?? -1,
                                  count,
                                ),
                                child: ExcludeSemantics(
                                  child: Align(
                                    heightFactor: 1,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        counter,
                                        style: style.counterStyle,
                                        maxLines: 1,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  if (options)
                    _ordered(
                      1,
                      key: const ValueKey('options'),
                      focusNode: _optionsFocus,
                      glyph: FindBarGlyph.options,
                      label: widget.optionsTooltip,
                      toggled: optionsRow,
                      style: style,
                      onPressed: _toggleOptions,
                    ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
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
            ),
          ],
        );

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            controls,
            if (optionsRow)
              // Escape on a toggle hides the row and leaves the rest of the
              // bar open.
              Actions(
                actions: <Type, Action<Intent>>{
                  _CloseOptionsIntent: _BarAction<_CloseOptionsIntent>(
                    isEnabled: () => _toggleHasFocus,
                    onInvoke: _dismissOptionsFromKeyboard,
                  ),
                },
                child: Shortcuts(
                  shortcuts: const <ShortcutActivator, Intent>{
                    SingleActivator(LogicalKeyboardKey.escape):
                        _CloseOptionsIntent(),
                  },
                  child: Row(
                    key: const ValueKey('options row'),
                    mainAxisSize: MainAxisSize.min,
                    children: toggleButtons(inline: false),
                  ),
                ),
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
    Key? buttonKey,
    FocusNode? focusNode,
    bool? toggled,
  }) {
    return FocusTraversalOrder(
      key: key,
      order: NumericFocusOrder(order),
      child: FindBarIconButton(
        key: buttonKey,
        focusNode: focusNode,
        glyph: glyph,
        label: label,
        style: style,
        toggled: toggled,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildField(FindBarStyle style, bool hasOverlay, double hitHeight) {
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
        // The field takes taps across the height of a button's hit area,
        // with the line of text centered in it.
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: hitHeight),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            heightFactor: 1,
            child: field,
          ),
        ),
      ),
    );
  }
}

/// Holds the way back into the query field of the bar a scope shows.
///
/// A [FindBar] below a [FindBarFocusScope] registers itself here, whether
/// the scope built it or its `barBuilder` returned it. The scope calls
/// [focusQuery] when the find shortcut is pressed while the bar is open,
/// the same as a browser does with its own find bar.
final class FindBarFocusRequests {
  /// The registered bars, oldest first. The last one is the one in use.
  final List<_FindBarState> _bars = [];

  void _register(_FindBarState bar) {
    _bars
      ..remove(bar)
      ..add(bar);
  }

  void _unregister(_FindBarState bar) => _bars.remove(bar);

  /// Moves focus into the query field of the last bar still registered and
  /// selects the query. Does nothing when no bar is registered.
  void focusQuery() {
    if (_bars.isNotEmpty) _bars.last._focusQuery();
  }

  /// Hides the matching options of the last bar still registered when one
  /// of them has focus, and reports whether it did.
  ///
  /// The scope asks before Escape closes find. Escape on an option closes
  /// only the options.
  bool dismissOptions() =>
      _bars.isNotEmpty && _bars.last._dismissOptionsFromKeyboard();
}

/// Hands a [FindBarFocusRequests] to the [FindBar] below it.
class FindBarFocusScope extends InheritedWidget {
  /// Makes [requests] the place where bars in [child] register.
  const FindBarFocusScope({
    required this.requests,
    required super.child,
    super.key,
  });

  /// Where bars below this widget register.
  final FindBarFocusRequests requests;

  /// The requests of the nearest enclosing scope, or null.
  static FindBarFocusRequests? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FindBarFocusScope>()?.requests;

  @override
  bool updateShouldNotify(FindBarFocusScope oldWidget) =>
      !identical(requests, oldWidget.requests);
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

class _CloseOptionsIntent extends Intent {
  const _CloseOptionsIntent();
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
