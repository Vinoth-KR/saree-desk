import 'package:aadav_saree_desk/features/sales/sale_detail.dart';
import 'package:aadav_saree_desk/features/tools/team_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens [dialog] from a button and returns whatever it pops with.
Future<void> openDialog<T>(WidgetTester tester, Widget dialog, void Function(T?) onResult) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async => onResult(await showDialog<T>(context: context, builder: (_) => dialog)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('Add person dialog', () {
    testWidgets('Cancel closes cleanly (no disposed-controller assertion)', (tester) async {
      Object? result = 'unset';
      await openDialog<({String email, String role})>(tester, const AddMemberDialog(), (r) => result = r);
      await tester.enterText(find.byType(TextField), 'someone@example.com');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AddMemberDialog), findsNothing);
      expect(result, isNull);
    });

    testWidgets('Add with an invalid email shows an error and stays open', (tester) async {
      await openDialog<({String email, String role})>(tester, const AddMemberDialog(), (_) {});
      await tester.enterText(find.byType(TextField), 'not-an-email');
      await tester.tap(find.text('Add'));
      await tester.pump();
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(find.byType(AddMemberDialog), findsOneWidget);
    });

    testWidgets('Add with a valid email returns the email and chosen role', (tester) async {
      ({String email, String role})? result;
      await openDialog<({String email, String role})>(tester, const AddMemberDialog(), (r) => result = r);
      await tester.enterText(find.byType(TextField), '  Spouse@Example.com ');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(result?.email, 'Spouse@Example.com');
      expect(result?.role, 'editor');
    });

    testWidgets('Back button (system pop) also closes cleanly', (tester) async {
      await openDialog<({String email, String role})>(tester, const AddMemberDialog(), (_) {});
      // Simulates the Android system back button (pageBack looks for an AppBar back button).
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AddMemberDialog), findsNothing);
    });
  });

  group('Void reason dialog', () {
    testWidgets('empty reason is rejected inline, dialog stays open', (tester) async {
      await openDialog<String>(tester, const VoidReasonDialog(itemCount: 2), (_) {});
      await tester.tap(find.text('Void sale'));
      await tester.pump();
      expect(find.text('A reason is required to void a sale'), findsOneWidget);
      expect(find.byType(VoidReasonDialog), findsOneWidget);
    });

    testWidgets('returns the trimmed reason; Cancel returns null without errors', (tester) async {
      String? result;
      await openDialog<String>(tester, const VoidReasonDialog(itemCount: 1), (r) => result = r);
      await tester.enterText(find.byType(TextField), '  wrong item  ');
      await tester.tap(find.text('Void sale'));
      await tester.pumpAndSettle();
      expect(result, 'wrong item');

      result = 'unset';
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(result, isNull);
    });
  });
}
