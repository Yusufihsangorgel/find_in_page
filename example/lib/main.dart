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
  'This release also ships a raster-cache fix, so scroll performance on '
      'older devices improves without a widget-tree rewrite.',
];

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'find_in_page',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0EA5E9),
        useMaterial3: true,
      ),
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
  final _controller = FindInPageController();
  var _lazyList = false;

  @override
  void initState() {
    super.initState();
    // After the first layout so discovery can read the text Flutter
    // actually painted. The query is already in the bar; matches light
    // up without the visitor having to know Ctrl+F exists.
    WidgetsBinding.instance.addPostFrameCallback((_) => _searchForMode());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _searchForMode() {
    _controller.search(_lazyList ? 'row 1997' : 'release');
  }

  void _setLazyList(bool value) {
    if (value == _lazyList) return;
    setState(() => _lazyList = value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchForMode();
    });
  }

  @override
  Widget build(BuildContext context) {
    // The scope wraps the whole Scaffold, not just the body, so the AppBar
    // title is searchable too. Nothing in the AppBar was written for this
    // package; the scope reads the text Flutter renders inside it.
    return FindInPageScope(
      // A fresh scope per mode, so switching does not carry over the
      // other mode's matches.
      key: ValueKey(_lazyList),
      controller: _controller,
      // The demo keeps its own bar on screen. This callback still has to
      // exist so the web intercept takes Ctrl+F instead of leaving it to
      // the browser's empty find-on-canvas.
      showBar: false,
      onOpenRequested: () {},
      child: Scaffold(
        appBar: AppBar(
          title: Text(_lazyList ? '2,000-row list' : 'Release notes'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(64),
            child: ExcludeFromFind(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FindBar(
                    controller: _controller,
                    autofocus: false,
                    onClose: _controller.clearSearch,
                  ),
                ),
              ),
            ),
          ),
        ),
        body: _lazyList ? const _LazyListDemo() : const _UnwrappedPage(),
        bottomNavigationBar: ExcludeFromFind(
          child: NavigationBar(
            selectedIndex: _lazyList ? 1 : 0,
            onDestinationSelected: (index) => _setLazyList(index == 1),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.article_outlined),
                label: 'Page',
              ),
              NavigationDestination(
                icon: Icon(Icons.list),
                label: '2,000 rows',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stock Flutter widgets, none of them wrapped. The labels name the
/// widget class and are chrome, so they stay out of the search.
class _UnwrappedPage extends StatelessWidget {
  const _UnwrappedPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        const _SectionLabel('ListTile'),
        const Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.rocket_launch_outlined),
                title: Text('Release 4.0 rollout'),
                subtitle: Text('Staged to ten percent of users'),
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.bug_report_outlined),
                title: Text('Release 3.29 hotfix'),
                subtitle: Text('Nine issues waiting on a repro'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const _SectionLabel('DataTable'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 40,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 40,
              columns: const [
                DataColumn(label: Text('Channel')),
                DataColumn(label: Text('State')),
              ],
              rows: const [
                DataRow(
                  cells: [
                    DataCell(Text('stable')),
                    DataCell(Text('released')),
                  ],
                ),
                DataRow(
                  cells: [
                    DataCell(Text('beta')),
                    DataCell(Text('release candidate')),
                  ],
                ),
                DataRow(
                  cells: [
                    DataCell(Text('main')),
                    DataCell(Text('untagged')),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const _SectionLabel('Text.rich'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text.rich(
              TextSpan(
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                children: [
                  const TextSpan(
                    text: 'The legacy text scaling APIs go away in the next ',
                  ),
                  TextSpan(
                    text: 'release',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.5,
                    ),
                  ),
                  const TextSpan(
                      text: '. Migrate to TextScaler now; a fix '
                          'rule rewrites most call sites.'),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const _SectionLabel('FindableText'),
        FindableText(
          'The rendering team landed raster cache fixes this release. '
          'Scroll performance on older devices improves, and the engine '
          'reuses shader programs across route transitions instead of '
          'recompiling them.',
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
        ),
        const SizedBox(height: 16),
        FindableText(
          'DevTools gained a frame-by-frame timeline for jank hunting. '
          'Attach it to any profile build and every Flutter frame is '
          'broken down into build, layout, and paint costs.',
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return ExcludeFromFind(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 2,000 rows. A plain `ListView.builder` of `FindableText` would only ever
/// search the handful currently built, and the count would drift as items
/// scroll in and out; `FindableListView` registers every row's text up
/// front, so all 2,000 are searchable and the count stays put while
/// scrolling. Opening this tab searches "row 1997": it is found and
/// scrolled to even though it was never built.
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
    if (matches.isEmpty) {
      return Text(text, maxLines: 3, overflow: TextOverflow.ellipsis);
    }
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
      TextSpan(children: spans, style: DefaultTextStyle.of(context).style),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}
