import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:retinexa/app_web.dart';

void main() {
  testWidgets('app boot smoke test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    dotenv.loadFromString(
      envString: 'API_BASE=http://localhost:8000\nTIMEOUT_MS=90000',
    );

    await tester.pumpWidget(const WebApp());
    await tester.pump();

    expect(find.text('MA Retinal Simulator'), findsOneWidget);
  });
}
