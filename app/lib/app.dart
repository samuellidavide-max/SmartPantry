import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/api_client.dart';
import 'core/theme.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'router.dart';
import 'state/providers.dart';

class SmartPantryApp extends ConsumerWidget {
  const SmartPantryApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final light = buildTheme(Brightness.light), dark = buildTheme(Brightness.dark);

    return session.when(
      loading: () => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: light,
        darkTheme: dark,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      error: (e, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: light,
        darkTheme: dark,
        home: ServerErrorScreen(error: e),
      ),
      data: (s) => s.onboarded
          ? MaterialApp.router(
              title: 'SmartPantry',
              debugShowCheckedModeBanner: false,
              theme: light,
              darkTheme: dark,
              routerConfig: appRouter,
            )
          : MaterialApp(
              title: 'SmartPantry',
              debugShowCheckedModeBanner: false,
              theme: light,
              darkTheme: dark,
              home: const OnboardingScreen(),
            ),
    );
  }
}

/// Mostrata quando il backend non risponde: permette di cambiare indirizzo del server.
class ServerErrorScreen extends ConsumerStatefulWidget {
  const ServerErrorScreen({super.key, required this.error});
  final Object error;

  @override
  ConsumerState<ServerErrorScreen> createState() => _ServerErrorScreenState();
}

class _ServerErrorScreenState extends ConsumerState<ServerErrorScreen> {
  late final TextEditingController _url =
      TextEditingController(text: ref.read(repositoryProvider).api.baseUrl);

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.error;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 24),
          Icon(Icons.cloud_off_outlined, size: 48, color: context.muted),
          const SizedBox(height: 16),
          Text('Non riesco a collegarmi al server', style: context.text.headlineSmall),
          const SizedBox(height: 8),
          Text(e is ApiException ? e.message : '$e', style: TextStyle(color: context.muted)),
          const SizedBox(height: 24),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Indirizzo del backend',
              helperText: 'Emulatore Android: http://10.0.2.2:8000 · Telefono: http://IP-del-computer:8000',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => ref.read(sessionProvider.notifier).changeServer(_url.text),
            child: const Text('Salva e riprova'),
          ),
        ]),
      ),
    );
  }
}
