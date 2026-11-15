import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Colors, text styles and geometry for a `FindBar`.
///
/// Every value is optional. A bar resolves its style in three layers. The
/// bar's own `style` wins, then the nearest [FindBarTheme], then
/// [FindBarStyle.fallback] for the platform brightness. The bar reads no
/// design-system theme of its own.
///
/// Apps that already have a theme can derive a style from it once, near the
/// root of the app, and hand it to [FindBarTheme].
@immutable
final class FindBarStyle with Diagnosticable {
  /// Creates a style. Values left null are taken from the next layer.
  const FindBarStyle({
    this.backgroundColor,
    this.foregroundColor,
    this.hintColor,
    this.accentColor,
    this.hoverColor,
    this.pressedColor,
    this.tooltipColor,
    this.textStyle,
    this.counterStyle,
    this.tooltipTextStyle,
    this.borderRadius,
    this.border,
    this.shadows,
    this.padding,
    this.buttonSize,
    this.iconSize,
    this.minFieldWidth,
    this.maxFieldWidth,
  });

  /// The neutral defaults for [brightness].
  ///
  /// Light uses a white surface with near-black text. Dark uses a charcoal
  /// surface with near-white text. In both, the text, the placeholder and
  /// the match counter stay above a 4.5 to 1 contrast ratio against the
  /// surface.
  ///
  /// The text styles here carry no color, and the hover, pressed, tooltip
  /// and border colors are left null. [FindBarTheme.resolve] fills them in
  /// from the resolved [foregroundColor], [backgroundColor] and [hintColor].
  /// A style that changes only those three colors keeps everything else
  /// readable against them.
  factory FindBarStyle.fallback(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return FindBarStyle(
      backgroundColor: dark ? const Color(0xFF2B3036) : const Color(0xFFFFFFFF),
      foregroundColor: dark ? const Color(0xFFE6EDF3) : const Color(0xFF1F2328),
      hintColor: dark ? const Color(0xFFA9B4BF) : const Color(0xFF59636E),
      accentColor: dark ? const Color(0xFF6CA9FF) : const Color(0xFF0969DA),
      textStyle: const TextStyle(
        inherit: false,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        decoration: TextDecoration.none,
        textBaseline: TextBaseline.alphabetic,
      ),
      counterStyle: const TextStyle(
        inherit: false,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        decoration: TextDecoration.none,
        textBaseline: TextBaseline.alphabetic,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      tooltipTextStyle: const TextStyle(
        inherit: false,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        decoration: TextDecoration.none,
        textBaseline: TextBaseline.alphabetic,
      ),
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      shadows: [
        BoxShadow(
          color: dark ? const Color(0x66000000) : const Color(0x29000000),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      buttonSize: 32,
      iconSize: 18,
      minFieldWidth: 96,
      maxFieldWidth: 180,
    );
  }

  /// Fill behind the whole bar.
  final Color? backgroundColor;

  /// Color of the query text and the button icons.
  final Color? foregroundColor;

  /// Color of the placeholder text.
  final Color? hintColor;

  /// Color of the cursor, the text selection, the focus ring and a switched
  /// on toggle.
  final Color? accentColor;

  /// Fill behind a button under a mouse pointer. Defaults to a light tint of
  /// [foregroundColor].
  final Color? hoverColor;

  /// Fill behind a button while it is pressed. Defaults to a stronger tint of
  /// [foregroundColor].
  final Color? pressedColor;

  /// Fill behind a button's tooltip. Defaults to [foregroundColor].
  final Color? tooltipColor;

  /// Style of the query text and of the placeholder.
  ///
  /// It is merged onto the layer below it, and a style with
  /// `inherit: false` replaces that layer outright. Without a color of its
  /// own the query is drawn in [foregroundColor]. The placeholder always uses
  /// [hintColor].
  final TextStyle? textStyle;

  /// Style of the match counter, such as `3/12`. Without a color of its own
  /// the counter is drawn in [hintColor].
  final TextStyle? counterStyle;

  /// Style of the text inside a tooltip. Without a color of its own it is
  /// drawn in [backgroundColor].
  final TextStyle? tooltipTextStyle;

  /// Corner radius of the bar.
  final BorderRadiusGeometry? borderRadius;

  /// Outline drawn around the bar. Defaults to a hairline tint of
  /// [foregroundColor].
  final BoxBorder? border;

  /// Shadows cast by the bar.
  final List<BoxShadow>? shadows;

  /// Space between the bar's edge and its contents.
  final EdgeInsetsGeometry? padding;

  /// Width and height of each button.
  final double? buttonSize;

  /// Size of the icon drawn inside each button.
  final double? iconSize;

  /// Narrowest the query field gets before the toggles are hidden.
  final double? minFieldWidth;

  /// Widest the query field grows.
  final double? maxFieldWidth;

  /// A copy with the given values replaced.
  FindBarStyle copyWith({
    Color? backgroundColor,
    Color? foregroundColor,
    Color? hintColor,
    Color? accentColor,
    Color? hoverColor,
    Color? pressedColor,
    Color? tooltipColor,
    TextStyle? textStyle,
    TextStyle? counterStyle,
    TextStyle? tooltipTextStyle,
    BorderRadiusGeometry? borderRadius,
    BoxBorder? border,
    List<BoxShadow>? shadows,
    EdgeInsetsGeometry? padding,
    double? buttonSize,
    double? iconSize,
    double? minFieldWidth,
    double? maxFieldWidth,
  }) {
    return FindBarStyle(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      foregroundColor: foregroundColor ?? this.foregroundColor,
      hintColor: hintColor ?? this.hintColor,
      accentColor: accentColor ?? this.accentColor,
      hoverColor: hoverColor ?? this.hoverColor,
      pressedColor: pressedColor ?? this.pressedColor,
      tooltipColor: tooltipColor ?? this.tooltipColor,
      textStyle: textStyle ?? this.textStyle,
      counterStyle: counterStyle ?? this.counterStyle,
      tooltipTextStyle: tooltipTextStyle ?? this.tooltipTextStyle,
      borderRadius: borderRadius ?? this.borderRadius,
      border: border ?? this.border,
      shadows: shadows ?? this.shadows,
      padding: padding ?? this.padding,
      buttonSize: buttonSize ?? this.buttonSize,
      iconSize: iconSize ?? this.iconSize,
      minFieldWidth: minFieldWidth ?? this.minFieldWidth,
      maxFieldWidth: maxFieldWidth ?? this.maxFieldWidth,
    );
  }

  /// This style with every non-null value of [other] laid on top.
  ///
  /// Text styles are merged with [TextStyle.merge] instead of replaced.
  FindBarStyle merge(FindBarStyle? other) {
    if (other == null) return this;
    return copyWith(
      backgroundColor: other.backgroundColor,
      foregroundColor: other.foregroundColor,
      hintColor: other.hintColor,
      accentColor: other.accentColor,
      hoverColor: other.hoverColor,
      pressedColor: other.pressedColor,
      tooltipColor: other.tooltipColor,
      textStyle: textStyle?.merge(other.textStyle) ?? other.textStyle,
      counterStyle:
          counterStyle?.merge(other.counterStyle) ?? other.counterStyle,
      tooltipTextStyle:
          tooltipTextStyle?.merge(other.tooltipTextStyle) ??
          other.tooltipTextStyle,
      borderRadius: other.borderRadius,
      border: other.border,
      shadows: other.shadows,
      padding: other.padding,
      buttonSize: other.buttonSize,
      iconSize: other.iconSize,
      minFieldWidth: other.minFieldWidth,
      maxFieldWidth: other.maxFieldWidth,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FindBarStyle &&
        other.backgroundColor == backgroundColor &&
        other.foregroundColor == foregroundColor &&
        other.hintColor == hintColor &&
        other.accentColor == accentColor &&
        other.hoverColor == hoverColor &&
        other.pressedColor == pressedColor &&
        other.tooltipColor == tooltipColor &&
        other.textStyle == textStyle &&
        other.counterStyle == counterStyle &&
        other.tooltipTextStyle == tooltipTextStyle &&
        other.borderRadius == borderRadius &&
        other.border == border &&
        listEquals(other.shadows, shadows) &&
        other.padding == padding &&
        other.buttonSize == buttonSize &&
        other.iconSize == iconSize &&
        other.minFieldWidth == minFieldWidth &&
        other.maxFieldWidth == maxFieldWidth;
  }

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    foregroundColor,
    hintColor,
    accentColor,
    hoverColor,
    pressedColor,
    tooltipColor,
    textStyle,
    counterStyle,
    tooltipTextStyle,
    borderRadius,
    border,
    shadows == null ? null : Object.hashAll(shadows!),
    padding,
    buttonSize,
    iconSize,
    minFieldWidth,
    maxFieldWidth,
  );

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(
        ColorProperty('backgroundColor', backgroundColor, defaultValue: null),
      )
      ..add(
        ColorProperty('foregroundColor', foregroundColor, defaultValue: null),
      )
      ..add(ColorProperty('hintColor', hintColor, defaultValue: null))
      ..add(ColorProperty('accentColor', accentColor, defaultValue: null))
      ..add(ColorProperty('hoverColor', hoverColor, defaultValue: null))
      ..add(ColorProperty('pressedColor', pressedColor, defaultValue: null))
      ..add(ColorProperty('tooltipColor', tooltipColor, defaultValue: null))
      ..add(
        DiagnosticsProperty<TextStyle>(
          'textStyle',
          textStyle,
          defaultValue: null,
        ),
      )
      ..add(
        DiagnosticsProperty<TextStyle>(
          'counterStyle',
          counterStyle,
          defaultValue: null,
        ),
      )
      ..add(
        DiagnosticsProperty<TextStyle>(
          'tooltipTextStyle',
          tooltipTextStyle,
          defaultValue: null,
        ),
      )
      ..add(
        DiagnosticsProperty<BorderRadiusGeometry>(
          'borderRadius',
          borderRadius,
          defaultValue: null,
        ),
      )
      ..add(
        DiagnosticsProperty<BoxBorder>('border', border, defaultValue: null),
      )
      ..add(IterableProperty<BoxShadow>('shadows', shadows, defaultValue: null))
      ..add(
        DiagnosticsProperty<EdgeInsetsGeometry>(
          'padding',
          padding,
          defaultValue: null,
        ),
      )
      ..add(DoubleProperty('buttonSize', buttonSize, defaultValue: null))
      ..add(DoubleProperty('iconSize', iconSize, defaultValue: null))
      ..add(DoubleProperty('minFieldWidth', minFieldWidth, defaultValue: null))
      ..add(DoubleProperty('maxFieldWidth', maxFieldWidth, defaultValue: null));
  }
}

/// Supplies a [FindBarStyle] to every `FindBar` below it.
///
/// This includes the bar a `FindInPageScope` shows, as long as the theme
/// sits above the scope. An inner theme replaces an outer one. It does not
/// merge with it.
///
/// ```dart
/// FindBarTheme(
///   style: const FindBarStyle(
///     backgroundColor: Color(0xFF1E293B),
///     foregroundColor: Color(0xFFF8FAFC),
///   ),
///   child: FindInPageScope(child: page),
/// )
/// ```
final class FindBarTheme extends InheritedTheme {
  /// Makes [style] the find bar style for [child].
  const FindBarTheme({required this.style, required super.child, super.key});

  /// The style applied to find bars below this widget.
  final FindBarStyle style;

  /// The style of the nearest enclosing [FindBarTheme], or null.
  static FindBarStyle? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FindBarTheme>()?.style;

  /// The style a find bar at [context] resolves to, with every value set.
  ///
  /// That is [FindBarStyle.fallback] for the platform brightness, with the
  /// nearest theme and then [style] laid over it. Colors no layer set are
  /// then derived from the resulting foreground, background and hint
  /// colors.
  static FindBarStyle resolve(BuildContext context, [FindBarStyle? style]) {
    final brightness =
        MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light;
    final merged = FindBarStyle.fallback(
      brightness,
    ).merge(maybeOf(context)).merge(style);
    final foreground = merged.foregroundColor!;
    final background = merged.backgroundColor!;
    return merged.copyWith(
      hoverColor: merged.hoverColor ?? foreground.withValues(alpha: 0.10),
      pressedColor: merged.pressedColor ?? foreground.withValues(alpha: 0.18),
      tooltipColor: merged.tooltipColor ?? foreground,
      border:
          merged.border ??
          Border.all(color: foreground.withValues(alpha: 0.18)),
      textStyle: _withColor(merged.textStyle, foreground),
      counterStyle: _withColor(merged.counterStyle, merged.hintColor!),
      tooltipTextStyle: _withColor(
        merged.tooltipTextStyle,
        _moreLegible(merged.tooltipColor ?? foreground, background, foreground),
      ),
    );
  }

  /// Whichever of [a] and [b] has the higher contrast against [surface].
  static Color _moreLegible(Color surface, Color a, Color b) {
    double contrast(Color color) {
      final x = color.computeLuminance() + 0.05;
      final y = surface.computeLuminance() + 0.05;
      return x > y ? x / y : y / x;
    }

    return contrast(a) >= contrast(b) ? a : b;
  }

  static TextStyle _withColor(TextStyle? style, Color color) {
    final base = style ?? const TextStyle();
    return base.color == null ? base.copyWith(color: color) : base;
  }

  @override
  Widget wrap(BuildContext context, Widget child) =>
      FindBarTheme(style: style, child: child);

  @override
  bool updateShouldNotify(FindBarTheme oldWidget) => style != oldWidget.style;
}
