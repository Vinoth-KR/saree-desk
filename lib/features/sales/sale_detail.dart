import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';
import '../sell/cart.dart';
import 'draft_actions.dart';
import 'slip_pdf.dart';

class SaleDetailScreen extends ConsumerStatefulWidget {
  const SaleDetailScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends ConsumerState<SaleDetailScreen> {
  bool _busy = false;

  Future<void> _void(Sale s) async {
    // The dialog owns its text controller and only closes with a non-empty reason.
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => VoidReasonDialog(itemCount: s.items.length),
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(repoProvider).voidSale(s.id, reason);
      refreshAll(ref);
      if (mounted) showInfo(context, 'Sale voided; items are available again');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDraft(Sale s) async {
    final ok = await confirmDialog(context,
        title: 'Confirm draft sale', body: 'Collect ${formatInr(s.totalCollectedPaise)} for ${s.items.length} item(s)?');
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await ref.read(repoProvider).confirmDraft(s.id, const Uuid().v4());
      refreshAll(ref);
      if (mounted) {
        showInfo(context, 'Sale confirmed');
        context.pop();
      }
    } catch (e) {
      refreshAll(ref);
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(salesProvider);
    final canWrite = ref.watch(membershipProvider).asData?.value?.canWrite ?? false;
    return async.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(appBar: AppBar(), body: Center(child: Text(friendlyError(e).message))),
      data: (all) {
        final s = all.where((x) => x.id == widget.id).firstOrNull;
        if (s == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Sale not found')));
        return Scaffold(
          appBar: AppBar(title: Text(s.saleNumber ?? 'Draft sale')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(child: Text(s.customerName, style: Theme.of(context).textTheme.titleLarge)),
              StatusChip(s.status),
            ]),
            Text(formatDate(s.effectiveDate)),
            if (s.status == 'void')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Voided${s.voidedAt != null ? ' ${formatDate(s.voidedAt!)}' : ''}: ${s.voidReason ?? ''}',
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const Divider(height: 24),
            for (final i in s.items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: SareeImage(path: i.imagePath, size: 56),
                title: Text('${i.sku} · ${i.description}', maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('Marked ${formatInr(i.markedPaise)} · Agreed ${formatInr(i.negotiatedPaise)}'),
                trailing: Text(formatInr(i.finalPaise), style: Theme.of(context).textTheme.titleSmall),
                onTap: () => context.push('/saree/${i.sareeId}'),
              ),
            const Divider(height: 24),
            _kv('Total marked', formatInr(s.totalMarkedPaise)),
            _kv('Agreed subtotal', formatInr(s.subtotalNegotiatedPaise)),
            _kv('Collective discount (${formatBp(s.discountBp)})', '− ${formatInr(s.orderDiscountPaise)}'),
            _kv('Customer discount vs tag', formatInr(s.totalDiscountVsTag)),
            _kv('Total collected', formatInr(s.totalCollectedPaise), bold: true),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              icon: const Icon(Icons.share),
              label: const Text('Share sales slip (PDF)'),
              onPressed: () async {
                final bytes = await buildSlipPdf(s);
                await Printing.sharePdf(bytes: bytes, filename: '${s.saleNumber ?? 'draft-${s.id.substring(0, 8)}'}.pdf');
              },
            ),
            const SizedBox(height: 8),
            if (s.status == 'draft' && canWrite) ...[
              FilledButton(onPressed: _busy ? null : () => _confirmDraft(s), child: const Text('Confirm sale')),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () {
                        final sarees = ref.read(sareesProvider).asData?.value ?? const [];
                        ref.read(cartProvider.notifier).loadDraft(s, sarees);
                        context.go('/sell');
                      },
                child: const Text('Edit in cart'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  side: BorderSide(color: Theme.of(context).colorScheme.error),
                ),
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        final done = await discardDraftFlow(context, ref, s);
                        if (!context.mounted) return;
                        setState(() => _busy = false);
                        if (done) context.pop();
                      },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Discard draft'),
              ),
            ],
            if (s.status == 'confirmed' && canWrite)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                onPressed: _busy ? null : () => _void(s),
                icon: const Icon(Icons.undo),
                label: const Text('Void / undo sale'),
              ),
          ]),
        );
      },
    );
  }

  Widget _kv(String k, String v, {bool bold = false}) {
    final st = bold ? Theme.of(context).textTheme.titleMedium : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(k, style: st), Text(v, style: st)]),
    );
  }
}

class VoidReasonDialog extends StatefulWidget {
  const VoidReasonDialog({super.key, required this.itemCount});
  final int itemCount;
  @override
  State<VoidReasonDialog> createState() => _VoidReasonDialogState();
}

class _VoidReasonDialogState extends State<VoidReasonDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final r = _reason.text.trim();
    if (r.isEmpty) {
      setState(() => _error = 'A reason is required to void a sale');
      return;
    }
    Navigator.pop(context, r);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Void this sale?'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('All ${widget.itemCount} item(s) become available again. The sale is kept as VOID.'),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(labelText: 'Reason (required)', errorText: _error),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(96, 44),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: _submit,
          child: const Text('Void sale'),
        ),
      ],
    );
  }
}
