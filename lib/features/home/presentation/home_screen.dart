import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/auth_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Study Language'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.push('/login');
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome, ${auth.username ?? 'User'}!',
                style: theme.textTheme.headlineSmall),
            const SizedBox(height: 24),
            _buildSection(context, 'Manage', [
              _NavCard(
                icon: Icons.class_,
                title: 'Classes',
                subtitle: 'Manage classes and groups',
                onTap: () => context.push('/classes'),
              ),
              _NavCard(
                icon: Icons.drive_file_move_outline,
                title: 'Move Words',
                subtitle: 'Search words and move them to groups',
                onTap: () => context.push('/words/manage'),
              ),
              _NavCard(
                icon: Icons.article,
                title: 'Paragraphs',
                subtitle: 'Create paragraphs for typing practice',
                onTap: () => context.push('/paragraphs'),
              ),
            ]),
            const SizedBox(height: 24),
            _buildSection(context, 'Study', [
              _NavCard(
                icon: Icons.style,
                title: 'Flashcards',
                subtitle: 'Review vocabulary with flip cards',
                onTap: () => context.push('/flashcard'),
              ),
              _NavCard(
                icon: Icons.quiz,
                title: 'Practice',
                subtitle: 'MCQ & fill-in-the-blank quizzes',
                onTap: () => context.push('/practice'),
              ),
            ]),
            const SizedBox(height: 24),
            _buildSection(context, 'Type to Learn', [
              _NavCard(
                icon: Icons.cloud,
                title: 'Floating Words',
                subtitle: 'Type words as they float across screen',
                onTap: () => context.push('/type-to-learn/mode1'),
              ),
              _NavCard(
                icon: Icons.keyboard,
                title: 'Paragraph Typing',
                subtitle: 'Type paragraphs word by word',
                onTap: () => context.push('/type-to-learn/mode2'),
              ),
            ]),
            const SizedBox(height: 24),
            _buildSection(context, 'Data', [
              _NavCard(
                icon: Icons.backup,
                title: 'Backup & Restore',
                subtitle: 'Export/import data as JSON',
                onTap: () => context.push('/backup'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
      BuildContext context, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: children,
        ),
      ],
    );
  }
}

class _NavCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _NavCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 220,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 36, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
