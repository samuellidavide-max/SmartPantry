import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/compare/compare_screen.dart';
import 'features/home/home_screen.dart';
import 'features/lists/list_screen.dart';
import 'features/lists/lists_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/receipt/receipt_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => _Shell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, __) => const HomeScreen())]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/lists',
            builder: (_, __) => const ListsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => ListScreen(listId: s.pathParameters['id']!),
                routes: [
                  GoRoute(path: 'compare', builder: (_, s) => CompareScreen(listId: s.pathParameters['id']!)),
                ],
              ),
            ],
          ),
        ]),
        StatefulShellBranch(routes: [GoRoute(path: '/scan', builder: (_, __) => const ReceiptScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen())]),
      ],
    ),
  ],
);

class _Shell extends StatelessWidget {
  const _Shell({required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.checklist_outlined), selectedIcon: Icon(Icons.checklist), label: 'Liste'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Scansiona'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profilo'),
        ],
      ),
    );
  }
}
