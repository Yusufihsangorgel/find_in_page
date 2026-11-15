// Reads the package sources from disk, which needs dart:io. The widget
// tests in find_bar_test.dart stay free of it and also run in a browser.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no file under lib/ imports Material, Cupertino or material_ui', () {
    final directive = RegExp(
      r'''^\s*(import|export)\s+['"][^'"]*'''
      r'''(material\.dart|cupertino\.dart|material_ui|/src/(material|cupertino)/)''',
      multiLine: true,
    );
    // The guard has to be able to fail, or a pass means nothing.
    expect(
      directive.hasMatch("import 'package:flutter/material.dart';"),
      isTrue,
    );
    expect(
      directive.hasMatch("import 'package:material_ui/material_ui.dart';"),
      isTrue,
    );
    expect(
      directive.hasMatch("export 'package:flutter/cupertino.dart' show X;"),
      isTrue,
    );
    expect(
      directive.hasMatch("import 'package:flutter/src/material/colors.dart';"),
      isTrue,
    );
    expect(
      directive.hasMatch(
        "import 'package:flutter/src/cupertino/colors.dart' show X;",
      ),
      isTrue,
    );
    expect(
      directive.hasMatch("import 'package:flutter/widgets.dart';"),
      isFalse,
    );
    expect(
      directive.hasMatch("import 'package:flutter/src/widgets/basic.dart';"),
      isFalse,
    );

    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
    expect(files.length, greaterThanOrEqualTo(15));
    final offenders = [
      for (final file in files)
        if (directive.hasMatch(file.readAsStringSync())) file.path,
    ];
    expect(offenders, isEmpty);
  });
}
