import 'package:find_in_page/find_in_page.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ExampleApp());

const _paragraphs = [
  'Flutter is an open source framework for building beautiful, natively '
      'compiled, multi-platform applications from a single codebase.',
  'Widgets are the building blocks of a Flutter app. Everything is a '
      'widget: layout models, text, buttons, and the app itself.',
  'Hot reload helps you quickly and easily experiment, build UIs, add '
      'features, and fix bugs faster.',
  'Dart is a client-optimized language for fast apps on any platform. '
      'Flutter apps are written in Dart.',
  'This example page is intentionally long. Press Ctrl+F (Cmd+F on '
      'macOS) and search for "widget", "flutter", or "fast" to see '
      'matches highlighted and the page scroll to each one.',
];

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'find_in_page example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: const _ExampleHome(),
    );
  }
}

class _ExampleHome extends StatefulWidget {
  const _ExampleHome();

  @override
  State<_ExampleHome> createState() => _ExampleHomeState();
}

class _ExampleHomeState extends State<_ExampleHome> {
  var _lazyList = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('find_in_page example'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: TextButton(
                onPressed: () => setState(() => _lazyList = !_lazyList),
                child: Text(_lazyList ? 'Show short page' : 'Show lazy list'),
              ),
            ),
          ),
        ],
      ),
      body: FindInPageScope(
        // A fresh scope per mode, so switching does not carry over the
        // other mode's matches.
        key: ValueKey(_lazyList),
        child: _lazyList ? const _LazyListDemo() : const _ShortPageDemo(),
      ),
    );
  }
}

/// Short, eager content: everything is built at once, so plain
/// `FindableText` already searches all of it.
class _ShortPageDemo extends StatelessWidget {
  const _ShortPageDemo();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (var i = 0; i < 12; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: FindableText(_paragraphs[i % _paragraphs.length]),
          ),
      ],
    );
  }
}

/// 2,000 rows. A plain `ListView.builder` of `FindableText` would only ever
/// search the handful currently built, and the count would drift as items
/// scroll in and out; `FindableListView` registers every row's text up
/// front, so all 2,000 are searchable and the count stays put while
/// scrolling. Try searching "row 1997": it is found and scrolled to even
/// though it was never built.
class _LazyListDemo extends StatelessWidget {
  const _LazyListDemo();

  static final rows = [
    for (var i = 0; i < 2000; i++)
      'Row $i: ${_paragraphs[i % _paragraphs.length]}',
  ];

  @override
  Widget build(BuildContext context) {
    return FindableListView(
      itemCount: rows.length,
      itemExtent: 88,
      findableTextOf: (index) => rows[index],
      itemBuilder: (context, index, matches, activeMatchIndex) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: _HighlightedRow(
          text: rows[index],
          matches: matches,
          activeMatchIndex: activeMatchIndex,
        ),
      ),
    );
  }
}

/// Renders one lazy-list row's text with its matches highlighted. Building
/// this by hand (instead of using `FindableText`) is the cost of
/// `FindableListView`: it hands over match offsets, not rendered spans.
class _HighlightedRow extends StatelessWidget {
  const _HighlightedRow({
    required this.text,
    required this.matches,
    required this.activeMatchIndex,
  });

  final String text;
  final List<FindMatch> matches;
  final int? activeMatchIndex;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) return Text(text);
    final spans = <TextSpan>[];
    var cursor = 0;
    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      spans.add(TextSpan(
        text: text.substring(match.start, match.end),
        style: TextStyle(
          backgroundColor: i == activeMatchIndex
              ? const Color(0xFFFFB74D)
              : const Color(0xFFFFF59D),
        ),
      ));
      cursor = match.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return Text.rich(
        TextSpan(children: spans, style: DefaultTextStyle.of(context).style));
  }
}
