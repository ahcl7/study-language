import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_provider.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/classes/presentation/class_list_screen.dart';
import '../../features/classes/presentation/class_form_screen.dart';
import '../../features/groups/presentation/group_list_screen.dart';
import '../../features/groups/presentation/group_form_screen.dart';
import '../../features/words/presentation/word_list_screen.dart';
import '../../features/words/presentation/word_form_screen.dart';
import '../../features/flashcard/presentation/flashcard_screen.dart';
import '../../features/practice/presentation/practice_config_screen.dart';
import '../../features/practice/presentation/mcq_screen.dart';
import '../../features/practice/presentation/fill_blank_screen.dart';
import '../../features/type_to_learn/presentation/mode1_screen.dart';
import '../../features/type_to_learn/presentation/mode2_screen.dart';
import '../../features/paragraphs/presentation/paragraph_list_screen.dart';
import '../../features/paragraphs/presentation/paragraph_form_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/backup/presentation/backup_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final isLoggedIn = authState.isLoggedIn;
      final isAuthRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';

      if (!isLoggedIn && !isAuthRoute) return '/login';
      if (isLoggedIn && isAuthRoute) return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/classes',
        builder: (context, state) => const ClassListScreen(),
      ),
      GoRoute(
        path: '/classes/new',
        builder: (context, state) => const ClassFormScreen(),
      ),
      GoRoute(
        path: '/classes/edit/:id',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return ClassFormScreen(classId: id);
        },
      ),
      GoRoute(
        path: '/classes/:classId/groups',
        builder: (context, state) {
          final classId = int.parse(state.pathParameters['classId']!);
          return GroupListScreen(classId: classId);
        },
      ),
      GoRoute(
        path: '/classes/:classId/groups/new',
        builder: (context, state) {
          final classId = int.parse(state.pathParameters['classId']!);
          return GroupFormScreen(classId: classId);
        },
      ),
      GoRoute(
        path: '/classes/:classId/groups/edit/:groupId',
        builder: (context, state) {
          final classId = int.parse(state.pathParameters['classId']!);
          final groupId = int.parse(state.pathParameters['groupId']!);
          return GroupFormScreen(classId: classId, groupId: groupId);
        },
      ),
      GoRoute(
        path: '/groups/:groupId/words',
        builder: (context, state) {
          final groupId = int.parse(state.pathParameters['groupId']!);
          return WordListScreen(groupId: groupId);
        },
      ),
      GoRoute(
        path: '/words/new',
        builder: (context, state) {
          final groupId = state.uri.queryParameters['groupId'] != null
              ? int.parse(state.uri.queryParameters['groupId']!)
              : null;
          return WordFormScreen(groupId: groupId);
        },
      ),
      GoRoute(
        path: '/words/edit/:id',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return WordFormScreen(wordId: id);
        },
      ),
      GoRoute(
        path: '/flashcard',
        builder: (context, state) => const FlashcardScreen(),
      ),
      GoRoute(
        path: '/practice',
        builder: (context, state) => const PracticeConfigScreen(),
      ),
      GoRoute(
        path: '/practice/mcq',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return McqScreen(words: extra['words'], title: extra['title']);
        },
      ),
      GoRoute(
        path: '/practice/fill-blank',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return FillBlankScreen(words: extra['words'], title: extra['title']);
        },
      ),
      GoRoute(
        path: '/type-to-learn/mode1',
        builder: (context, state) => const Mode1Screen(),
      ),
      GoRoute(
        path: '/type-to-learn/mode2',
        builder: (context, state) => const Mode2Screen(),
      ),
      GoRoute(
        path: '/paragraphs',
        builder: (context, state) => const ParagraphListScreen(),
      ),
      GoRoute(
        path: '/paragraphs/new',
        builder: (context, state) {
          final classId = state.uri.queryParameters['classId'] != null
              ? int.parse(state.uri.queryParameters['classId']!)
              : null;
          return ParagraphFormScreen(classId: classId);
        },
      ),
      GoRoute(
        path: '/paragraphs/edit/:id',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return ParagraphFormScreen(paragraphId: id);
        },
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/backup',
        builder: (context, state) => const BackupScreen(),
      ),
    ],
  );
});
