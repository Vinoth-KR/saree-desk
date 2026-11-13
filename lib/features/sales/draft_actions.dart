import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../sell/cart.dart';

/// Asks for confirmation, then discards an unconfirmed draft. Returns true if it was discarded.
/// Drafts never reserved or changed stock, so nothing else needs undoing.
Future<bool> discardDraftFlow(BuildContext context, WidgetRef ref, Sale draft) async {
  final ok = await confirmDialog(
    context,
    title: 'Discard this draft?',
    body: '${draft.customerName}, ${draft.items.length} item(s), ${formatInr(draft.totalCollectedPaise)}.\n\n'
        'The draft is removed. Stock is not affected. This cannot be undone.',
    ok: 'Discard draft',
  );
  if (!ok || !context.mounted) return false;
  try {
    await ref.read(repoProvider).discardDraft(draft.id);
    // If this draft was open in the cart, drop it so it cannot be saved again by accident.
    if (ref.read(cartProvider).draftId == draft.id) ref.read(cartProvider.notifier).reset();
    refreshAll(ref);
    if (context.mounted) showInfo(context, 'Draft discarded');
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}
