import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/models.dart';

class CartLine {
  CartLine({required this.saree, required this.negotiatedPaise});
  final Saree saree;
  final int negotiatedPaise;
  CartLine withPrice(int p) => CartLine(saree: saree, negotiatedPaise: p);
}

class CartState {
  const CartState({
    this.lines = const [],
    this.idempotencyKey = '',
    this.draftId,
    this.draftCustomer,
    this.draftDiscountBp,
  });
  final List<CartLine> lines;

  /// One key per checkout attempt; kept across retries, regenerated after success.
  final String idempotencyKey;

  /// Set while editing a saved draft. Saving or confirming then updates that same sale row.
  final String? draftId;

  /// Loaded from the draft so the sell screen can restore the customer and discount fields.
  final String? draftCustomer;
  final int? draftDiscountBp;

  CartState withLines(List<CartLine> l) => CartState(
        lines: l,
        idempotencyKey: idempotencyKey,
        draftId: draftId,
        draftCustomer: draftCustomer,
        draftDiscountBp: draftDiscountBp,
      );
}

class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() => CartState(idempotencyKey: const Uuid().v4());

  void add(Saree s) {
    if (state.lines.any((l) => l.saree.id == s.id)) return;
    state = state.withLines([...state.lines, CartLine(saree: s, negotiatedPaise: s.markedPricePaise)]);
  }

  void remove(String id) => state = state.withLines(state.lines.where((l) => l.saree.id != id).toList());

  void setPrice(String id, int paise) =>
      state = state.withLines([for (final l in state.lines) l.saree.id == id ? l.withPrice(paise) : l]);

  void loadDraft(Sale draft, List<Saree> all) {
    final byId = {for (final s in all) s.id: s};
    final lines = <CartLine>[];
    for (final i in draft.items) {
      final s = byId[i.sareeId];
      if (s != null) lines.add(CartLine(saree: s, negotiatedPaise: i.negotiatedPaise));
    }
    state = CartState(
      lines: lines,
      idempotencyKey: const Uuid().v4(),
      draftId: draft.id,
      draftCustomer: draft.customerName,
      draftDiscountBp: draft.discountBp,
    );
  }

  void reset() => state = CartState(idempotencyKey: const Uuid().v4());
}

final cartProvider = NotifierProvider<CartNotifier, CartState>(CartNotifier.new);
