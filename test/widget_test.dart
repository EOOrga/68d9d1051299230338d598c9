import 'package:ass_gestion_base/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('opens the operational register from bottom navigation', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp(screenshotMode: false));
    await tester.pumpAndSettle();

    expect(find.text('Tableau de bord'), findsOneWidget);

    await tester.tap(find.text('Dossiers'));
    await tester.pumpAndSettle();

    expect(find.text('Registre opérationnel'), findsOneWidget);
  });

  testWidgets('creates a local operations record', (tester) async {
    await tester.pumpWidget(const MyApp(screenshotMode: false));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('new-record')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('field-title')),
      'Projecteur mobile',
    );
    await tester.enterText(
      find.byKey(const Key('field-reference')),
      'ACT-3001',
    );
    await tester.enterText(
      find.byKey(const Key('field-location')),
      'Salle polyvalente',
    );
    await tester.enterText(find.byKey(const Key('field-owner')), 'Accueil');
    await tester.enterText(
      find.byKey(const Key('field-due-date')),
      '20/05/2026',
    );
    await tester.enterText(
      find.byKey(const Key('field-notes')),
      'À placer avec les câbles HDMI.',
    );

    await tester.ensureVisible(find.byKey(const Key('save-record')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-record')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dossiers'));
    await tester.pumpAndSettle();

    expect(find.text('Projecteur mobile'), findsOneWidget);
    expect(find.text('ACT-3001 • Salle polyvalente'), findsOneWidget);
  });
}
