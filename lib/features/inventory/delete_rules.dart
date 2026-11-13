import '../../data/models.dart';

/// A sale that stops a saree from being deleted.
class DeleteBlock {
  const DeleteBlock(this.sale);
  final Sale sale;

  /// A draft only blocks until it is discarded or edited. Anything else is permanent sales history.
  bool get isDraft => sale.status == 'draft';
}

/// Why [sareeId] cannot be deleted, or null if none of the loaded [sales] blocks it.
///
/// Mirrors the database rule in delete_saree (migration 003): a saree that appears in any sale
/// (confirmed, void or draft) is kept. The server still enforces it; this only explains it early.
/// Real history is reported ahead of a draft, because discarding a draft would not unblock it.
DeleteBlock? deleteBlocker(String sareeId, List<Sale> sales) {
  Sale? draft;
  for (final s in sales) {
    if (!s.items.any((i) => i.sareeId == sareeId)) continue;
    if (s.status != 'draft') return DeleteBlock(s);
    draft ??= s;
  }
  return draft == null ? null : DeleteBlock(draft);
}
