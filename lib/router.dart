import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/providers.dart';
import 'features/add/add_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';
import 'features/inventory/inventory_screen.dart';
import 'features/inventory/saree_detail.dart';
import 'features/sales/sale_detail.dart';
import 'features/sales/sales_screen.dart';
import 'features/sell/cart.dart';
import 'features/sell/scan_screen.dart';
import 'features/sell/sell_screen.dart';
import 'features/tools/team_screen.dart';
import 'features/tools/tools_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.listen(membershipProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final loc = state.matchedLocation;
      // Until the first auth event we fall back to the persisted session.
      final signedIn = session.asData?.value != null ||
          (session.isLoading && ref.read(supabaseProvider).auth.currentSession != null);
      if (!signedIn) return loc == '/login' ? null : '/login';

      final m = ref.read(membershipProvider);
      if (m.isLoading) return loc == '/loading' ? null : '/loading';
      if (m.hasError) return loc == '/loading' ? null : '/loading';
      if (m.asData?.value == null) return loc == '/denied' ? null : '/denied';
      if (loc == '/login' || loc == '/denied' || loc == '/loading') return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/denied', builder: (_, _) => const NotAuthorizedScreen()),
      GoRoute(path: '/loading', builder: (_, _) => const _Loading()),
      GoRoute(path: '/tools', builder: (_, _) => const ToolsScreen()),
      GoRoute(path: '/team', builder: (_, _) => const TeamScreen()),
      GoRoute(path: '/scan', builder: (_, _) => const ScanScreen()),
      GoRoute(path: '/saree/:id', builder: (_, s) => SareeDetailScreen(id: s.pathParameters['id']!)),
      GoRoute(path: '/sale/:id', builder: (_, s) => SaleDetailScreen(id: s.pathParameters['id']!)),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _Shell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/add', builder: (_, _) => const AddScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/inventory', builder: (_, _) => const InventoryScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/sell', builder: (_, _) => const SellScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/sales', builder: (_, _) => const SalesScreen())]),
        ],
      ),
    ],
  );
});

class _Loading extends ConsumerWidget {
  const _Loading();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(membershipProvider);
    return Scaffold(
      body: Center(
        child: m.hasError
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.wifi_off, size: 48),
                const SizedBox(height: 8),
                const Text('Could not reach the server'),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: () => ref.invalidate(membershipProvider), child: const Text('Retry')),
                TextButton(
                  onPressed: () => ref.read(supabaseProvider).auth.signOut(),
                  child: const Text('Sign out'),
                ),
              ])
            : const CircularProgressIndicator(),
      ),
    );
  }
}

class _Shell extends ConsumerWidget {
  const _Shell({required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(realtimeProvider);
    final cartCount = ref.watch(cartProvider).lines.length;
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Home'),
          const NavigationDestination(icon: Icon(Icons.add_a_photo_outlined), selectedIcon: Icon(Icons.add_a_photo), label: 'Add'),
          const NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view), label: 'Stock'),
          NavigationDestination(
            icon: Badge(isLabelVisible: cartCount > 0, label: Text('$cartCount'), child: const Icon(Icons.point_of_sale_outlined)),
            selectedIcon: const Icon(Icons.point_of_sale),
            label: 'Sell',
          ),
          const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Sales'),
        ],
      ),
    );
  }
}
