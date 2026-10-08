import 'package:flutter/material.dart';

import 'discover/discover_page.dart';
import 'library/library_page.dart';
import 'settings/settings_page.dart';

/// Главная оболочка: Discover / Library / Настройки с «пилюлей» на активном табе.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [DiscoverPage(), LibraryPage(), SettingsPage()],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.08), blurRadius: 8),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _tab(0, Icons.explore_outlined, 'Discover'),
                _tab(1, Icons.menu_book_outlined, 'Library'),
                _tab(2, Icons.settings_outlined, 'Настройки'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(int index, IconData icon, String label) {
    final theme = Theme.of(context);
    final active = _index == index;
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => setState(() => _index = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF1B3A6B) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 22,
                color: active
                    ? Colors.white
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            if (active) ...[
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }
}
