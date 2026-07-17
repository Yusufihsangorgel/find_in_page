// Captures the frames for doc/demo.gif. Not part of the regular test
// suite; run explicitly with:
//
//   flutter test --tags demo test/demo_capture_test.dart
//
// Frames are written to /tmp/demo_find_in_page/frame_NNN.png and
// assembled with ffmpeg (see doc/demo.gif in the README).
@Tags(['demo'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:find_in_page/find_in_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _captureKey = ValueKey('demo-capture');
final _frameDir = Directory('/tmp/demo_find_in_page');
int _frameIndex = 0;

void main() {
  testWidgets('captures find-in-page demo frames', (tester) async {
    if (_frameDir.existsSync()) _frameDir.deleteSync(recursive: true);
    _frameDir.createSync(recursive: true);

    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    EditableText.debugDeterministicCursor = true;
    addTearDown(() => EditableText.debugDeterministicCursor = false);
    await _loadRealFonts(tester);

    final controller = FindInPageController();
    addTearDown(controller.dispose);

    // Tests paint a solid outline instead of shadows; the captures should
    // show the find bar's real elevation. This must be restored before the
    // test body ends, hence try/finally rather than a teardown.
    debugDisableShadows = false;
    try {
      await _run(tester, controller);
    } finally {
      debugDisableShadows = true;
    }
  });
}

Future<void> _run(WidgetTester tester, FindInPageController controller) async {
  await tester.pumpWidget(_DemoApp(controller: controller));

  // The article at rest.
  await _capture(tester);
  await tester.pump(const Duration(milliseconds: 60));
  await _capture(tester);

  // Ctrl+F opens the find bar.
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await _capture(tester);
  await tester.pump(const Duration(milliseconds: 60));
  await _capture(tester);

  // Type the query letter by letter; matches highlight as it grows.
  const query = 'flutter';
  for (var i = 1; i <= query.length; i++) {
    await tester.enterText(find.byType(TextField), query.substring(0, i));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await _capture(tester);
  }

  // Let the reveal scroll of the first match settle.
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 80));
    await _capture(tester);
  }

  // Jump through matches; each jump scrolls the active match into view.
  for (var jump = 0; jump < 4; jump++) {
    controller.next();
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 70));
      await _capture(tester);
    }
  }
}

/// The default test font renders every glyph as a box; load the SDK's
/// bundled Roboto and MaterialIcons so the captures look like a real app.
Future<void> _loadRealFonts(WidgetTester tester) async {
  await tester.runAsync(() async {
    final fonts = _materialFontsDir();
    Future<ByteData> read(String name) async =>
        ByteData.sublistView(await File('${fonts.path}/$name').readAsBytes());
    final roboto = FontLoader('Roboto')
      ..addFont(read('Roboto-Regular.ttf'))
      ..addFont(read('Roboto-Medium.ttf'))
      ..addFont(read('Roboto-Bold.ttf'));
    await roboto.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(read('MaterialIcons-Regular.otf'));
    await icons.load();
  });
}

Directory _materialFontsDir() {
  var dir = File(Platform.resolvedExecutable).parent;
  while (true) {
    final fonts = Directory('${dir.path}/bin/cache/artifacts/material_fonts');
    if (fonts.existsSync()) return fonts;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('material_fonts not found above $dir');
    }
    dir = parent;
  }
}

Future<void> _capture(WidgetTester tester) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
  final name = 'frame_${'$_frameIndex'.padLeft(3, '0')}.png';
  _frameIndex++;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('${_frameDir.path}/$name')
          .writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

class _DemoApp extends StatelessWidget {
  const _DemoApp({required this.controller});

  final FindInPageController controller;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF0EA5E9),
          fontFamily: 'Roboto',
        ),
        home: Scaffold(
          appBar: AppBar(title: const Text('Release notes')),
          body: FindInPageScope(
            controller: controller,
            child: const _Article(),
          ),
        ),
      ),
    );
  }
}

class _Article extends StatelessWidget {
  const _Article();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = theme.textTheme.titleLarge
        ?.copyWith(fontWeight: FontWeight.w600, height: 1.3);
    final body = theme.textTheme.bodyLarge?.copyWith(height: 1.55);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FindableText(
            'Weekly digest: rendering, tooling, and the road to 4.0',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          FindableText(
            'Published Tuesday - 6 min read',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          FindableText(
            'The rendering team landed a series of raster cache fixes this '
            'week. Scroll performance on older devices improves noticeably, '
            'and the Flutter engine now reuses shader programs across '
            'route transitions instead of recompiling them.',
            style: body,
          ),
          const SizedBox(height: 20),
          FindableText('Tooling', style: heading),
          const SizedBox(height: 8),
          FindableText(
            'DevTools gained a frame-by-frame timeline for jank hunting. '
            'Attach it to any profile build and every Flutter frame is '
            'broken down into build, layout, and paint costs, so a slow '
            'frame points straight at the widget that caused it.',
            style: body,
          ),
          const SizedBox(height: 20),
          FindableText('Packages', style: heading),
          const SizedBox(height: 8),
          FindableText(
            'The ecosystem keeps growing: this cycle alone, more than two '
            'hundred packages added support for the new platform view API. '
            'If your app embeds maps or video, check whether your plugin '
            'ships the updated flutter bindings before upgrading.',
            style: body,
          ),
          const SizedBox(height: 20),
          FindableText('Breaking changes', style: heading),
          const SizedBox(height: 8),
          FindableText(
            'A reminder that the legacy text scaling APIs are removed in '
            'the next release. Migrate to TextScaler now; a Flutter fix '
            'rule can rewrite most call sites automatically.',
            style: body,
          ),
          const SizedBox(height: 20),
          FindableText(
            'As always, file issues with a minimal reproduction. The '
            'triage bots label anything tagged with a Flutter version '
            'within a few hours, and small reproductions get fixed first.',
            style: body,
          ),
        ],
      ),
    );
  }
}
