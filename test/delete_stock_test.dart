import 'package:aadav_saree_desk/data/models.dart';
import 'package:aadav_saree_desk/data/providers.dart';
import 'package:aadav_saree_desk/data/repository.dart';
import 'package:aadav_saree_desk/features/inventory/delete_rules.dart';
import 'package:aadav_saree_desk/features/inventory/saree_detail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

Saree _saree(String sku, {String status = 'available'}) => Saree(
      id: 'id-$sku',
      businessId: 'b',
      sku: sku,
      receiptDate: DateTime(2026, 10, 1),
      billIndex: 'B1',
      description: 'desc $sku',
      imagePath: null,
      markedPricePaise: 100000,
      status: status,
      indexedAt: DateTime(2026, 10, 2),
      soldAt: null,
    );

Sale _sale(String status, String sareeSku, {String? number, String customer = 'Asha'}) => Sale(
      id: 'sale-$status-$sareeSku',
      saleNumber: number,
      customerName: customer,
      status: status,
      createdAt: DateTime(2026, 10, 3),
      confirmedAt: status == 'draft' ? null : DateTime(2026, 10, 3),
      totalMarkedPaise: 100000,
      subtotalNegotiatedPaise: 100000,
      discountBp: 0,
      orderDiscountPaise: 0,
      totalCollectedPaise: 100000,
      voidReason: status == 'void' ? 'test' : null,
      voidedAt: null,
      items: [
        SaleItem(
          sareeId: 'id-$sareeSku',
          sku: sareeSku,
          description: 'desc $sareeSku',
          imagePath: null,
          markedPaise: 100000,
          negotiatedPaise: 100000,
          allocatedDiscountPaise: 0,
          finalPaise: 100000,
        ),
      ],
    );

class _FakeRepo implements Repository {
  final deleted = <String>[];
  Object? failWith;

  @override
  Future<void> deleteSaree(String sareeId) async {
    if (failWith != null) throw failWith!;
    deleted.add(sareeId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('deleteBlocker (mirrors the database rule)', () {
    test('free saree: nothing blocks it', () {
      expect(deleteBlocker('id-SR-0001', [_sale('confirmed', 'SR-0002')]), isNull);
      expect(deleteBlocker('id-SR-0001', const []), isNull);
    });
    test('confirmed and void sales are permanent history', () {
      final b = deleteBlocker('id-SR-0001', [_sale('confirmed', 'SR-0001', number: 'SD-2026-000001')]);
      expect(b, isNotNull);
      expect(b!.isDraft, isFalse);
      expect(deleteBlocker('id-SR-0001', [_sale('void', 'SR-0001')])!.isDraft, isFalse);
    });
    test('a draft blocks only until it is discarded', () {
      expect(deleteBlocker('id-SR-0001', [_sale('draft', 'SR-0001')])!.isDraft, isTrue);
    });
    test('real history is reported ahead of a draft', () {
      final b = deleteBlocker('id-SR-0001', [
        _sale('draft', 'SR-0001'),
        _sale('confirmed', 'SR-0001', number: 'SD-2026-000007'),
      ]);
      expect(b!.isDraft, isFalse);
      expect(b.sale.saleNumber, 'SD-2026-000007');
    });
  });

  group('Delete stock on the detail screen', () {
    late _FakeRepo repo;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      repo = _FakeRepo();
    });

    Future<GoRouter> pump(WidgetTester tester,
        {required String role, required List<Saree> sarees, List<Sale> sales = const []}) async {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        initialLocation: '/inventory',
        routes: [
          GoRoute(path: '/inventory', builder: (_, _) => const Scaffold(body: Text('INVENTORY PAGE'))),
          GoRoute(path: '/sell', builder: (_, _) => const Scaffold(body: Text('SELL PAGE'))),
          GoRoute(path: '/saree/:id', builder: (_, s) => SareeDetailScreen(id: s.pathParameters['id']!)),
        ],
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          repoProvider.overrideWithValue(repo),
          membershipProvider.overrideWith(
            (ref) async => Membership(businessId: 'b', role: role, businessName: 'Test Shop'),
          ),
          sareesProvider.overrideWith((ref) async => sarees),
          salesProvider.overrideWith((ref) async => sales),
        ],
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();
      router.push('/saree/${sarees.first.id}');
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('never-sold saree: confirm deletes it and returns to the list', (tester) async {
      await pump(tester, role: 'editor', sarees: [_saree('SR-0001')]);
      expect(find.text('Delete stock'), findsOneWidget);

      await tester.tap(find.text('Delete stock'));
      await tester.pumpAndSettle();
      expect(find.text('Delete SR-0001?'), findsOneWidget);
      expect(repo.deleted, isEmpty, reason: 'nothing is deleted before the user confirms');

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(repo.deleted, ['id-SR-0001']);
      expect(find.text('INVENTORY PAGE'), findsOneWidget, reason: 'goes back to the list');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Cancel in the confirmation deletes nothing', (tester) async {
      await pump(tester, role: 'owner', sarees: [_saree('SR-0001')]);
      await tester.tap(find.text('Delete stock'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.deleted, isEmpty);
      expect(find.text('Delete stock'), findsOneWidget, reason: 'still on the detail screen');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a server refusal is shown and the screen stays usable', (tester) async {
      repo.failWith = AppException('SR-0001 is part of sales history (SD-2026-000001). Sales history is kept.');
      await pump(tester, role: 'owner', sarees: [_saree('SR-0001')]);
      await tester.tap(find.text('Delete stock'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.textContaining('part of sales history'), findsOneWidget);
      expect(find.text('Delete stock'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a saree with sales history shows why it cannot be deleted, with no button', (tester) async {
      await pump(tester,
          role: 'owner',
          sarees: [_saree('SR-0001')],
          sales: [_sale('void', 'SR-0001', number: 'SD-2026-000003')]);
      expect(find.text('Delete stock'), findsNothing);
      expect(find.textContaining('part of sales history (SD-2026-000003)'), findsOneWidget);
    });

    testWidgets('a saree in a draft says to discard the draft first', (tester) async {
      await pump(tester, role: 'owner', sarees: [_saree('SR-0001')], sales: [_sale('draft', 'SR-0001')]);
      expect(find.text('Delete stock'), findsNothing);
      expect(find.textContaining('draft sale for Asha'), findsOneWidget);
    });

    testWidgets('a sold saree cannot be deleted', (tester) async {
      await pump(tester, role: 'owner', sarees: [_saree('SR-0001', status: 'sold')]);
      expect(find.text('Delete stock'), findsNothing);
      expect(find.textContaining('cannot be deleted'), findsOneWidget);
    });

    testWidgets('a viewer sees no delete controls at all', (tester) async {
      await pump(tester, role: 'viewer', sarees: [_saree('SR-0001')]);
      expect(find.text('Delete stock'), findsNothing);
      expect(find.textContaining('cannot be deleted'), findsNothing);
    });
  });
}
