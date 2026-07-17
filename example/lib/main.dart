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
      home: Scaffold(
        appBar: AppBar(title: const Text('find_in_page example')),
        body: FindInPageScope(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (var i = 0; i < 12; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: FindableText(_paragraphs[i % _paragraphs.length]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
