import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/age.dart';
import '../../core/format.dart';
import '../../data/models.dart';

enum StockStatus { available, sold, all }

enum InventorySort {
  newestIndexed('Newest indexed'),
  oldestIndexed('Oldest indexed'),
  receiptNewest('Receipt date: newest first'),
  receiptOldest('Receipt date: oldest first (oldest stock)'),
  priceHigh('Price: high to low'),
  priceLow('Price: low to high'),
  skuAsc('SKU: A to Z'),
  skuDesc('SKU: Z to A'),
  billIndex('Bill index');

  const InventorySort(this.label);
  final String label;

  int compare(Saree a, Saree b) => switch (this) {
        InventorySort.newestIndexed => b.indexedAt.compareTo(a.indexedAt),
        InventorySort.oldestIndexed => a.indexedAt.compareTo(b.indexedAt),
        InventorySort.receiptNewest => b.receiptDate.compareTo(a.receiptDate),
        InventorySort.receiptOldest => a.receiptDate.compareTo(b.receiptDate),
        InventorySort.priceHigh => b.markedPricePaise.compareTo(a.markedPricePaise),
        InventorySort.priceLow => a.markedPricePaise.compareTo(b.markedPricePaise),
        InventorySort.skuAsc => a.sku.compareTo(b.sku),
        InventorySort.skuDesc => b.sku.compareTo(a.sku),
        InventorySort.billIndex => a.billIndex.toLowerCase().compareTo(b.billIndex.toLowerCase()),
      };
}

/// Filter and sort state for the Stock tab. Lives in a provider so the dashboard can open the
/// inventory already filtered (status and/or age bucket from receipt date).
class InventoryFilter {
  const InventoryFilter({
    this.status = StockStatus.available,
    this.age,
    this.receiptFrom,
    this.receiptTo,
    this.billIndex,
    this.minPaise,
    this.maxPaise,
    this.sort = InventorySort.newestIndexed,
  });

  final StockStatus status;
  final AgeBucket? age;
  final DateTime? receiptFrom;
  final DateTime? receiptTo;
  final String? billIndex;
  final int? minPaise;
  final int? maxPaise;
  final InventorySort sort;

  /// Filters other than status and sort (what the filter sheet edits).
  int get activeExtraFilters =>
      (age != null ? 1 : 0) +
      (receiptFrom != null || receiptTo != null ? 1 : 0) +
      (billIndex != null ? 1 : 0) +
      (minPaise != null || maxPaise != null ? 1 : 0);

  bool accepts(Saree s, {DateTime? now}) {
    final okStatus = switch (status) {
      StockStatus.available => s.isAvailable,
      StockStatus.sold => !s.isAvailable,
      StockStatus.all => true,
    };
    if (!okStatus) return false;
    if (age != null && ageBuckets[ageBucketIndex(ageInDays(s.receiptDate, now: now))] != age) return false;
    final d = dateOnly(s.receiptDate);
    if (receiptFrom != null && d.isBefore(dateOnly(receiptFrom!))) return false;
    if (receiptTo != null && d.isAfter(dateOnly(receiptTo!))) return false;
    if (billIndex != null && s.billIndex.toLowerCase() != billIndex!.toLowerCase()) return false;
    if (minPaise != null && s.markedPricePaise < minPaise!) return false;
    if (maxPaise != null && s.markedPricePaise > maxPaise!) return false;
    return true;
  }

  InventoryFilter copyWith({
    StockStatus? status,
    InventorySort? sort,
    AgeBucket? age,
    DateTime? receiptFrom,
    DateTime? receiptTo,
    String? billIndex,
    int? minPaise,
    int? maxPaise,
    bool clearAge = false,
    bool clearReceipt = false,
    bool clearBill = false,
    bool clearPrice = false,
  }) =>
      InventoryFilter(
        status: status ?? this.status,
        sort: sort ?? this.sort,
        age: clearAge ? null : (age ?? this.age),
        receiptFrom: clearReceipt ? null : (receiptFrom ?? this.receiptFrom),
        receiptTo: clearReceipt ? null : (receiptTo ?? this.receiptTo),
        billIndex: clearBill ? null : (billIndex ?? this.billIndex),
        minPaise: clearPrice ? null : (minPaise ?? this.minPaise),
        maxPaise: clearPrice ? null : (maxPaise ?? this.maxPaise),
      );
}

class InventoryFilterNotifier extends Notifier<InventoryFilter> {
  @override
  InventoryFilter build() => const InventoryFilter();

  /// Opens a fresh view. Coming from an age tile shows the oldest stock first.
  void show(StockStatus status, {AgeBucket? age}) => state = InventoryFilter(
        status: status,
        age: age,
        sort: age != null ? InventorySort.receiptOldest : InventorySort.newestIndexed,
      );

  void set(InventoryFilter f) => state = f;
  void setStatus(StockStatus s) => state = state.copyWith(status: s);
  void setSort(InventorySort s) => state = state.copyWith(sort: s);
  void clearAge() => state = state.copyWith(clearAge: true);
  void clearReceipt() => state = state.copyWith(clearReceipt: true);
  void clearBill() => state = state.copyWith(clearBill: true);
  void clearPrice() => state = state.copyWith(clearPrice: true);

  /// Clears every filter but keeps the status and sort the user picked.
  void clearExtras() => state = InventoryFilter(status: state.status, sort: state.sort);
}

final inventoryFilterProvider =
    NotifierProvider<InventoryFilterNotifier, InventoryFilter>(InventoryFilterNotifier.new);
