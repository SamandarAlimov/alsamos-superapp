// CategoryFilterBar - Horizontal scrollable category chips
// Filters discovery content and persists user interests

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';

class Category {
  final String id;
  final String name;
  final String nameUz;
  final String nameEn;
  final String nameRu;
  final String? icon;
  final String? color;
  final int displayOrder;

  const Category({
    required this.id,
    required this.name,
    required this.nameUz,
    required this.nameEn,
    required this.nameRu,
    this.icon,
    this.color,
    this.displayOrder = 0,
  });

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as String,
      name: map['name'] as String,
      nameUz: map['name_uz'] as String,
      nameEn: map['name_en'] as String,
      nameRu: map['name_ru'] as String,
      icon: map['icon'] as String?,
      color: map['color'] as String?,
      displayOrder: (map['display_order'] as int?) ?? 0,
    );
  }

  String getLocalizedName(String locale) {
    switch (locale) {
      case 'uz':
        return nameUz;
      case 'ru':
        return nameRu;
      case 'en':
      default:
        return nameEn;
    }
  }
}

// Provider for selected categories
final selectedCategoriesProvider =
    StateProvider<Set<String>>((ref) => {'all'});

// Provider for available categories
final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  try {
    final rows = await Supabase.instance.client
        .from('categories')
        .select()
        .eq('is_active', true)
        .order('display_order');

    return (rows as List)
        .map((r) => Category.fromMap(r as Map<String, dynamic>))
        .toList();
  } catch (e) {
    print('Error loading categories: $e');
    return [];
  }
});

class CategoryFilterBar extends ConsumerStatefulWidget {
  final ValueChanged<Set<String>>? onCategoriesChanged;

  const CategoryFilterBar({
    super.key,
    this.onCategoriesChanged,
  });

  @override
  ConsumerState<CategoryFilterBar> createState() =>
      _CategoryFilterBarState();
}

class _CategoryFilterBarState extends ConsumerState<CategoryFilterBar> {
  @override
  void initState() {
    super.initState();
    _loadUserInterests();
  }

  Future<void> _loadUserInterests() async {
    try {
      final supa = Supabase.instance.client;
      final userId = supa.auth.currentUser?.id;
      if (userId == null) return;

      final rows = await supa
          .from('user_interests')
          .select('category_id, categories!inner(name)')
          .eq('user_id', userId);

      if (!mounted) return;

      final categoryNames = (rows as List)
          .map((r) => r['categories']['name'] as String)
          .toSet();

      if (categoryNames.isNotEmpty) {
        ref.read(selectedCategoriesProvider.notifier).state =
            categoryNames;
        widget.onCategoriesChanged?.call(categoryNames);
      }
    } catch (e) {
      print('Error loading user interests: $e');
    }
  }

  Future<void> _toggleCategory(String categoryName, String categoryId) async {
    HapticFeedback.lightImpact();

    final selected = ref.read(selectedCategoriesProvider);
    final newSelected = Set<String>.from(selected);

    // Handle "All" category
    if (categoryName == 'all') {
      newSelected.clear();
      newSelected.add('all');
    } else {
      newSelected.remove('all');
      if (newSelected.contains(categoryName)) {
        newSelected.remove(categoryName);
      } else {
        newSelected.add(categoryName);
      }
      
      // If empty, default to 'all'
      if (newSelected.isEmpty) {
        newSelected.add('all');
      }
    }

    ref.read(selectedCategoriesProvider.notifier).state = newSelected;
    widget.onCategoriesChanged?.call(newSelected);

    // Persist to database
    await _persistInterests(newSelected, categoryId);
  }

  Future<void> _persistInterests(
      Set<String> categories, String? toggledCategoryId) async {
    try {
      final supa = Supabase.instance.client;
      final userId = supa.auth.currentUser?.id;
      if (userId == null || toggledCategoryId == null) return;

      if (categories.contains('all') || categories.isEmpty) {
        // Clear all interests
        await supa
            .from('user_interests')
            .delete()
            .eq('user_id', userId);
      } else {
        // Get category IDs for selected categories
        final categoryRows = await supa
            .from('categories')
            .select('id, name')
            .inFilter('name', categories.toList());

        final categoryIds = (categoryRows as List)
            .map((r) => r['id'] as String)
            .toList();

        // Delete old interests and insert new ones
        await supa
            .from('user_interests')
            .delete()
            .eq('user_id', userId);

        if (categoryIds.isNotEmpty) {
          await supa.from('user_interests').insert(
                categoryIds
                    .map((id) => {
                          'user_id': userId,
                          'category_id': id,
                          'weight': 1.0,
                        })
                    .toList(),
              );
        }
      }
    } catch (e) {
      print('Error persisting interests: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final categoriesAsync = ref.watch(categoriesProvider);
    final selected = ref.watch(selectedCategoriesProvider);

    return categoriesAsync.when(
      loading: () => _Skeleton(c: c),
      error: (_, __) => const SizedBox.shrink(),
      data: (categories) {
        if (categories.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.filter, size: 20, color: primary),
                const SizedBox(width: 8),
                Text(
                  'Categories',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: c.foreground,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final category = categories[index];
                  final isSelected = selected.contains(category.name);

                  return _CategoryChip(
                    category: category,
                    isSelected: isSelected,
                    onTap: () =>
                        _toggleCategory(category.name, category.id),
                    primary: primary,
                    c: c,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CategoryChip extends StatefulWidget {
  final Category category;
  final bool isSelected;
  final VoidCallback onTap;
  final Color primary;
  final AlsamosColors c;

  const _CategoryChip({
    required this.category,
    required this.isSelected,
    required this.onTap,
    required this.primary,
    required this.c,
  });

  @override
  State<_CategoryChip> createState() => _CategoryChipState();
}

class _CategoryChipState extends State<_CategoryChip> {
  bool _hover = false;

  IconData _getIcon(String? iconName) {
    switch (iconName) {
      case 'trophy':
        return LucideIcons.trophy;
      case 'music':
        return LucideIcons.music;
      case 'cpu':
        return LucideIcons.cpu;
      case 'shirt':
        return LucideIcons.shirt;
      case 'utensils':
        return LucideIcons.utensils;
      case 'plane':
        return LucideIcons.plane;
      case 'gamepad2':
        return LucideIcons.gamepad2;
      case 'palette':
        return LucideIcons.palette;
      case 'graduationCap':
        return LucideIcons.graduationCap;
      case 'briefcase':
        return LucideIcons.briefcase;
      case 'heart':
        return LucideIcons.heart;
      case 'grid':
      default:
        return LucideIcons.grid;
    }
  }

  Color _parseColor(String? colorStr, Color fallback) {
    if (colorStr == null || !colorStr.startsWith('#')) return fallback;
    try {
      return Color(int.parse(colorStr.substring(1), radix: 16) + 0xFF000000);
    } catch (_) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final primary = widget.primary;
    final chipColor = _parseColor(widget.category.color, primary);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? chipColor
                : (_hover
                    ? c.muted.withValues(alpha: 0.8)
                    : c.muted.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.isSelected
                  ? chipColor
                  : (_hover ? chipColor.withValues(alpha: 0.3) : c.border),
              width: widget.isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getIcon(widget.category.icon),
                size: 16,
                color: widget.isSelected ? Colors.white : c.foreground,
              ),
              const SizedBox(width: 6),
              Text(
                widget.category.nameEn, // Using English for now
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: widget.isSelected ? Colors.white : c.foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  final AlsamosColors c;

  const _Skeleton({required this.c});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 100,
          height: 18,
          decoration: BoxDecoration(
            color: c.muted,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 5,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, __) => Container(
              width: 80,
              height: 40,
              decoration: BoxDecoration(
                color: c.muted,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
