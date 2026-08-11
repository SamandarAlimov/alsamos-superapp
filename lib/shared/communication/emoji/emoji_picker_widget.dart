import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import 'animated_emoji.dart';
import 'emoji_manager.dart';

enum EmojiPickerStyle { sheet, inline, compact }

class EmojiPickerWidget extends ConsumerStatefulWidget {
  final ValueChanged<String> onSelect;
  final EmojiPickerStyle style;
  final double? height;
  final int crossAxisCount;

  const EmojiPickerWidget({
    super.key,
    required this.onSelect,
    this.style = EmojiPickerStyle.sheet,
    this.height,
    this.crossAxisCount = 8,
  });

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _EmojiPickerSheet(),
    );
  }

  @override
  ConsumerState<EmojiPickerWidget> createState() => _EmojiPickerWidgetState();
}

class _EmojiPickerWidgetState extends ConsumerState<EmojiPickerWidget>
    with SingleTickerProviderStateMixin {
  late final EmojiManager _manager;
  late final TabController _tab;
  final _searchCtrl = TextEditingController();
  List<String>? _searchResults;

  @override
  void initState() {
    super.initState();
    _manager = ref.read(emojiManagerProvider);
    _tab =
        TabController(length: EmojiManager.categories.length + 1, vsync: this);
    _searchCtrl.addListener(_onSearch);
  }

  void _onSearch() {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      setState(() => _searchResults = null);
    } else {
      setState(() => _searchResults = _manager.search(q));
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _select(String emoji) {
    HapticFeedback.selectionClick();
    _manager.recordUsage(emoji);
    widget.onSelect(emoji);
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      height: widget.height ?? MediaQuery.of(context).size.height * 0.45,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: widget.style == EmojiPickerStyle.inline
            ? null
            : const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        if (widget.style != EmojiPickerStyle.inline)
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 38,
            height: 4,
            decoration: BoxDecoration(
                color: c.mutedForeground.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2)),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Emoji qidirish...',
              prefixIcon:
                  Icon(Icons.search, size: 18, color: c.mutedForeground),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon:
                          Icon(Icons.close, size: 16, color: c.mutedForeground),
                      onPressed: () => _searchCtrl.clear())
                  : null,
              filled: true,
              fillColor: c.muted,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
          ),
        ),
        if (_searchResults == null) ...[
          TabBar(
            controller: _tab,
            isScrollable: true,
            labelColor: primary,
            unselectedLabelColor: c.mutedForeground,
            indicatorColor: primary,
            indicatorWeight: 2,
            tabAlignment: TabAlignment.start,
            tabs: [
              const Tab(text: '\u{1F553}'),
              ...EmojiManager.categories.map((e) => Tab(text: e.icon)),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _buildRecentTab(c),
                ...EmojiManager.categories.map((cat) => _buildGrid(cat.emojis)),
              ],
            ),
          ),
        ] else
          Expanded(child: _buildGrid(_searchResults!)),
      ]),
    );
  }

  Widget _buildRecentTab(AlsamosColors c) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: _manager.recentEmojis,
      builder: (_, recent, __) {
        if (recent.isEmpty) {
          return Center(
            child: Text('Hali emoji ishlatilmagan',
                style: TextStyle(fontSize: 13, color: c.mutedForeground)),
          );
        }
        return _buildGrid(recent);
      },
    );
  }

  Widget _buildGrid(List<String> emojis) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.crossAxisCount,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: emojis.length,
      itemBuilder: (_, i) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _select(emojis[i]),
        onLongPress: () {
          HapticFeedback.mediumImpact();
          _manager.toggleFavorite(emojis[i]);
        },
        child: Center(
          child: AnimatedEmoji(emoji: emojis[i], size: 30),
        ),
      ),
    );
  }
}

class _EmojiPickerSheet extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return EmojiPickerWidget(
      onSelect: (emoji) => Navigator.pop(context, emoji),
      style: EmojiPickerStyle.sheet,
    );
  }
}
