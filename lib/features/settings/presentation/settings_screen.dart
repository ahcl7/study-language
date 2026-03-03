import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_notifier.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/database/app_database.dart';
import '../../../core/utils/password_utils.dart';
import '../../auth/auth_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeProvider);
    final notifier = ref.read(themeProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.push('/home'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Theme mode
              Text('Theme', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (v) => notifier.setThemeMode(v.first),
              ),
              const SizedBox(height: 24),

              // Primary color
              Text('Primary Color', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AppTheme.availableColors.map((color) {
                  final selected = settings.seedColor == color;
                  return GestureDetector(
                    onTap: () => notifier.setSeedColor(color),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: selected
                            ? Border.all(
                                color: theme.colorScheme.onSurface, width: 3)
                            : null,
                      ),
                      child: selected
                          ? Icon(Icons.check,
                              color: color.computeLuminance() > 0.5
                                  ? Colors.black
                                  : Colors.white,
                              size: 20)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Font family
              Text('Font Family', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: settings.fontFamily,
                decoration: const InputDecoration(labelText: 'Font Family'),
                items: AppTheme.availableFonts
                    .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) notifier.setFontFamily(v);
                },
              ),
              const SizedBox(height: 24),

              // Font size
              Text(
                  'Font Size Factor: ${settings.fontSizeFactor.toStringAsFixed(1)}',
                  style: theme.textTheme.titleMedium),
              Slider(
                value: settings.fontSizeFactor,
                min: 0.7,
                max: 1.5,
                divisions: 8,
                label: settings.fontSizeFactor.toStringAsFixed(1),
                onChanged: (v) => notifier.setFontSizeFactor(v),
              ),
              const SizedBox(height: 32),

              // Change password
              const Divider(),
              const SizedBox(height: 16),
              Text('Account', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _showChangePassword(context, ref),
                icon: const Icon(Icons.lock),
                label: const Text('Change Password'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChangePassword(BuildContext context, WidgetRef ref) {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Password'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: currentCtrl,
                decoration:
                    const InputDecoration(labelText: 'Current Password'),
                obscureText: true,
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: newCtrl,
                decoration: const InputDecoration(labelText: 'New Password'),
                obscureText: true,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (v.length < 4) return 'Min 4 characters';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: confirmCtrl,
                decoration:
                    const InputDecoration(labelText: 'Confirm New Password'),
                obscureText: true,
                validator: (v) {
                  if (v != newCtrl.text) return 'Passwords do not match';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final db = ref.read(databaseProvider);
              final auth = ref.read(authProvider);
              if (auth.username == null) return;

              final user = await db.getUserByUsername(auth.username!);
              if (user == null) return;

              if (!verifyPassword(currentCtrl.text, user.passwordHash)) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                        content: Text('Current password is incorrect')),
                  );
                }
                return;
              }

              final newHash = hashPassword(newCtrl.text);
              await db.updateUser(User(
                id: user.id,
                username: user.username,
                passwordHash: newHash,
                createdAt: user.createdAt,
              ));

              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                      content: Text('Password changed successfully')),
                );
              }
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }
}
