/// Dart mirror of the confirm_sale allocation in 001_initial.sql.
/// Used for the live cart preview; the server remains the source of truth.
class SaleLineInput {
  const SaleLineInput({required this.id, required this.markedPaise, required this.negotiatedPaise});
  final String id;
  final int markedPaise;
  final int negotiatedPaise;
}

class SaleTotals {
  const SaleTotals({
    required this.totalMarked,
    required this.subtotalNegotiated,
    required this.orderDiscount,
    required this.totalCollected,
    required this.allocations,
  });
  final int totalMarked;
  final int subtotalNegotiated;
  final int orderDiscount;
  final int totalCollected;

  /// saree id -> allocated discount paise
  final Map<String, int> allocations;

  int get totalDiscountVsTag => totalMarked - totalCollected;
  int finalFor(SaleLineInput l) => l.negotiatedPaise - (allocations[l.id] ?? 0);
}

SaleTotals computeSaleTotals(List<SaleLineInput> lines, int discountBp) {
  assert(discountBp >= 0 && discountBp <= 10000);
  // Same order as the SQL (sorted by uuid text == uuid byte order for lowercase hex).
  final sorted = [...lines]..sort((a, b) => a.id.compareTo(b.id));
  final marked = sorted.fold<int>(0, (s, l) => s + l.markedPaise);
  final sub = sorted.fold<int>(0, (s, l) => s + l.negotiatedPaise);
  final disc = (sub * discountBp) ~/ 10000;
  final allocs = <String, int>{};
  var allocated = 0;
  for (var i = 0; i < sorted.length; i++) {
    final l = sorted[i];
    final int a;
    if (i == sorted.length - 1) {
      a = disc - allocated;
    } else if (sub == 0) {
      a = 0;
    } else {
      a = (l.negotiatedPaise * disc) ~/ sub;
    }
    allocated += a;
    allocs[l.id] = a;
  }
  return SaleTotals(
    totalMarked: marked,
    subtotalNegotiated: sub,
    orderDiscount: disc,
    totalCollected: sub - disc,
    allocations: allocs,
  );
}
