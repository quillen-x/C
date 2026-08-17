import 'package:flutter_test/flutter_test.dart';

import 'package:media_downloader/main.dart';

void main() {
  testWidgets('app boots', (tester) async {
    await tester.pumpWidget(const MediaDownloaderApp());
    await tester.pump();
    expect(find.byType(MediaDownloaderApp), findsOneWidget);
  });
}
