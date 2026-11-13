import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/privacy.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';
import 'draft_actions.dart';

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});
  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  String _filter = 'confirmed'; // confirmed | draft | void | all

  @override
  Widget build(BuildContext context) {
    final sales = ref.watch(salesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sales')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(spacing: 8, children: [
            for (final f in const ['confirmed', 'draft', 'void', 'all'])
              ChoiceChip(
                label: Text(f[0].toUpperCase() + f.substring(1)),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
          ]),
        ),
        Expanded(
          child: sales.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(friendlyError(e).message)),
            data: (all) {
              final list = all.where((s) => _filter == 'all' || s.status == _filter).toList();
              if (list.isEmpty) return const Center(child: Text('No sales here'));
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(salesProvider);
                  await ref.read(salesProvider.future);
                },
                child: ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (c, i) {
                    final s = list[i];
                    final canWrite = ref.watch(membershipProvider).asData?.value?.canWrite ?? false;
                    return SaleTile(
                      sale: s,
                      onDiscard: s.status == 'draft' && canWrite ? () => discardDraftFlow(context, ref, s) : null,
                    );
                  },
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class SaleTile extends StatelessWidget {
  const SaleTile({super.key, required this.sale, this.onDiscard, this.hideAmounts = false});
  final Sale sale;

  /// Masks the rupee amounts (used on the dashboard, where they must not be visible by default).
  final bool hideAmounts;

  /// Shown as a delete button on draft rows only.
  final VoidCallback? onDiscard;
  @override
  Widget build(BuildContext context) {
    final s = sale;
    return ListTile(
      onTap: () => context.push('/sale/${s.id}'),
      trailing: onDiscard == null
          ? null
          : IconButton(
              tooltip: 'Discard draft',
              icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              onPressed: onDiscard,
            ),
      title: Row(children: [
        Expanded(child: Text('${s.saleNumber ?? 'Draft'} · ${s.customerName}', overflow: TextOverflow.ellipsis)),
        StatusChip(s.status),
      ]),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          for (final i in s.items.take(3))
            Padding(padding: const EdgeInsets.only(right: 6), child: SareeImage(path: i.imagePath, size: 44)),
          if (s.items.length > 3) Text('+${s.items.length - 3}'),
          const Spacer(),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              amountText(s.totalCollectedPaise, hide: hideAmounts),
              semanticsLabel: hideAmounts ? hiddenAmountSemantics : null,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text('${s.items.length} item(s) · ${formatDate(s.effectiveDate)}', style: Theme.of(context).textTheme.bodySmall),
            if (s.totalDiscountVsTag > 0)
              Text(
                'Discount ${amountText(s.totalDiscountVsTag, hide: hideAmounts)}',
                semanticsLabel: hideAmounts ? 'discount $hiddenAmountSemantics' : null,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ]),
        ]),
      ),
    );
  }
}
