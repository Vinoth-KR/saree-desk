import 'package:aadav_saree_desk/core/age.dart';
import 'package:aadav_saree_desk/core/csv.dart';
import 'package:aadav_saree_desk/core/discount.dart';
import 'package:aadav_saree_desk/core/format.dart';
import 'package:aadav_saree_desk/core/search.dart';
import 'package:aadav_saree_desk/data/models.dart';
import 'package:aadav_saree_desk/features/inventory/inventory_filter.dart';
import 'package:aadav_saree_desk/features/sell/scan_screen.dart';
import 'package:flutter_test/flutter_test.dart';

Saree saree(String sku, String desc, int rupees,
        {String status = 'available', DateTime? receipt, String bill = 'B1'}) =>
    Saree(
      id: 'id-$sku',
      businessId: 'b',
      sku: sku,
      receiptDate: receipt ?? DateTime(2026, 1, 1),
      billIndex: bill,
      description: desc,
      imagePath: null,
      markedPricePaise: rupees * 100,
      status: status,
      indexedAt: DateTime(2026, 1, 2),
      soldAt: null,
    );

void main() {
  group('money parsing/formatting', () {
    test('parses rupees to paise without floats', () {
      expect(parseRupeesToPaise('2,499'), 249900);
      expect(parseRupeesToPaise('2499.5'), 249950);
      expect(parseRupeesToPaise('0.07'), 7);
      expect(parseRupeesToPaise('₹ 1,00,000'), 10000000);
    });
    test('rejects zero, negative, junk', () {
      expect(parseRupeesToPaise('0'), isNull);
      expect(parseRupeesToPaise('-5'), isNull);
      expect(parseRupeesToPaise('abc'), isNull);
      expect(parseRupeesToPaise(''), isNull);
      expect(parseRupeesToPaise('1.234'), isNull);
      expect(parseRupeesToPaise('0', allowZero: true), 0);
    });
    test('formats en-IN', () {
      expect(formatInr(249900), '₹2,499');
      expect(formatInr(10000000), '₹1,00,000');
      expect(formatInr(249950), '₹2,499.50');
    });
    test('percent to basis points', () {
      expect(parsePercentToBp('10'), 1000);
      expect(parsePercentToBp('7.5'), 750);
      expect(parsePercentToBp(''), 0);
      expect(parsePercentToBp('100'), 10000);
      expect(parsePercentToBp('100.01'), isNull);
      expect(parsePercentToBp('-1'), isNull);
      expect(formatBp(1000), '10%');
      expect(formatBp(750), '7.5%');
    });
  });

  group('sale totals', () {
    test('single item tagged 2499 sold 2199 -> discount 300', () {
      final t = computeSaleTotals(
          [const SaleLineInput(id: 'a', markedPaise: 249900, negotiatedPaise: 219900)], 0);
      expect(t.totalCollected, 219900);
      expect(t.totalDiscountVsTag, 30000);
    });
    test('two items with 10% collective discount stay consistent', () {
      final lines = [
        const SaleLineInput(id: 'a', markedPaise: 249900, negotiatedPaise: 249900),
        const SaleLineInput(id: 'b', markedPaise: 150000, negotiatedPaise: 140000),
      ];
      final t = computeSaleTotals(lines, 1000);
      expect(t.subtotalNegotiated, 389900);
      expect(t.orderDiscount, 38990);
      expect(t.totalCollected, 350910);
      final sumFinal = lines.fold<int>(0, (s, l) => s + t.finalFor(l));
      expect(sumFinal, t.totalCollected);
      expect(t.allocations.values.fold<int>(0, (a, b) => a + b), t.orderDiscount);
    });
    test('rounding remainder goes to the last item; sums always match', () {
      final lines = [
        const SaleLineInput(id: 'a', markedPaise: 10001, negotiatedPaise: 10001),
        const SaleLineInput(id: 'b', markedPaise: 10001, negotiatedPaise: 10001),
        const SaleLineInput(id: 'c', markedPaise: 10001, negotiatedPaise: 10001),
      ];
      for (final bp in [1, 333, 1000, 1234, 9999, 10000]) {
        final t = computeSaleTotals(lines, bp);
        expect(lines.fold<int>(0, (s, l) => s + t.finalFor(l)), t.totalCollected, reason: 'bp=$bp');
        for (final l in lines) {
          expect(t.finalFor(l), greaterThanOrEqualTo(0));
        }
      }
    });
    test('100% discount gives zero collected, never negative', () {
      final t = computeSaleTotals(
          [const SaleLineInput(id: 'a', markedPaise: 5000, negotiatedPaise: 5000)], 10000);
      expect(t.totalCollected, 0);
    });
  });

  group('search', () {
    final a = saree('SR-0001', 'Blue soft-silk floral border', 2499);
    final b = saree('SR-0012', 'Red Kanchipuram silk', 12000);
    test('empty matches everything', () => expect(matchesQuery(a, ''), isTrue));
    test('SKU prefix and bare number', () {
      expect(matchesQuery(a, 'sr-0001'), isTrue);
      expect(matchesQuery(b, 'SR-001'), isTrue);
      expect(matchesQuery(a, '0012'), isFalse);
    });
    test('description case-insensitive, all words', () {
      expect(matchesQuery(a, 'BLUE silk'), isTrue);
      expect(matchesQuery(a, 'blue kanchipuram'), isFalse);
    });
    test('exact price and range', () {
      expect(matchesQuery(a, '2499'), isTrue);
      expect(matchesQuery(b, '2499'), isFalse);
      expect(matchesQuery(a, '2000-3000'), isTrue);
      expect(matchesQuery(b, '2000..3000'), isFalse);
      expect(matchesQuery(b, '3000-2000'), isFalse);
      expect(matchesQuery(b, '10000-15000'), isTrue);
    });
  });

  group('age and csv', () {
    test('age is driven by receipt date', () {
      final now = DateTime(2026, 10, 31);
      expect(ageInDays(DateTime(2026, 10, 1), now: now), 30);
      expect(ageInDays(DateTime(2026, 8, 2), now: now), 90);
      expect(ageInDays(DateTime(2026, 7, 1), now: now), greaterThan(90));
    });
    test('csv escapes commas, quotes, newlines', () {
      expect(csvEscape('a,b'), '"a,b"');
      expect(csvEscape('say "hi"'), '"say ""hi"""');
      expect(toCsv(['x', 'y'], [['1', 'a,b']]), 'x,y\r\n1,"a,b"\r\n');
    });
    test('paise to decimal', () {
      expect(paiseToDecimal(249900), '2499.00');
      expect(paiseToDecimal(7), '0.07');
    });
  });

  group('search: bill index and receipt date', () {
    final a = saree('SR-0001', 'Blue silk', 2499, bill: 'WB-77', receipt: DateTime(2026, 10, 12));
    final b = saree('SR-0002', 'Red cotton', 999, bill: 'WB-78', receipt: DateTime(2026, 3, 5));
    test('bill index', () {
      expect(matchesQuery(a, 'wb-77'), isTrue);
      expect(matchesQuery(b, 'wb-77'), isFalse);
      expect(matchesQuery(a, 'WB'), isTrue);
    });
    test('receipt date in several typed formats', () {
      for (final q in ['2026-10-12', '12-10-2026', '12/10/2026', '12 oct 2026', '12 oct', 'oct', 'october', 'oct 2026']) {
        expect(matchesQuery(a, q), isTrue, reason: q);
        expect(matchesQuery(b, q), isFalse, reason: q);
      }
      expect(matchesQuery(b, 'march'), isTrue);
      expect(matchesQuery(b, '05/03/2026'), isTrue);
    });
    test('words can combine description and date or bill', () {
      expect(matchesQuery(a, 'blue oct'), isTrue);
      expect(matchesQuery(a, 'blue wb-77'), isTrue);
      expect(matchesQuery(b, 'blue oct'), isFalse);
    });
    test('price range still works and does not break', () {
      expect(matchesQuery(a, '2000-3000'), isTrue);
      expect(matchesQuery(b, '2000-3000'), isFalse);
    });
  });

  group('age buckets', () {
    test('boundaries', () {
      expect(ageBucketIndex(0), 0);
      expect(ageBucketIndex(30), 0);
      expect(ageBucketIndex(31), 1);
      expect(ageBucketIndex(60), 1);
      expect(ageBucketIndex(61), 2);
      expect(ageBucketIndex(90), 2);
      expect(ageBucketIndex(91), 3);
      expect(ageBucketIndex(500), 3);
      expect(ageBucketIndex(-3), 0);
    });
  });

  group('inventory filter and sort', () {
    final now = DateTime(2026, 10, 31);
    final fresh = saree('SR-0001', 'fresh', 1000, receipt: DateTime(2026, 10, 20), bill: 'A');
    final mid = saree('SR-0002', 'mid', 3000, receipt: DateTime(2026, 9, 10), bill: 'B');
    final old = saree('SR-0003', 'old', 2000, receipt: DateTime(2026, 5, 1), bill: 'a', status: 'sold');
    final all = [fresh, mid, old];

    List<String> run(InventoryFilter f) => all.where((s) => f.accepts(s, now: now)).map((s) => s.sku).toList();

    test('status', () {
      expect(run(const InventoryFilter()), ['SR-0001', 'SR-0002']);
      expect(run(const InventoryFilter(status: StockStatus.sold)), ['SR-0003']);
      expect(run(const InventoryFilter(status: StockStatus.all)).length, 3);
    });
    test('age bucket from receipt date', () {
      expect(run(const InventoryFilter(status: StockStatus.all).copyWith(age: ageBuckets[0])), ['SR-0001']);
      expect(run(const InventoryFilter(status: StockStatus.all).copyWith(age: ageBuckets[1])), ['SR-0002']);
      expect(run(const InventoryFilter(status: StockStatus.all).copyWith(age: ageBuckets[3])), ['SR-0003']);
    });
    test('receipt date range is inclusive', () {
      final f = const InventoryFilter(status: StockStatus.all)
          .copyWith(receiptFrom: DateTime(2026, 9, 10), receiptTo: DateTime(2026, 10, 20));
      expect(run(f), ['SR-0001', 'SR-0002']);
    });
    test('bill index is case-insensitive exact', () {
      expect(run(const InventoryFilter(status: StockStatus.all).copyWith(billIndex: 'A')), ['SR-0001', 'SR-0003']);
    });
    test('price range', () {
      final f = const InventoryFilter(status: StockStatus.all).copyWith(minPaise: 150000, maxPaise: 250000);
      expect(run(f), ['SR-0003']);
    });
    test('active extra filter count and clearing', () {
      var f = const InventoryFilter().copyWith(age: ageBuckets[0], billIndex: 'A', minPaise: 1);
      expect(f.activeExtraFilters, 3);
      f = f.copyWith(clearAge: true, clearBill: true, clearPrice: true);
      expect(f.activeExtraFilters, 0);
    });
    test('sorting', () {
      List<String> sorted(InventorySort s) => ([...all]..sort(s.compare)).map((x) => x.sku).toList();
      expect(sorted(InventorySort.priceHigh), ['SR-0002', 'SR-0003', 'SR-0001']);
      expect(sorted(InventorySort.priceLow), ['SR-0001', 'SR-0003', 'SR-0002']);
      expect(sorted(InventorySort.receiptOldest), ['SR-0003', 'SR-0002', 'SR-0001']);
      expect(sorted(InventorySort.receiptNewest), ['SR-0001', 'SR-0002', 'SR-0003']);
      expect(sorted(InventorySort.skuDesc), ['SR-0003', 'SR-0002', 'SR-0001']);
    });
  });

  test('bp to text round trips', () {
    expect(bpToText(0), '');
    expect(bpToText(1000), '10');
    expect(bpToText(750), '7.5');
    expect(bpToText(1234), '12.34');
    for (final bp in [1, 50, 750, 1000, 1234, 10000]) {
      expect(parsePercentToBp(bpToText(bp)), bp);
    }
  });

  group('scan lookup', () {
    final a = saree('SR-0001', 'one', 1000);
    final b = saree('SR-0002', 'two', 2000, status: 'sold');
    final all = [a, b];
    test('adds an available saree by exact SKU, ignoring case and spaces', () {
      final r = resolveScan(' sr-0001 ', all, {});
      expect(r.outcome, ScanOutcome.added);
      expect(r.saree, a);
    });
    test('reports already in cart, sold and unknown codes', () {
      expect(resolveScan('SR-0001', all, {a.id}).outcome, ScanOutcome.alreadyInCart);
      expect(resolveScan('SR-0002', all, {}).outcome, ScanOutcome.sold);
      expect(resolveScan('SR-9999', all, {}).outcome, ScanOutcome.notFound);
      expect(resolveScan('https://example.com/SR-0001', all, {}).outcome, ScanOutcome.notFound);
    });
  });
}
