import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/search.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';
import 'filter_sheet.dart';
import 'inventory_filter.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});
  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final _search = TextEditingController();
  bool _retrying = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _retryPending() async {
    final m = ref.read(membershipProvider).asData?.value;
    if (m == null) return;
    setState(() => _retrying = true);
    final repo = ref.read(repoProvider);
    final pending = await PendingPhotos.all();
    // Photos whose saree was deleted (or wiped) can never attach to anything: drop them instead of
    // retrying forever. Judged against a FRESH fetch so a just-saved saree is never mistaken for deleted.
    final known = {for (final s in await repo.fetchSarees()) s.id};
    for (final id in pending.keys.where((id) => !known.contains(id)).toList()) {
      await PendingPhotos.remove(id);
    }
    pending.removeWhere((id, _) => !known.contains(id));
    var ok = 0;
    for (final id in pending.keys) {
      final bytes = await PendingPhotos.bytes(id);
      if (bytes == null) {
        await PendingPhotos.remove(id);
        continue;
      }
      try {
        await repo.uploadPhoto(businessId: m.businessId, sareeId: id, bytes: bytes);
        await PendingPhotos.remove(id);
        ok++;
      } catch (_) {}
    }
    refreshAll(ref);
    if (mounted) {
      setState(() => _retrying = false);
      showInfo(context, ok == pending.length ? 'All photos uploaded' : '$ok of ${pending.length} uploaded; try again');
    }
  }

  void _openFilters(List<Saree> all) {
    final bills = {for (final s in all) s.billIndex}.toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FilterSheet(billIndexes: bills),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sarees = ref.watch(sareesProvider);
    final filter = ref.watch(inventoryFilterProvider);
    final notifier = ref.read(inventoryFilterProvider.notifier);
    final pending = ref.watch(pendingPhotosProvider).asData?.value ?? {};
    final loaded = sarees.asData?.value ?? const <Saree>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        actions: [
          IconButton(
            tooltip: 'Filters',
            icon: Badge(
              isLabelVisible: filter.activeExtraFilters > 0,
              label: Text('${filter.activeExtraFilters}'),
              child: const Icon(Icons.filter_list),
            ),
            onPressed: () => _openFilters(loaded),
          ),
          PopupMenuButton<InventorySort>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            initialValue: filter.sort,
            onSelected: notifier.setSort,
            itemBuilder: (_) => [
              for (final s in InventorySort.values)
                CheckedPopupMenuItem(value: s, checked: s == filter.sort, child: Text(s.label)),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'SKU, description, bill no., receipt date or price',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(_search.clear)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 0,
                children: [
                  for (final f in StockStatus.values)
                    ChoiceChip(
                      label: Text(switch (f) {
                        StockStatus.available => 'Available',
                        StockStatus.sold => 'Sold',
                        StockStatus.all => 'All',
                      }),
                      selected: filter.status == f,
                      onSelected: (_) => notifier.setStatus(f),
                    ),
                  if (filter.age != null)
                    InputChip(
                      avatar: const Icon(Icons.schedule, size: 18),
                      label: Text('Age ${filter.age!.label}'),
                      onDeleted: notifier.clearAge,
                    ),
                  if (filter.receiptFrom != null || filter.receiptTo != null)
                    InputChip(
                      avatar: const Icon(Icons.calendar_today, size: 16),
                      label: Text('Received ${filter.receiptFrom == null ? 'any' : formatDate(filter.receiptFrom!)}'
                          ' to ${filter.receiptTo == null ? 'any' : formatDate(filter.receiptTo!)}'),
                      onDeleted: notifier.clearReceipt,
                    ),
                  if (filter.billIndex != null)
                    InputChip(
                      avatar: const Icon(Icons.receipt_outlined, size: 18),
                      label: Text('Bill ${filter.billIndex}'),
                      onDeleted: notifier.clearBill,
                    ),
                  if (filter.minPaise != null || filter.maxPaise != null)
                    InputChip(
                      avatar: const Icon(Icons.currency_rupee, size: 16),
                      label: Text('${filter.minPaise == null ? 'Any' : formatInr(filter.minPaise!)}'
                          ' to ${filter.maxPaise == null ? 'any' : formatInr(filter.maxPaise!)}'),
                      onDeleted: notifier.clearPrice,
                    ),
                  if (filter.activeExtraFilters > 1)
                    ActionChip(label: const Text('Clear filters'), onPressed: notifier.clearExtras),
                ],
              ),
            ),
          ),
          if (pending.isNotEmpty)
            MaterialBanner(
              content: Text('${pending.length} photo(s) not uploaded yet'),
              leading: const Icon(Icons.cloud_off),
              actions: [
                TextButton(
                  onPressed: _retrying ? null : _retryPending,
                  child: Text(_retrying ? 'Uploading…' : 'Retry upload'),
                ),
              ],
            ),
          Expanded(
            child: sarees.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorRetry(message: friendlyError(e).message, onRetry: () => ref.invalidate(sareesProvider)),
              data: (all) {
                final list = all.where((s) => filter.accepts(s) && matchesQuery(s, _search.text)).toList()
                  ..sort(filter.sort.compare);
                return RefreshIndicator(
                  onRefresh: () async {
                    refreshAll(ref);
                    await ref.read(sareesProvider.future);
                  },
                  child: list.isEmpty
                      ? ListView(children: [
                          const SizedBox(height: 80),
                          Center(child: Text(all.isEmpty ? 'No sarees yet. Tap Add.' : 'No matches')),
                        ])
                      : ListView.separated(
                          itemCount: list.length + 1,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (c, i) => i == list.length
                              ? Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Center(child: Text('${list.length} of ${all.length} sarees')),
                                )
                              : SareeTile(saree: list[i], hasPending: pending.containsKey(list[i].id)),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class SareeTile extends StatelessWidget {
  const SareeTile({super.key, required this.saree, this.hasPending = false, this.trailing, this.onTap});
  final Saree saree;
  final bool hasPending;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = saree;
    return ListTile(
      minVerticalPadding: 10,
      leading: Stack(
        children: [
          SareeImage(path: s.imagePath, size: 64),
          if (hasPending)
            const Positioned(right: 0, top: 0, child: Icon(Icons.cloud_off, size: 18, color: Colors.orange)),
        ],
      ),
      title: Row(
        children: [
          Text(s.sku, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          if (!s.isAvailable) const StatusChip('sold'),
        ],
      ),
      subtitle: Text('${s.description}\n${formatDate(s.receiptDate)} · ${ageInDays(s.receiptDate)}d · Bill ${s.billIndex}'),
      isThreeLine: true,
      trailing: trailing ?? Text(formatInr(s.markedPricePaise), style: Theme.of(context).textTheme.titleSmall),
      onTap: onTap ?? () => context.push('/saree/${s.id}'),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi_off, size: 48),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ]),
        ),
      );
}
