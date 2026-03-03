import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/theme_notifier.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: StudyLanguageApp()));
}

class StudyLanguageApp extends ConsumerWidget {
  const StudyLanguageApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeSettings = ref.watch(themeProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Study Language',
      debugShowCheckedModeBanner: false,
      theme: themeSettings.lightTheme,
      darkTheme: themeSettings.darkTheme,
      themeMode: themeSettings.themeMode,
      routerConfig: router,
    );
  }
}
