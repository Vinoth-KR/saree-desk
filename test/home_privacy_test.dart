import 'package:aadav_saree_desk/core/privacy.dart';
import 'package:aadav_saree_desk/data/models.dart';
import 'package:aadav_saree_desk/data/providers.dart';
import 'package:aadav_saree_desk/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Saree _saree(String sku, int rupees, {String status = 'available'}) => Saree(
      id: 'id-$sku',
      businessId: 'b',
      sku: sku,
      receiptDate: DateTime.now().subtract(const Duration(days: 5)),
      billIndex: 'B1',
      description: 'desc $sku',
      imagePath: null,
      markedPricePaise: rupees * 100,
      status: status,
      indexedAt: DateTime.now(),
      soldAt: null,
    );

/// Tagged INR 2,499, sold for INR 2,199 (discount INR 300).
Sale _sale() => Sale(
      id: 'sale-1',
      saleNumber: 'SD-2026-000001',
      customerName: 'Asha',
      status: 'confirmed',
      createdAt: DateTime.now(),
      confirmedAt: DateTime.now(),
      totalMarkedPaise: 249900,
      subtotalNegotiatedPaise: 219900,
      discountBp: 0,
      orderDiscountPaise: 0,
      totalCollectedPaise: 219900,
      voidReason: null,
      voidedAt: null,
      items: [
        SaleItem(
          sareeId: 'id-SR-0003',
          sku: 'SR-0003',
          description: 'desc SR-0003',
          imagePath: null,
          markedPaise: 249900,
          negotiatedPaise: 219900,
          allocatedDiscountPaise: 0,
          finalPaise: 219900,
        ),
      ],
    );

Future<void> _pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      membershipProvider.overrideWith(
        (ref) async => Membership(businessId: 'b', role: 'owner', businessName: 'Test Shop'),
      ),
      sareesProvider.overrideWith(
        (ref) async => [_saree('SR-0001', 1000), _saree('SR-0002', 2000), _saree('SR-0003', 2499, status: 'sold')],
      ),
      salesProvider.overrideWith((ref) async => [_sale()]),
    ],
    child: const MaterialApp(home: HomeScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('amount masking helper', () {
    test('masks or formats', () {
      expect(amountText(249900, hide: true), hiddenAmountText);
      expect(amountText(249900, hide: false), '₹2,499');
      expect(hiddenAmountText.contains(RegExp(r'\d')), isFalse, reason: 'the mask must not leak digits');
    });

    test('amounts are hidden by default and toggle on and off', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(hideAmountsProvider), isTrue);
      c.read(hideAmountsProvider.notifier).toggle();
      expect(c.read(hideAmountsProvider), isFalse);
      c.read(hideAmountsProvider.notifier).toggle();
      expect(c.read(hideAmountsProvider), isTrue);
    });
  });

  group('dashboard', () {
    testWidgets('shows no rupee amounts by default, but still shows counts', (tester) async {
      await _pumpHome(tester);

      // Counts and labels stay visible.
      expect(find.text('Total indexed'), findsOneWidget);
      expect(find.text('Stock at tag price'), findsOneWidget);
      expect(find.text('Collected'), findsOneWidget);

      // No rupee figure anywhere: stock value, collected, discount, average, recent sale, customer total.
      expect(find.textContaining('3,000'), findsNothing);
      expect(find.textContaining('2,199'), findsNothing);
      expect(find.textContaining('2,499'), findsNothing);
      expect(find.textContaining('₹300'), findsNothing);
      expect(find.textContaining('300'), findsNothing);
      expect(find.text(hiddenAmountText), findsWidgets);
      expect(find.byTooltip('Show amounts'), findsOneWidget);
    });

    testWidgets('the eye button reveals every amount, and hides them again', (tester) async {
      await _pumpHome(tester);

      await tester.tap(find.byTooltip('Show amounts'));
      await tester.pumpAndSettle();
      expect(find.text(hiddenAmountText), findsNothing);
      expect(find.text('₹3,000'), findsOneWidget, reason: 'stock at tag price tile');
      expect(find.text('₹2,199'), findsWidgets, reason: 'collected, average, recent sale and customer total');
      expect(find.textContaining('300'), findsWidgets, reason: 'discount tile and recent sale discount');
      expect(find.byTooltip('Hide amounts'), findsOneWidget);

      await tester.tap(find.byTooltip('Hide amounts'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2,199'), findsNothing);
      expect(find.text(hiddenAmountText), findsWidgets);
    });

    testWidgets('has 30-day and 7-day ranges', (tester) async {
      await _pumpHome(tester);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('7 days'), findsOneWidget);
      expect(find.text('30 days'), findsOneWidget);
      expect(find.text('All time'), findsOneWidget);
    });
  });
}
