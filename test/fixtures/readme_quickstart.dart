import 'package:find_in_page/find_in_page.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(
    const MaterialApp(
      home: FindInPageScope(
        child: Scaffold(
          body: Column(
            children: [
              Text('The first plain text match.'),
              Text('The second plain text match.'),
            ],
          ),
        ),
      ),
    ),
  );
}
