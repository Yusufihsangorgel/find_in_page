import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'find_bar_style.dart';

/// The icons a find bar draws. Each one is painted with paths or text, with
/// no icon font involved.
enum FindBarGlyph {
  /// An upward chevron, for the previous match.
  previous,

  /// A downward chevron, for the next match.
  next,

  /// A cross, for closing the bar.
  close,

  /// The letters "Aa", for the match case toggle.
  matchCase,

  /// An accented letter, for the match accents toggle.
  matchAccents,

  /// The letters "Aa", for the button that shows and hides the toggles.
  options,
}

/// Paints one [FindBarGlyph] centered in the canvas.
class FindBarGlyphPainter extends CustomPainter {
  /// Creates a painter for [glyph] in [color].
  const FindBarGlyphPainter({
    required this.glyph,
    required this.color,
    this.fontFamily,
  });

  /// The icon to paint.
  final FindBarGlyph glyph;

  /// Stroke and text color.
  final Color color;

  /// Font family for the two lettered glyphs. Null uses the platform font.
  final String? fontFamily;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final origin = Offset((size.width - side) / 2, (size.height - side) / 2);
    Offset at(double x, double y) => origin + Offset(x * side, y * side);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, side * 0.11)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (glyph) {
      case FindBarGlyph.previous:
        canvas.drawPath(
          Path()
            ..moveTo(at(0.22, 0.64).dx, at(0.22, 0.64).dy)
            ..lineTo(at(0.5, 0.36).dx, at(0.5, 0.36).dy)
            ..lineTo(at(0.78, 0.64).dx, at(0.78, 0.64).dy),
          stroke,
        );
      case FindBarGlyph.next:
        canvas.drawPath(
          Path()
            ..moveTo(at(0.22, 0.36).dx, at(0.22, 0.36).dy)
            ..lineTo(at(0.5, 0.64).dx, at(0.5, 0.64).dy)
            ..lineTo(at(0.78, 0.36).dx, at(0.78, 0.36).dy),
          stroke,
        );
      case FindBarGlyph.close:
        canvas
          ..drawLine(at(0.27, 0.27), at(0.73, 0.73), stroke)
          ..drawLine(at(0.73, 0.27), at(0.27, 0.73), stroke);
      case FindBarGlyph.matchCase:
      case FindBarGlyph.options:
        _paintLetters(canvas, size, 'Aa', side * 0.68);
      case FindBarGlyph.matchAccents:
        _paintLetters(canvas, size, 'á', side * 0.86);
    }
  }

  void _paintLetters(Canvas canvas, Size size, String letters, double height) {
    final painter = TextPainter(
      text: TextSpan(
        text: letters,
        style: TextStyle(
          inherit: false,
          color: color,
          fontFamily: fontFamily,
          fontSize: height,
          fontWeight: FontWeight.w600,
          height: 1,
          letterSpacing: 0,
        ),
      ),
      // An icon keeps its size at any text scale, like the drawn ones do.
      textScaler: TextScaler.noScaling,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        (size.width - painter.width) / 2,
        (size.height - painter.height) / 2,
      ),
    );
    painter.dispose();
  }

  @override
  bool shouldRepaint(FindBarGlyphPainter oldDelegate) =>
      glyph != oldDelegate.glyph ||
      color != oldDelegate.color ||
      fontFamily != oldDelegate.fontFamily;
}

/// A square icon button for the find bar, built on the widgets layer.
///
/// It is focusable and activates with the keyboard's activate keys, shows
/// hover, press and focus states, carries a tooltip, and is announced as a
/// button with [label]. Passing [toggled] makes it a toggle button.
///
/// A switched on toggle is filled with the accent color, and its glyph takes
/// whichever of the background and foreground colors reads better on that
/// fill. The focus ring sits outside the fill with a gap of background
/// between them, which keeps it visible on a switched on toggle.
class FindBarIconButton extends StatefulWidget {
  /// Creates a button that draws [glyph] and calls [onPressed].
  const FindBarIconButton({
    required this.glyph,
    required this.label,
    required this.onPressed,
    required this.style,
    this.toggled,
    this.focusNode,
    super.key,
  });

  /// The icon drawn in the button.
  final FindBarGlyph glyph;

  /// Tooltip text and accessible name.
  final String label;

  /// Called on tap, on the activate keys and on a screen reader's activate
  /// gesture. Null disables the button.
  final VoidCallback? onPressed;

  /// A fully resolved style, as returned by [FindBarTheme.resolve].
  final FindBarStyle style;

  /// Whether a toggle button is switched on. Null for a plain button.
  final bool? toggled;

  /// The node that holds the button's keyboard focus. When null, the button
  /// keeps one of its own.
  final FocusNode? focusNode;

  /// The touch target size [defaultTargetPlatform] asks for, or 0 on a
  /// desktop platform.
  ///
  /// Android and Fuchsia ask for 48 by 48 and iOS for 44 by 44. The choice
  /// follows the platform alone, the same as Flutter's Material tap target
  /// default. A browser on a phone reports the phone's platform and gets its
  /// touch size, and a desktop browser gets none.
  static double get touchTargetSize => switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.fuchsia => 48,
    TargetPlatform.iOS => 44,
    TargetPlatform.linux || TargetPlatform.macOS || TargetPlatform.windows => 0,
  };

  /// The width and height a button takes in the bar, painted area and hit
  /// area together.
  ///
  /// On a touch platform the button keeps its painted [style] size and the
  /// space around it up to [touchTargetSize] takes taps too. Desktop
  /// platforms keep the compact [FindBarStyle.buttonSize].
  static double extentOf(FindBarStyle style) =>
      math.max(style.buttonSize!, touchTargetSize);

  @override
  State<FindBarIconButton> createState() => _FindBarIconButtonState();
}

class _FindBarIconButtonState extends State<FindBarIconButton> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  void _activate() => widget.onPressed?.call();

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  void didUpdateWidget(FindBarIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled) _pressed = false;
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final accent = style.accentColor!;
    final foreground = style.foregroundColor!;
    final on = widget.toggled ?? false;

    // A light tint of the accent did not set a switched on toggle apart from
    // a switched off one. A solid fill does, in both default themes.
    var fill = on ? accent : const Color(0x00000000);
    if (_enabled && (_pressed || _hovered)) {
      fill = Color.alphaBlend(
        _pressed ? style.pressedColor! : style.hoverColor!,
        fill,
      );
    }
    final glyphColor = !_enabled
        ? foreground.withValues(alpha: 0.38)
        : on
        ? moreLegibleOn(accent, style.backgroundColor!, foreground)
        : foreground;

    Widget result = SizedBox.square(
      dimension: style.buttonSize,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(6)),
          border: _focused ? Border.all(color: accent, width: 2) : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              // The ring and the fill would merge on a switched on toggle.
              // While the ring shows, the fill is inset to leave a gap of
              // background between them.
              child: Padding(
                padding: EdgeInsets.all(_focused ? 4 : 0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.all(
                      Radius.circular(_focused ? 2 : 6),
                    ),
                  ),
                ),
              ),
            ),
            CustomPaint(
              size: Size.square(style.iconSize!),
              painter: FindBarGlyphPainter(
                glyph: widget.glyph,
                color: glyphColor,
                fontFamily: style.textStyle?.fontFamily,
              ),
            ),
          ],
        ),
      ),
    );

    // A tooltip needs an Overlay to draw into. Without one the button still
    // works and is still labelled for screen readers.
    if (Overlay.maybeOf(context) != null) {
      result = RawTooltip(
        semanticsTooltip: widget.label,
        positionDelegate: _belowTarget,
        tooltipBuilder: (context, animation) => FadeTransition(
          opacity: animation,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: style.tooltipColor,
              borderRadius: const BorderRadius.all(Radius.circular(4)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(widget.label, style: style.tooltipTextStyle),
            ),
          ),
        ),
        child: result,
      );
    }

    // On touch platforms the square around the painted button takes taps
    // too. It sits inside the gesture detector and counts as the button.
    final extent = FindBarIconButton.extentOf(style);
    if (extent > style.buttonSize!) {
      result = SizedBox.square(
        dimension: extent,
        child: Center(child: result),
      );
    }

    result = GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTapDown: _enabled ? (_) => _setPressed(true) : null,
      onTapUp: _enabled ? (_) => _setPressed(false) : null,
      onTapCancel: _enabled ? () => _setPressed(false) : null,
      onTap: _enabled ? _activate : null,
      child: result,
    );

    return Semantics(
      container: true,
      button: true,
      enabled: _enabled,
      toggled: widget.toggled,
      label: widget.label,
      onTap: _enabled ? _activate : null,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        enabled: _enabled,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        mouseCursor: _enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        // The label above already names the button. The tooltip's own
        // semantics would announce the same words a second time.
        child: ExcludeSemantics(child: result),
      ),
    );
  }

  static Offset _belowTarget(TooltipPositionContext context) =>
      positionDependentBox(
        size: context.overlaySize,
        childSize: context.tooltipSize,
        target: context.target,
        preferBelow: true,
        verticalOffset: context.targetSize.height / 2 + 4,
      );
}

/// Selection handles for the find bar's query field, drawn on the widgets
/// layer.
///
/// Every touch platform gets the same rounded handle in the bar's accent
/// color. The context menu is supplied separately through
/// `EditableText.contextMenuBuilder`.
class FindFieldSelectionControls extends TextSelectionControls
    with TextSelectionHandleControls {
  /// Creates handles painted in [color].
  FindFieldSelectionControls(this.color);

  /// Fill of the handles.
  final Color color;

  static const double _size = 22;

  @override
  Size getHandleSize(double textLineHeight) => const Size.square(_size);

  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textLineHeight, [
    VoidCallback? onTap,
  ]) {
    final handle = SizedBox.square(
      dimension: _size,
      child: CustomPaint(
        painter: _HandlePainter(color),
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.translucent,
        ),
      ),
    );
    // The unrotated drop points up and to the left, toward the end of a
    // selection. Rotations aim it at the start, or straight up for a caret.
    return switch (type) {
      TextSelectionHandleType.left => Transform.rotate(
        angle: math.pi / 2,
        child: handle,
      ),
      TextSelectionHandleType.right => handle,
      TextSelectionHandleType.collapsed => Transform.rotate(
        angle: math.pi / 4,
        child: handle,
      ),
    };
  }

  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) {
    return switch (type) {
      TextSelectionHandleType.left => const Offset(_size, 0),
      TextSelectionHandleType.right => Offset.zero,
      TextSelectionHandleType.collapsed => const Offset(_size / 2, -4),
    };
  }
}

class _HandlePainter extends CustomPainter {
  const _HandlePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    canvas.drawPath(
      Path()
        ..addOval(
          Rect.fromCircle(center: Offset(radius, radius), radius: radius),
        )
        ..addRect(Rect.fromLTWH(0, 0, radius, radius)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_HandlePainter oldDelegate) => color != oldDelegate.color;
}

/// The query field's context menu where the platform has none to offer.
///
/// It lists the field's own [buttonItems] (cut, copy, paste, select all and
/// whatever else the field reports) with labels from the ambient
/// [WidgetsLocalizations]. Desktop platforms open it as a vertical list at
/// the pointer. Touch platforms place a row above the selection, or below
/// it when there is no room above.
class FindFieldContextMenu extends StatelessWidget {
  /// Creates a menu for [buttonItems] at [anchors].
  const FindFieldContextMenu({
    required this.anchors,
    required this.buttonItems,
    required this.style,
    super.key,
  });

  /// Where the field asks for the menu to appear.
  final TextSelectionToolbarAnchors anchors;

  /// The actions to offer.
  final List<ContextMenuButtonItem> buttonItems;

  /// A fully resolved style, as returned by [FindBarTheme.resolve].
  final FindBarStyle style;

  static const double _screenPadding = 8;

  static bool get _isDesktop => switch (defaultTargetPlatform) {
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    TargetPlatform.android ||
    TargetPlatform.fuchsia ||
    TargetPlatform.iOS => false,
  };

  /// The label for [item], localized where the widgets layer has a string.
  static String labelFor(BuildContext context, ContextMenuButtonItem item) {
    final label = item.label;
    if (label != null) return label;
    final strings =
        Localizations.of<WidgetsLocalizations>(context, WidgetsLocalizations) ??
        const DefaultWidgetsLocalizations();
    return switch (item.type) {
      ContextMenuButtonType.cut => strings.cutButtonLabel,
      ContextMenuButtonType.copy => strings.copyButtonLabel,
      ContextMenuButtonType.paste => strings.pasteButtonLabel,
      ContextMenuButtonType.selectAll => strings.selectAllButtonLabel,
      ContextMenuButtonType.lookUp => strings.lookUpButtonLabel,
      ContextMenuButtonType.searchWeb => strings.searchWebButtonLabel,
      ContextMenuButtonType.share => strings.shareButtonLabel,
      ContextMenuButtonType.delete => 'Delete',
      ContextMenuButtonType.liveTextInput => 'Scan Text',
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    if (buttonItems.isEmpty) return const SizedBox.shrink();
    final desktop = _isDesktop;
    final paddingAbove =
        (MediaQuery.maybePaddingOf(context)?.top ?? 0) + _screenPadding;
    final shift = Offset(_screenPadding, paddingAbove);

    final items = [
      for (final item in buttonItems)
        _MenuItem(
          label: labelFor(context, item),
          onPressed: item.onPressed,
          style: style,
          wide: desktop,
        ),
    ];

    final menu = DecoratedBox(
      decoration: BoxDecoration(
        color: style.backgroundColor,
        borderRadius: style.borderRadius,
        border: style.border,
        boxShadow: style.shadows,
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: desktop
            ? IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: items,
                ),
              )
            : Row(mainAxisSize: MainAxisSize.min, children: items),
      ),
    );

    return TextFieldTapRegion(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          _screenPadding,
          paddingAbove,
          _screenPadding,
          _screenPadding,
        ),
        child: CustomSingleChildLayout(
          delegate: desktop
              ? DesktopTextSelectionToolbarLayoutDelegate(
                  anchor: anchors.primaryAnchor - shift,
                )
              : TextSelectionToolbarLayoutDelegate(
                  anchorAbove:
                      anchors.primaryAnchor - shift - const Offset(0, 8),
                  anchorBelow:
                      (anchors.secondaryAnchor ?? anchors.primaryAnchor) -
                      shift +
                      const Offset(0, 20),
                ),
          child: menu,
        ),
      ),
    );
  }
}

class _MenuItem extends StatefulWidget {
  const _MenuItem({
    required this.label,
    required this.onPressed,
    required this.style,
    required this.wide,
  });

  final String label;
  final VoidCallback? onPressed;
  final FindBarStyle style;
  final bool wide;

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final textStyle = style.textStyle!.copyWith(
      color: style.textStyle!.color ?? style.foregroundColor,
    );
    return Semantics(
      button: true,
      enabled: widget.onPressed != null,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _hovered ? style.hoverColor : null,
              borderRadius: const BorderRadius.all(Radius.circular(4)),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: widget.wide ? 6 : 10,
              ),
              child: Text(widget.label, style: textStyle, maxLines: 1),
            ),
          ),
        ),
      ),
    );
  }
}
