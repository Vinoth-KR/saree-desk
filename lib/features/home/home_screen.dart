import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/age.dart';
import '../../core/format.dart';
import '../../core/privacy.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';
import '../inventory/inventory_filter.dart';
import '../sales/sales_screen.dart';

enum _Range { today, week, month, all }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  _Range _range = _Range.all;

  bool _inRange(DateTime d) {
    final now = DateTime.now();
    final today = dateOnly(now);
    switch (_range) {
      case _Range.all:
        return true;
      case _Range.today:
        return !dateOnly(d.toLocal()).isBefore(today);
      case _Range.week:
        return !dateOnly(d.toLocal()).isBefore(today.subtract(const Duration(days: 6)));
      case _Range.month:
        return !dateOnly(d.toLocal()).isBefore(today.subtract(const Duration(days: 29)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sarees = ref.watch(sareesProvider);
    final sales = ref.watch(salesProvider);
    final membership = ref.watch(membershipProvider).asData?.value;
    final hide = ref.watch(hideAmountsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const BrandLogo(size: 30),
          const SizedBox(width: 8),
          Expanded(child: Text(membership?.businessName ?? 'Aadav Saree Desk', overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          IconButton(
            tooltip: hide ? 'Show amounts' : 'Hide amounts',
            icon: Icon(hide ? Icons.visibility_off : Icons.visibility),
            onPressed: () => ref.read(hideAmountsProvider.notifier).toggle(),
          ),
          IconButton(
            tooltip: Theme.of(context).brightness == Brightness.dark ? 'Switch to light theme' : 'Switch to dark theme',
            icon: Icon(Theme.of(context).brightness == Brightness.dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => ref.read(themeModeProvider.notifier).set(
                  Theme.of(context).brightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
                ),
          ),
          IconButton(icon: const Icon(Icons.build_outlined), tooltip: 'Tools', onPressed: () => context.push('/tools')),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          refreshAll(ref);
          await ref.read(sareesProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (sarees.hasError || sales.hasError)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.wifi_off),
                  title: Text(friendlyError(sarees.error ?? sales.error!).message),
                  trailing: TextButton(onPressed: () => refreshAll(ref), child: const Text('Retry')),
                ),
              ),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => context.go('/add'),
                  icon: const Icon(Icons.add_a_photo),
                  label: const Text('Add saree'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: () => context.go('/sell'),
                  icon: const Icon(Icons.point_of_sale),
                  label: const Text('New sale'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            if (sarees.asData != null && sales.asData != null) ..._stats(sarees.asData!.value, sales.asData!.value)
            else if (sarees.isLoading || sales.isLoading)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
          ],
        ),
      ),
    );
  }

  List<Widget> _stats(List<Saree> sarees, List<Sale> allSales) {
    final hide = ref.watch(hideAmountsProvider);
    final available = sarees.where((s) => s.isAvailable).toList();
    final sold = sarees.length - available.length;
    final confirmed = allSales.where((s) => s.status == 'confirmed' && _inRange(s.effectiveDate)).toList();
    final collected = confirmed.fold<int>(0, (a, s) => a + s.totalCollectedPaise);
    final discount = confirmed.fold<int>(0, (a, s) => a + s.totalDiscountVsTag);
    final items = confirmed.fold<int>(0, (a, s) => a + s.items.length);
    final avg = items == 0 ? 0 : collected ~/ items;
    final marked = available.fold<int>(0, (a, s) => a + s.markedPricePaise);

    final buckets = List<int>.filled(ageBuckets.length, 0);
    for (final s in available) {
      buckets[ageBucketIndex(ageInDays(s.receiptDate))]++;
    }

    final recent = allSales.where((s) => s.status != 'void').take(5).toList();

    // Sales by customer (names are not unique identifiers).
    final byCustomer = <String, List<Sale>>{};
    for (final s in confirmed) {
      byCustomer.putIfAbsent(s.customerName, () => []).add(s);
    }
    final customerRows = byCustomer.entries.toList()
      ..sort((a, b) => b.value.fold<int>(0, (x, s) => x + s.totalCollectedPaise)
          .compareTo(a.value.fold<int>(0, (x, s) => x + s.totalCollectedPaise)));

    return [
      Row(children: [
        _kpi('Total indexed', '${sarees.length}', onTap: () => _openStock(StockStatus.all)),
        _kpi('Available', '${available.length}', onTap: () => _openStock(StockStatus.available)),
        _kpi('Sold', '$sold', onTap: () => _openStock(StockStatus.sold)),
      ]),
      Row(children: [
        _kpi('Stock at tag price', amountText(marked, hide: hide),
            hidden: hide, wide: true, onTap: () => _openStock(StockStatus.available)),
      ]),
      const SizedBox(height: 8),
      SegmentedButton<_Range>(
        segments: const [
          ButtonSegment(value: _Range.today, label: Text('Today')),
          ButtonSegment(value: _Range.week, label: Text('7 days')),
          ButtonSegment(value: _Range.month, label: Text('30 days')),
          ButtonSegment(value: _Range.all, label: Text('All time')),
        ],
        selected: {_range},
        onSelectionChanged: (v) => setState(() => _range = v.first),
      ),
      const SizedBox(height: 8),
      Row(children: [
        _kpi('Collected', amountText(collected, hide: hide), hidden: hide, onTap: () => context.go('/sales')),
        _kpi('Discount given', amountText(discount, hide: hide), hidden: hide, onTap: () => context.go('/sales')),
        _kpi('Avg / piece', amountText(avg, hide: hide), hidden: hide, onTap: () => context.go('/sales')),
      ]),
      const SizedBox(height: 8),
      Text('Available stock age (from receipt date)', style: Theme.of(context).textTheme.titleSmall),
      Text('Tap a tile to see those sarees', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      Row(children: [
        for (final (i, b) in ageBuckets.indexed)
          _kpi(b.shortLabel, '${buckets[i]}',
              warn: i == ageBuckets.length - 1 && buckets[i] > 0,
              onTap: () => _openStock(StockStatus.available, age: b)),
      ]),
      const SizedBox(height: 12),
      Text('Recent sales', style: Theme.of(context).textTheme.titleSmall),
      if (recent.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('No sales yet')),
      for (final s in recent) SaleTile(sale: s, hideAmounts: hide),
      if (customerRows.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Sales by customer name', style: Theme.of(context).textTheme.titleSmall),
        Text('Names alone are not unique identifiers.', style: Theme.of(context).textTheme.bodySmall),
        for (final e in customerRows.take(10))
          ListTile(
            dense: true,
            title: Text(e.key),
            subtitle: Text('${e.value.length} order(s) · last ${formatDate(e.value.first.effectiveDate)}'),
            trailing: Text(
              amountText(e.value.fold<int>(0, (a, s) => a + s.totalCollectedPaise), hide: hide),
              semanticsLabel: hide ? hiddenAmountSemantics : null,
            ),
          ),
      ],
    ];
  }

  /// Opens the Stock tab already filtered (status and optional age bucket from receipt date).
  void _openStock(StockStatus status, {AgeBucket? age}) {
    ref.read(inventoryFilterProvider.notifier).show(status, age: age);
    context.go('/inventory');
  }

  /// [hidden] marks a masked rupee amount so screen readers say "amount hidden" instead of the bullets.
  Widget _kpi(String label, String value,
          {bool wide = false, bool warn = false, bool hidden = false, VoidCallback? onTap}) =>
      Expanded(
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(value,
                      semanticsLabel: hidden ? hiddenAmountSemantics : null,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(color: warn ? Colors.orange.shade800 : null)),
                ),
              ]),
            ),
          ),
        ),
      );
}
