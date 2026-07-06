import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:tilawah_app/core/storage/hive_storage.dart';
import 'package:tilawah_app/main.dart';

void main() {
  setUpAll(() async {
    final tempDir = Directory.systemTemp.createTempSync('tilawah_test');
    Hive.init(tempDir.path);
    final settingsBox = await Hive.openBox('settings');
    final bookmarksBox = await Hive.openBox('bookmarks');
    final historyBox = await Hive.openBox('history');
    HiveStorage.initializeTest(
      settingsBox: settingsBox,
      bookmarksBox: bookmarksBox,
      historyBox: historyBox,
    );
  });

  testWidgets('TilawahApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: TilawahApp()));
    expect(find.byType(MaterialApp), findsOneWidget);
    
    // Allow the 3-second splash timer to fire and clean up
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
