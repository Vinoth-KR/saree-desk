import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/discount.dart';
import '../../core/format.dart';
import '../../core/search.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';
import '../inventory/inventory_screen.dart';
import 'cart.dart';

class SellScreen extends ConsumerStatefulWidget {
  const SellScreen({super.key});
  @override
  ConsumerState<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends ConsumerState<SellScreen> {
  final _search = TextEditingController();
  final _customer = TextEditingController();
  final _discount = TextEditingController();
  bool _walkIn = true;
  bool _busy = false;
  String? _appliedDraftId;

  @override
  void initState() {
    super.initState();
    // Editing a draft can start before this tab was ever opened.
    _applyDraft(ref.read(cartProvider));
  }

  /// Restores the customer and discount of a draft loaded into the cart (otherwise editing a
  /// draft would silently reset the discount to 0%).
  void _applyDraft(CartState c) {
    if (c.draftId == null || c.draftId == _appliedDraftId) return;
    _appliedDraftId = c.draftId;
    final name = c.draftCustomer ?? 'Walk-in customer';
    _walkIn = name == 'Walk-in customer';
    _customer.text = _walkIn ? '' : name;
    _discount.text = bpToText(c.draftDiscountBp ?? 0);
  }

  void _clearForm() {
    _appliedDraftId = null;
    _customer.clear();
    _discount.clear();
    _search.clear();
    _walkIn = true;
  }

  @override
  void dispose() {
    _search.dispose();
    _customer.dispose();
    _discount.dispose();
    super.dispose();
  }

  int? get _bp => parsePercentToBp(_discount.text);

  SaleTotals? _totals(CartState cart) {
    final bp = _bp;
    if (bp == null || cart.lines.isEmpty || cart.lines.any((l) => l.negotiatedPaise < 0)) return null;
    return computeSaleTotals([
      for (final l in cart.lines)
        SaleLineInput(id: l.saree.id, markedPaise: l.saree.markedPricePaise, negotiatedPaise: l.negotiatedPaise)
    ], bp);
  }

  String? _validate(CartState cart) {
    if (cart.lines.isEmpty) return 'Add at least one saree';
    if (cart.lines.any((l) => l.negotiatedPaise < 0)) return 'Fix the invalid sold price';
    if (_bp == null) return 'Discount must be 0–100%';
    if (!_walkIn && _customer.text.trim().isEmpty) return 'Enter a customer name or choose Walk-in';
    return null;
  }

  Future<void> _submit({required bool confirm}) async {
    if (_busy) return;
    final cart = ref.read(cartProvider);
    final err = _validate(cart);
    if (err != null) {
      showError(context, err);
      return;
    }
    final t = _totals(cart)!;
    if (confirm) {
      final ok = await confirmDialog(
        context,
        title: 'Confirm sale',
        body: '${cart.lines.length} item(s)\nCollect ${formatInr(t.totalCollected)}\n\n'
            'Hand over goods only after you see "Sale confirmed".',
        ok: 'Confirm sale',
      );
      if (!ok) return;
    }
    setState(() => _busy = true);
    try {
      final repo = ref.read(repoProvider);
      final customer = _walkIn ? 'Walk-in customer' : _customer.text.trim();
      final sale = await repo.submitSale(
        items: [for (final l in cart.lines) (sareeId: l.saree.id, negotiatedPaise: l.negotiatedPaise)],
        customerName: customer,
        discountBp: _bp!,
        idempotencyKey: cart.idempotencyKey,
        confirm: confirm,
        draftId: cart.draftId,
      );
      ref.read(cartProvider.notifier).reset();
      setState(_clearForm);
      refreshAll(ref);
      if (!mounted) return;
      showInfo(context, confirm ? 'Sale confirmed ${sale.saleNumber ?? ''}' : 'Draft saved');
      context.push('/sale/${sale.id}');
    } on AppException catch (e) {
      if (!mounted) return;
      refreshAll(ref);
      if (e.isConflict) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Sale not completed'),
            content: Text('${e.message}\n\nNothing was changed. Remove the sold item(s) and try again.'),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
          ),
        );
      } else {
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final membership = ref.watch(membershipProvider).asData?.value;
    if (membership != null && !membership.canWrite) return const ReadOnlyScreen(title: 'New sale');
    ref.listen<CartState>(cartProvider, (prev, next) {
      if (next.draftId != prev?.draftId) setState(() => _applyDraft(next));
    });
    final cart = ref.watch(cartProvider);
    final all = ref.watch(sareesProvider).asData?.value ?? const [];
    final q = _search.text;
    final inCart = cart.lines.map((l) => l.saree.id).toSet();
    final results = q.trim().isEmpty
        ? const []
        : all.where((s) => s.isAvailable && !inCart.contains(s.id) && matchesQuery(s, q)).take(20).toList();
    final totals = _totals(cart);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('New sale'),
        actions: [
          if (cart.lines.isNotEmpty)
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      ref.read(cartProvider.notifier).reset();
                      setState(_clearForm);
                    },
              child: const Text('Clear'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          if (cart.draftId != null)
            const Card(
              child: ListTile(
                leading: Icon(Icons.edit_note),
                title: Text('Editing a saved draft'),
                subtitle: Text('Save draft updates it. Confirm sells it. Nothing is voided.'),
              ),
            ),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Find available: SKU, description, price',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  suffixIcon: q.isEmpty
                      ? null
                      : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(_search.clear)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Scan QR code',
              iconSize: 28,
              style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () => context.push('/scan'),
            ),
          ]),
          if (q.trim().isNotEmpty && results.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('No available match'))),
          for (final s in results)
            SareeTile(
              saree: s,
              trailing: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(72, 44)),
                onPressed: () {
                  ref.read(cartProvider.notifier).add(s);
                  setState(_search.clear);
                },
                child: const Text('Add'),
              ),
              onTap: () {
                ref.read(cartProvider.notifier).add(s);
                setState(_search.clear);
              },
            ),
          const SizedBox(height: 8),
          Text('Cart (${cart.lines.length})', style: Theme.of(context).textTheme.titleMedium),
          if (cart.lines.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Search above to add sarees'))),
          for (final l in cart.lines) _CartRow(line: l, key: ValueKey(l.saree.id)),
          if (cart.lines.isNotEmpty) ...[
            const Divider(height: 24),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Walk-in customer')),
                ButtonSegment(value: false, label: Text('Named customer')),
              ],
              selected: {_walkIn},
              onSelectionChanged: (v) => setState(() => _walkIn = v.first),
            ),
            if (!_walkIn) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _customer,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Customer name', isDense: true),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _discount,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: InputDecoration(
                labelText: 'Collective discount on total',
                suffixText: '%',
                isDense: true,
                errorText: _bp == null ? 'Enter 0–100 (up to 2 decimals)' : null,
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: cart.lines.isEmpty
          ? null
          : Material(
              elevation: 8,
              color: cs.surface,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (totals != null) ...[
                      _sum('Total marked', formatInr(totals.totalMarked)),
                      _sum('Negotiated subtotal', formatInr(totals.subtotalNegotiated)),
                      _sum('Collective discount (${formatBp(_bp!)})', '− ${formatInr(totals.orderDiscount)}'),
                      _sum('Customer discount vs tag', formatInr(totals.totalDiscountVsTag)),
                      const SizedBox(height: 4),
                      _sum('Total to collect', formatInr(totals.totalCollected), bold: true),
                    ],
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : () => _submit(confirm: false),
                          child: const Text('Save draft'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: _busy ? null : () => _submit(confirm: true),
                          child: _busy
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Confirm sale'),
                        ),
                      ),
                    ]),
                  ]),
                ),
              ),
            ),
    );
  }

  Widget _sum(String k, String v, {bool bold = false}) {
    final st = bold ? Theme.of(context).textTheme.titleMedium : Theme.of(context).textTheme.bodyMedium;
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(k, style: st), Text(v, style: st)]);
  }
}

class _CartRow extends ConsumerStatefulWidget {
  const _CartRow({super.key, required this.line});
  final CartLine line;
  @override
  ConsumerState<_CartRow> createState() => _CartRowState();
}

class _CartRowState extends ConsumerState<_CartRow> {
  late final _price = TextEditingController(text: paiseToRupeeText(widget.line.negotiatedPaise));

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.line.saree;
    final parsed = parseRupeesToPaise(_price.text, allowZero: true);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          SareeImage(path: s.imagePath, size: 64),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.sku, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(s.description, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('Marked ${formatInr(s.markedPricePaise)}', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          SizedBox(
            width: 104,
            child: TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(
                labelText: 'Sold at',
                prefixText: '₹',
                isDense: true,
                errorText: parsed == null ? 'Invalid' : null,
              ),
              onChanged: (v) {
                final p = parseRupeesToPaise(v, allowZero: true);
                // -1 marks an invalid entry so it can never be submitted with a stale price.
                ref.read(cartProvider.notifier).setPrice(s.id, p ?? -1);
                setState(() {});
              },
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close),
            onPressed: () => ref.read(cartProvider.notifier).remove(s.id),
          ),
        ]),
      ),
    );
  }
}
