import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'repository.dart';

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final repoProvider = Provider<Repository>((ref) => Repository(ref.watch(supabaseProvider)));

final sessionProvider = StreamProvider<Session?>((ref) async* {
  final auth = ref.watch(supabaseProvider).auth;
  yield auth.currentSession;
  yield* auth.onAuthStateChange.map((e) => e.session);
});

final membershipProvider = FutureProvider<Membership?>((ref) async {
  final session = ref.watch(sessionProvider).asData?.value;
  if (session == null) return null;
  return ref.watch(repoProvider).fetchMembership();
});

final sareesProvider = FutureProvider<List<Saree>>((ref) async {
  final m = ref.watch(membershipProvider).asData?.value;
  if (m == null) return [];
  return ref.watch(repoProvider).fetchSarees();
});

final salesProvider = FutureProvider<List<Sale>>((ref) async {
  final m = ref.watch(membershipProvider).asData?.value;
  if (m == null) return [];
  return ref.watch(repoProvider).fetchSales();
});

final signedUrlProvider = FutureProvider.family<String, String>(
  (ref, path) => ref.watch(repoProvider).signedUrl(path),
);

final pendingPhotosProvider = FutureProvider<Map<String, String>>((ref) => PendingPhotos.all());

void refreshAll(WidgetRef ref) {
  ref.invalidate(sareesProvider);
  ref.invalidate(salesProvider);
  ref.invalidate(pendingPhotosProvider);
}

/// Realtime: any change to sarees/sales refetches. Realtime is a hint only;
/// every write is validated server-side.
final realtimeProvider = Provider<void>((ref) {
  final client = ref.watch(supabaseProvider);
  final m = ref.watch(membershipProvider).asData?.value;
  if (m == null) return;
  Timer? debounce;
  void bump() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 300), () {
      ref.invalidate(sareesProvider);
      ref.invalidate(salesProvider);
    });
  }

  final ch = client
      .channel('shop-${m.businessId}')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'sarees',
        callback: (_) => bump(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'sales',
        callback: (_) => bump(),
      )
      .subscribe();
  ref.onDispose(() {
    debounce?.cancel();
    client.removeChannel(ch);
  });
});
