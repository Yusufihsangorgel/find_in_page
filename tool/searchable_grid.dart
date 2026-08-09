// Generates doc/searchable-grid.png, the "what is searchable" figure in the
// README and the pub.dev screenshot.
//
//   flutter test tool/searchable_grid.dart
//
// Nothing here draws a highlight. The four cells are stock Flutter widgets,
// the query is typed into the real FindBar, and every yellow box in the
// output was painted by HighlightOverlay during the capture. If discovery
// regresses, this figure goes blank instead of lying.
//
// It lives outside test/ on purpose: `flutter test` with no path only walks
// test/, so CI never spends time rendering documentation.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:find_in_page/find_in_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Logical size of the figure. Kept close to square because pub.dev fits the
/// screenshot into a 190x190 card thumbnail instead of cropping it. A wide
/// diagram arrives there as an unreadable strip.
const Size _figure = Size(820, 664);

/// Only Roboto and MaterialIcons are bundled with the SDK, and a test binding
/// draws every unresolved glyph as a filled box. Identifiers are therefore
/// styled as chips rather than set in a monospace face.
const TextStyle _identifier = TextStyle(
  fontFamily: 'Roboto',
  fontSize: 14,
  height: 1.0,
  fontWeight: FontWeight.w700,
  letterSpacing: 0.3,
  color: Color(0xFF0F172A),
  backgroundColor: Color(0xFFE2E8F0),
);

const _captureKey = ValueKey('searchable-grid');
const _query = 'release';
final _output = File('doc/searchable-grid.png');

void main() {
  testWidgets('renders the searchable-widgets figure', (tester) async {
    tester.view.physicalSize = _figure * 2.0;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    EditableText.debugDeterministicCursor = true;
    addTearDown(() => EditableText.debugDeterministicCursor = false);
    await _loadRealFonts(tester);

    final controller = FindInPageController();
    addTearDown(controller.dispose);

    // Tests paint a flat outline in place of shadows. The figure should show
    // the find bar's real elevation, so this is restored by hand rather than
    // by a teardown that would run after the capture.
    debugDisableShadows = false;
    try {
      await tester.pumpWidget(_Figure(controller: controller));
      await _openFindBar(tester);
      await tester.enterText(find.byType(TextField), _query);
      await tester.pumpAndSettle();

      // A blank figure is the failure this file exists to prevent.
      expect(controller.matchCount, greaterThan(0));
      expect(controller.activeMatchIndex, isNotNull);

      await _capture(tester);
    } finally {
      debugDisableShadows = true;
    }

    stdout.writeln('wrote ${_output.path}: '
        '${controller.matchCount} matches, ${_output.lengthSync()} bytes');
  });
}

Future<void> _openFindBar(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await _output.writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

/// The default test font draws every glyph as a box. Load the SDK's bundled
/// Roboto and MaterialIcons so the figure looks like a running app.
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

class _Figure extends StatelessWidget {
  const _Figure({required this.controller});

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
          useMaterial3: true,
        ),
        home: Scaffold(
          backgroundColor: const Color(0xFFF1F5F9),
          body: FindInPageScope(
            controller: controller,
            barAlignment: AlignmentDirectional.topCenter,
            child: const _Grid(),
          ),
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid();

  @override
  Widget build(BuildContext context) {
    return Padding(
      // The find bar floats over the top of the scope; leave it a lane.
      padding: const EdgeInsets.fromLTRB(24, 92, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          Expanded(
            child: Row(
              children: [
                Expanded(child: _Cell(label: 'AppBar', child: _AppBarCell())),
                SizedBox(width: 18),
                Expanded(child: _Cell(label: 'ListTile', child: _TileCell())),
              ],
            ),
          ),
          SizedBox(height: 18),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _Cell(label: 'DataTable', child: _TableCell())),
                SizedBox(width: 18),
                Expanded(child: _Cell(label: 'Text.rich', child: _RichCell())),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled card. The label names the widget class and is chrome rather than
/// content, so it stays out of the search the way an application keeps its
/// navigation out.
class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeFromFind(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 16, 0),
              child: Text(label, style: _identifier),
            ),
          ),
          Expanded(child: Center(child: child)),
        ],
      ),
    );
  }
}

class _AppBarCell extends StatelessWidget {
  const _AppBarCell();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 56,
              child: AppBar(
                automaticallyImplyLeading: false,
                title: const Text('Release notes'),
                titleTextStyle: const TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 19,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF0F172A),
                ),
                backgroundColor: const Color(0xFFE0F2FE),
                actions: const [
                  Icon(Icons.more_vert, color: Color(0xFF475569)),
                  SizedBox(width: 12),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Updated twelve minutes ago',
            style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}

class _TileCell extends StatelessWidget {
  const _TileCell();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(2, 0, 2, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.article_outlined, color: Color(0xFF0284C7)),
            title: Text('Release 4.0 rollout'),
            subtitle: Text('Staged to ten percent of users'),
          ),
          Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: Icon(Icons.bug_report_outlined, color: Color(0xFF94A3B8)),
            title: Text('Triage queue'),
            subtitle: Text('Nine issues waiting on a repro'),
          ),
        ],
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  const _TableCell();

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(fontWeight: FontWeight.w600, fontSize: 14);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      child: DataTable(
        headingRowHeight: 40,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 40,
        horizontalMargin: 0,
        columnSpacing: 24,
        columns: const [
          DataColumn(label: Text('Channel', style: head)),
          DataColumn(label: Text('State', style: head)),
        ],
        rows: const [
          DataRow(
              cells: [DataCell(Text('stable')), DataCell(Text('released'))]),
          DataRow(cells: [
            DataCell(Text('beta')),
            DataCell(Text('release candidate')),
          ]),
          DataRow(cells: [DataCell(Text('main')), DataCell(Text('untagged'))]),
        ],
      ),
    );
  }
}

class _RichCell extends StatelessWidget {
  const _RichCell();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Text.rich(
        TextSpan(
          style:
              TextStyle(fontSize: 16, height: 1.55, color: Color(0xFF1E293B)),
          children: [
            TextSpan(text: 'The legacy text scaling APIs go away in the next '),
            TextSpan(
              text: 'release',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: '. Migrate to '),
            TextSpan(text: 'TextScaler', style: _identifier),
            TextSpan(text: ' now; a fix rule rewrites most call sites.'),
          ],
        ),
      ),
    );
  }
}
