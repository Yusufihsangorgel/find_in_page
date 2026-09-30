// The "after" example of doc/migrating-from-substring_highlight.md.
//
// Run it with `flutter run -t lib/migrating_from_substring_highlight.dart`
// from the example directory.
import 'package:find_in_page/find_in_page.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(home: TrackSearchPage()));

const _tracks = [
  'Blue in Green',
  'Green Onions',
  'Greensleeves',
  'Kind of Blue',
  'Mood Indigo',
  'Take Five',
  'Watermelon Man',
  'So What',
];

class TrackSearchPage extends StatefulWidget {
  const TrackSearchPage({super.key});

  @override
  State<TrackSearchPage> createState() => _TrackSearchPageState();
}

class _TrackSearchPageState extends State<TrackSearchPage> {
  // The page owns this controller and disposes it.
  final _find = FindInPageController();

  @override
  void dispose() {
    _find.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FindInPageScope(
      controller: _find,
      // Your own TextField is the search box. The built-in bar stays off.
      showBar: false,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // Chrome stays out of the search. Without this, the counter
              // below could match the query it reports on.
              ExcludeFromFind(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: 'Search tracks',
                          ),
                          // The term now lives on the controller, not on
                          // each row.
                          onChanged: _find.search,
                        ),
                      ),
                      ListenableBuilder(
                        listenable: _find,
                        builder: (context, _) {
                          final active = _find.activeMatchIndex;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              active == null
                                  ? '0'
                                  : '${active + 1}/${_find.matchCount}',
                            ),
                          );
                        },
                      ),
                      IconButton(
                        tooltip: 'Previous match',
                        icon: const Icon(Icons.keyboard_arrow_up),
                        onPressed: _find.previous,
                      ),
                      IconButton(
                        tooltip: 'Next match',
                        icon: const Icon(Icons.keyboard_arrow_down),
                        onPressed: _find.next,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final title in _tracks)
                      ListTile(
                        title: FindableText(
                          title,
                          style: const TextStyle(color: Colors.grey),
                          highlightColor: const Color(0xFFFFF59D),
                          activeHighlightColor: const Color(0xFFFFB74D),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
