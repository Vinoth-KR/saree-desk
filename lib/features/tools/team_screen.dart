import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';

final teamProvider = FutureProvider.autoDispose<List<TeamMember>>((ref) => ref.watch(repoProvider).listMembers());

/// Owner-only list of people allowed into the shop, with their roles.
/// Every action is enforced again in the database (list_members, add_member, ...).
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action, String done) async {
    try {
      await action();
      ref.invalidate(teamProvider);
      ref.invalidate(membershipProvider);
      if (context.mounted) showInfo(context, done);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    // The dialog owns (and disposes) its own text controller, so closing it by Cancel, Add or the
    // back button can never touch a disposed controller during the closing animation.
    final result = await showDialog<({String email, String role})>(
      context: context,
      builder: (_) => const AddMemberDialog(),
    );
    if (result != null && context.mounted) {
      await _run(context, ref, () => ref.read(repoProvider).addMember(result.email, result.role), 'Added');
    }
  }

  static String _title(String r) => _roleTitle(r);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(membershipProvider).asData?.value;
    if (me == null || !me.isOwner) {
      return Scaffold(
        appBar: AppBar(title: const Text('Team and roles')),
        body: const Center(child: Text('Only the owner can manage the team.')),
      );
    }
    final myId = ref.watch(repoProvider).userId;
    final team = ref.watch(teamProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Team and roles')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.person_add),
        label: const Text('Add person'),
      ),
      body: team.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(friendlyError(e).message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: () => ref.invalidate(teamProvider), child: const Text('Retry')),
            ]),
          ),
        ),
        data: (members) => ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            const ListTile(
              dense: true,
              title: Text('Owner: everything, including this screen.\n'
                  'Editor: add and edit stock, sell, void sales.\n'
                  'Viewer: view only.'),
            ),
            const Divider(height: 1),
            for (final m in members)
              ListTile(
                leading: Icon(m.role == 'owner' ? Icons.verified_user : m.role == 'editor' ? Icons.edit : Icons.visibility),
                title: Text(m.email + (m.userId == myId ? ' (you)' : '')),
                subtitle: Text(roleDescription(m.role)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  PopupMenuButton<String>(
                    tooltip: 'Change role',
                    child: Chip(label: Text(_title(m.role)), avatar: const Icon(Icons.arrow_drop_down, size: 18)),
                    onSelected: (r) {
                      if (r != m.role) {
                        _run(context, ref, () => ref.read(repoProvider).setMemberRole(m.userId, r), 'Role updated');
                      }
                    },
                    itemBuilder: (_) => [for (final r in memberRoles) PopupMenuItem(value: r, child: Text(_title(r)))],
                  ),
                  if (m.userId != myId)
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.person_remove_outlined),
                      onPressed: () async {
                        final ok = await confirmDialog(context,
                            title: 'Remove ${m.email}?',
                            body: 'They lose all access to the shop immediately. Their past records stay.',
                            ok: 'Remove');
                        if (ok && context.mounted) {
                          await _run(context, ref, () => ref.read(repoProvider).removeMember(m.userId), 'Removed');
                        }
                      },
                    ),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

String _roleTitle(String r) => r[0].toUpperCase() + r.substring(1);

class AddMemberDialog extends StatefulWidget {
  const AddMemberDialog({super.key});
  @override
  State<AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<AddMemberDialog> {
  final _email = TextEditingController();
  String _role = 'editor';
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    final email = _email.text.trim();
    final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    if (!valid) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    Navigator.pop(context, (email: email, role: _role));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a person'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              labelText: 'Their email (same as their Google account)',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _role,
            decoration: const InputDecoration(labelText: 'Role'),
            items: [for (final r in memberRoles) DropdownMenuItem(value: r, child: Text(_roleTitle(r)))],
            onChanged: (v) => setState(() => _role = v ?? _role),
          ),
          const SizedBox(height: 8),
          Text(roleDescription(_role), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Text('They must have an account first: sign in once with Google, or be created in Supabase.',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
