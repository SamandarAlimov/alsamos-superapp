import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_shell_page.dart';

/// Settings page entry point - redirects to responsive shell
/// This maintains backward compatibility with existing routes
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mobile/Tablet: Show list only (push navigation to sub-pages)
    // Desktop: Show master-detail with empty state (select item from list)
    return const SettingsShellPage();
  }
}
