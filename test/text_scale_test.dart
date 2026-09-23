import 'dart:ui' as ui;

import 'package:find_in_page/find_in_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _activeArgb = 0xFFCA47E8;
const _inactiveArgb = 0xFF176B87;
const _activeColor = Color(_activeArgb);
const _inactiveColor = Color(_inactiveArgb);
const _text = 'scale text scale';
const _rectTolerance = 1.5;

class _ScaleHost extends StatefulWidget {
  const _ScaleHost({
    required this.controller,
    required this.boundaryKey,
    required this.initialScale,
    super.key,
  });

  final FindInPageController controller;
  final GlobalKey boundaryKey;
  final double initialScale;

  @override
  State<_ScaleHost> createState() => _ScaleHostState();
}

class _ScaleHostState extends State<_ScaleHost> {
  late double _scale = widget.initialScale;

  void setScale(double value) => setState(() => _scale = value);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(_scale)),
        child: RepaintBoundary(
          key: widget.boundaryKey,
          child: FindInPageScope(
            controller: widget.controller,
            highlightColor: _inactiveColor,
            activeHighlightColor: _activeColor,
            child: const ColoredBox(
              color: Colors.white,
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(37, 29, 11, 13),
                  child: Text(_text, style: TextStyle(fontSize: 18)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

RenderParagraph _paragraphOf(WidgetTester tester, String text) {
  return tester.renderObject<RenderParagraph>(
    find.descendant(of: find.text(text), matching: find.byType(RichText)),
  );
}

List<Rect> _selectionRects(
  RenderParagraph paragraph,
  RenderObject ancestor,
  List<TextSelection> selections,
) {
  final transform = paragraph.getTransformTo(ancestor);
  return [
    for (final selection in selections)
      for (final box in paragraph.getBoxesForSelection(selection))
        MatrixUtils.transformRect(transform, box.toRect()).inflate(1),
  ];
}

Future<Map<int, Rect>> _paintedColorBounds(
  RenderRepaintBoundary boundary,
) async {
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(data, isNotNull);
    final bytes = data!.buffer.asUint8List();
    final bounds = <int, ({int minX, int minY, int maxX, int maxY})>{};

    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final offset = (y * image.width + x) * 4;
        final argb = (bytes[offset + 3] << 24) |
            (bytes[offset] << 16) |
            (bytes[offset + 1] << 8) |
            bytes[offset + 2];
        if (argb != _activeArgb && argb != _inactiveArgb) continue;
        final previous = bounds[argb];
        bounds[argb] = (
          minX: previous == null || x < previous.minX ? x : previous.minX,
          minY: previous == null || y < previous.minY ? y : previous.minY,
          maxX: previous == null || x > previous.maxX ? x : previous.maxX,
          maxY: previous == null || y > previous.maxY ? y : previous.maxY,
        );
      }
    }

    return {
      for (final entry in bounds.entries)
        entry.key: Rect.fromLTRB(
          entry.value.minX.toDouble(),
          entry.value.minY.toDouble(),
          (entry.value.maxX + 1).toDouble(),
          (entry.value.maxY + 1).toDouble(),
        ),
    };
  } finally {
    image.dispose();
  }
}

void _expectRectClose(Rect actual, Rect expected) {
  expect(actual.left, closeTo(expected.left, _rectTolerance));
  expect(actual.top, closeTo(expected.top, _rectTolerance));
  expect(actual.right, closeTo(expected.right, _rectTolerance));
  expect(actual.bottom, closeTo(expected.bottom, _rectTolerance));
}

List<({String text, Color color})> _highlightedSpans(WidgetTester tester) {
  final highlighted = <({String text, Color color})>[];
  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    richText.text.visitChildren((span) {
      final color = span.style?.backgroundColor;
      if (span is TextSpan && span.text != null && color != null) {
        highlighted.add((text: span.text!, color: color));
      }
      return true;
    });
  }
  return highlighted;
}

void main() {
  testWidgets('discovered highlights paint the scaled selection rectangles', (
    tester,
  ) async {
    final sizes = <Size>[];

    for (final scale in [1.0, 2.0]) {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final hostKey = GlobalKey<_ScaleHostState>();
      final boundaryKey = GlobalKey();

      await tester.pumpWidget(
        _ScaleHost(
          key: hostKey,
          controller: controller,
          boundaryKey: boundaryKey,
          initialScale: scale,
        ),
      );
      controller.search('scale');
      await tester.pump();

      expect(controller.matchCount, 2);
      expect(controller.activeMatchIndex, 0);
      final paragraph = _paragraphOf(tester, _text);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final expected = _selectionRects(
        paragraph,
        boundary,
        const [
          TextSelection(baseOffset: 0, extentOffset: 5),
          TextSelection(baseOffset: 11, extentOffset: 16),
        ],
      );
      final painted = (await tester.runAsync(
        () => _paintedColorBounds(boundary),
      ))!;

      expect(painted.keys, containsAll([_activeArgb, _inactiveArgb]));
      _expectRectClose(painted[_activeArgb]!, expected[0]);
      _expectRectClose(painted[_inactiveArgb]!, expected[1]);
      sizes.add(expected.first.size);
    }

    expect(sizes[1].width, greaterThan(sizes[0].width));
    expect(sizes[1].height, greaterThan(sizes[0].height));
  });

  testWidgets(
    'changing text scale repaints existing highlights without another search',
    (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final hostKey = GlobalKey<_ScaleHostState>();
      final boundaryKey = GlobalKey();

      await tester.pumpWidget(
        _ScaleHost(
          key: hostKey,
          controller: controller,
          boundaryKey: boundaryKey,
          initialScale: 1,
        ),
      );
      controller.search('scale');
      await tester.pump();

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final firstParagraph = _paragraphOf(tester, _text);
      final firstExpected = _selectionRects(
        firstParagraph,
        boundary,
        const [TextSelection(baseOffset: 0, extentOffset: 5)],
      ).single;
      final firstPaint = (await tester.runAsync(
        () => _paintedColorBounds(boundary),
      ))!;
      _expectRectClose(firstPaint[_activeArgb]!, firstExpected);

      hostKey.currentState!.setScale(2);
      await tester.pump();

      expect(controller.query, 'scale');
      expect(controller.matchCount, 2);
      expect(controller.activeMatchIndex, 0);
      final scaledParagraph = _paragraphOf(tester, _text);
      final scaledExpected = _selectionRects(
        scaledParagraph,
        boundary,
        const [TextSelection(baseOffset: 0, extentOffset: 5)],
      ).single;
      final scaledPaint = (await tester.runAsync(
        () => _paintedColorBounds(boundary),
      ))!;

      expect(scaledExpected.width, greaterThan(firstExpected.width));
      expect(scaledExpected.height, greaterThan(firstExpected.height));
      _expectRectClose(scaledPaint[_activeArgb]!, scaledExpected);
      expect(
        (scaledPaint[_activeArgb]!.width - firstExpected.width).abs(),
        greaterThan(_rectTolerance),
      );
    },
  );

  testWidgets(
    'explicit textScaler preserves inline highlight layout and custom colors',
    (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      const text = 'Straße Straße';

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(0.75)),
            child: FindInPageScope(
              controller: controller,
              child: const Scaffold(
                body: Padding(
                  padding: EdgeInsets.all(23),
                  child: FindableText(
                    text,
                    style: TextStyle(fontSize: 20),
                    textScaler: TextScaler.linear(2),
                    highlightColor: _inactiveColor,
                    activeHighlightColor: _activeColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final plainParagraph = _paragraphOf(tester, text);
      final plainSize = plainParagraph.size;
      final plainBoxes = plainParagraph
          .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: text.length),
          )
          .map((box) => box.toRect())
          .toList();
      expect(plainParagraph.textScaler.scale(10), closeTo(20, 0.01));

      controller.search('strasse');
      await tester.pump();

      final highlightedParagraph = _paragraphOf(tester, text);
      final highlightedBoxes = highlightedParagraph
          .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: text.length),
          )
          .map((box) => box.toRect())
          .toList();
      expect(controller.matchCount, 2);
      expect(highlightedParagraph.textScaler.scale(10), closeTo(20, 0.01));
      expect(highlightedParagraph.size, plainSize);
      expect(highlightedBoxes, hasLength(plainBoxes.length));
      for (var index = 0; index < plainBoxes.length; index++) {
        _expectRectClose(highlightedBoxes[index], plainBoxes[index]);
      }
      expect(
        _highlightedSpans(tester),
        const [
          (text: 'Straße', color: _activeColor),
          (text: 'Straße', color: _inactiveColor),
        ],
      );
    },
  );
}
