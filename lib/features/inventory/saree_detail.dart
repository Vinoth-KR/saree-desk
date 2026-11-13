import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';
import '../sell/cart.dart';
import 'delete_rules.dart';

class SareeDetailScreen extends ConsumerStatefulWidget {
  const SareeDetailScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<SareeDetailScreen> createState() => _SareeDetailScreenState();
}

class _SareeDetailScreenState extends ConsumerState<SareeDetailScreen> {
  bool _uploading = false;
  bool _deleting = false;

  Future<void> _delete(Saree s) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete ${s.sku}?',
      body: '${s.description}\n\nThis permanently removes the saree from your stock and cannot be undone. '
          'The photo file stays in storage.',
      ok: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ref.read(repoProvider).deleteSaree(s.id);
      await PendingPhotos.remove(s.id); // a photo still waiting to upload has nothing to attach to now
      refreshAll(ref);
      if (!mounted) return;
      showInfo(context, '${s.sku} deleted');
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/inventory');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _replacePhoto(ImageSource src) async {
    final m = ref.read(membershipProvider).asData?.value;
    if (m == null) return;
    try {
      final bytes = await PhotoPicker.pick(src);
      if (bytes == null) return;
      setState(() => _uploading = true);
      try {
        await ref
            .read(repoProvider)
            .uploadPhoto(
              businessId: m.businessId,
              sareeId: widget.id,
              bytes: bytes,
            );
        await PendingPhotos.remove(widget.id);
        refreshAll(ref);
        if (mounted) showInfo(context, 'Photo saved');
      } catch (e) {
        await PendingPhotos.add(widget.id, bytes);
        ref.invalidate(pendingPhotosProvider);
        if (mounted) {
          showError(
            context,
            'Photo not uploaded: $e. It is kept on this phone; retry from Inventory.',
          );
        }
      }
    } catch (e) {
      if (mounted) showError(context, 'Could not open picker: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _photoSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take photo'),
              onTap: () {
                Navigator.pop(c);
                _replacePhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(c);
                _replacePhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(Saree s) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => _EditSheet(saree: s),
    );
    if (changed == true) refreshAll(ref);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(sareesProvider);
    final sales = ref.watch(salesProvider).asData?.value ?? const <Sale>[];
    final canWrite =
        ref.watch(membershipProvider).asData?.value?.canWrite ?? false;
    return async.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(friendlyError(e).message)),
      ),
      data: (all) {
        final s = all.where((x) => x.id == widget.id).firstOrNull;
        if (s == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Saree not found')),
          );
        }
        final sale = s.isAvailable
            ? null
            : sales
                  .where(
                    (x) =>
                        x.status == 'confirmed' &&
                        x.items.any((i) => i.sareeId == s.id),
                  )
                  .firstOrNull;
        return Scaffold(
          appBar: AppBar(
            title: Text(s.sku),
            actions: [
              if (canWrite)
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Edit',
                  onPressed: () => _edit(s),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              GestureDetector(
                onTap: s.imagePath == null
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        builder: (_) => Dialog.fullscreen(
                          child: Stack(
                            children: [
                              InteractiveViewer(
                                child: Center(
                                  child: SareeImage(
                                    path: s.imagePath,
                                    size: null,
                                    fit: BoxFit.contain,
                                    radius: 0,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: SafeArea(
                                  child: IconButton.filledTonal(
                                    icon: const Icon(Icons.close),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: SareeImage(
                    path: s.imagePath,
                    size: null,
                    fit: BoxFit.cover,
                    radius: 12,
                  ),
                ),
              ),
              if (canWrite) const SizedBox(height: 8),
              if (canWrite)
                OutlinedButton.icon(
                  onPressed: _uploading ? null : _photoSheet,
                  icon: _uploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.photo_camera),
                  label: Text(
                    s.imagePath == null ? 'Add photo' : 'Replace photo',
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  CopyChip(
                    text: s.sku,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const Spacer(),
                  StatusChip(s.status),
                ],
              ),
              Text(
                s.description,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              _row('Marked price', formatInr(s.markedPricePaise)),
              _row('Receipt date', formatDate(s.receiptDate)),
              _row('Bill index', s.billIndex),
              _row('Stock age', '${ageInDays(s.receiptDate)} days'),
              _row('Indexed', formatDate(s.indexedAt)),
              if (s.soldAt != null) _row('Sold', formatDate(s.soldAt!)),
              if (sale != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.receipt_long),
                  title: Text('Sale ${sale.saleNumber ?? ''}'),
                  subtitle: Text(
                    '${sale.customerName} · ${formatInr(sale.items.firstWhere((i) => i.sareeId == s.id).finalPaise)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/sale/${sale.id}'),
                ),
              const SizedBox(height: 16),
              Text('Label QR code (contains only the SKU, never the price)',
                  style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              Center(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: BarcodeWidget(
                    barcode: Barcode.qrCode(),
                    data: s.sku, // payload is exactly the SKU
                    width: 180,
                    height: 180,
                    drawText: false,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (s.isAvailable && canWrite) ...[
                FilledButton.icon(
                  onPressed: () {
                    ref.read(cartProvider.notifier).add(s);
                    showInfo(context, '${s.sku} added to sale');
                    context.go('/sell');
                  },
                  icon: const Icon(Icons.point_of_sale),
                  label: const Text('Sell this saree'),
                ),
              ],
              if (canWrite) ...[
                const SizedBox(height: 24),
                const Divider(),
                _DeleteSection(
                  saree: s,
                  blocker: deleteBlocker(s.id, sales),
                  busy: _deleting,
                  onDelete: () => _delete(s),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _row(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            k,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        Expanded(child: Text(v)),
      ],
    ),
  );
}

class _EditSheet extends ConsumerStatefulWidget {
  const _EditSheet({required this.saree});
  final Saree saree;
  @override
  ConsumerState<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends ConsumerState<_EditSheet> {
  final _form = GlobalKey<FormState>();
  late final _desc = TextEditingController(text: widget.saree.description);
  late final _bill = TextEditingController(text: widget.saree.billIndex);
  late final _price = TextEditingController(
    text: paiseToRupeeText(widget.saree.markedPricePaise),
  );
  late DateTime _date = widget.saree.receiptDate;
  bool _busy = false;

  @override
  void dispose() {
    _desc.dispose();
    _bill.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(repoProvider)
          .editSaree(
            id: widget.saree.id,
            receiptDate: _date,
            billIndex: _bill.text.trim(),
            description: _desc.text.trim(),
            markedPaise: parseRupeesToPaise(_price.text)!,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Edit ${widget.saree.sku}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _desc,
                decoration: const InputDecoration(labelText: 'Description'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bill,
                decoration: const InputDecoration(labelText: 'Bill index'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Marked price',
                  prefixText: '₹ ',
                ),
                validator: (v) => parseRupeesToPaise(v ?? '') == null
                    ? 'Enter a price greater than zero'
                    : null,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today),
                label: Text('Receipt date: ${formatDate(_date)}'),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2015),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (d != null) setState(() => _date = dateOnly(d));
                },
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: const Text('Save changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Delete stock" with its explanation. The button only appears when nothing blocks the deletion.
class _DeleteSection extends StatelessWidget {
  const _DeleteSection({required this.saree, required this.blocker, required this.busy, required this.onDelete});
  final Saree saree;
  final DeleteBlock? blocker;
  final bool busy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final b = blocker;
    if (b != null || !saree.isAvailable) {
      final text = b == null
          ? '${saree.sku} is not available, so it cannot be deleted.'
          : b.isDraft
              ? '${saree.sku} is in a draft sale for ${b.sale.customerName}. '
                  'Discard or edit that draft first, then you can delete this saree.'
              : '${saree.sku} is part of sales history (${b.sale.saleNumber ?? 'a sale'}). '
                  'Sales history is always kept, so this saree cannot be deleted.';
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.lock_outline, size: 18, color: cs.outline),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: cs.error, side: BorderSide(color: cs.error)),
        onPressed: busy ? null : onDelete,
        icon: busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.delete_outline),
        label: const Text('Delete stock'),
      ),
    );
  }
}
