import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/i18n/app_strings.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/error_mapper.dart';
import '../../data/history_repository.dart';

/// Content type filter for history
enum ContentTypeFilter {
  all,
  video,
  post,
  product,
  channel,
  article,
}

/// Watch/View History page - YouTube/Instagram style content history
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  ContentTypeFilter _selectedFilter = ContentTypeFilter.all;
  bool _isLoading = true;
  String? _error;
  bool _isPaused = false;
  
  List<ViewHistoryItem> _historyItems = [];
  final _scrollController = ScrollController();
  bool _isLoadingMore = false;
  bool _hasMore = true;
  
  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadPauseState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMore) {
        _loadMore();
      }
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final repo = ref.read(historyRepositoryProvider);
      final contentType = _selectedFilter == ContentTypeFilter.all
          ? null
          : _selectedFilter.name;
      
      final data = await repo.getHistory(
        userId: userId,
        contentType: contentType,
        limit: 50,
        offset: 0,
      );

      if (mounted) {
        setState(() {
          _historyItems = data.map((e) => ViewHistoryItem.fromMap(e)).toList();
          _isLoading = false;
          _hasMore = data.length >= 50;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    
    setState(() => _isLoadingMore = true);

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final repo = ref.read(historyRepositoryProvider);
      final contentType = _selectedFilter == ContentTypeFilter.all
          ? null
          : _selectedFilter.name;
      
      final data = await repo.getHistory(
        userId: userId,
        contentType: contentType,
        limit: 50,
        offset: _historyItems.length,
      );

      if (mounted) {
        setState(() {
          _historyItems.addAll(data.map((e) => ViewHistoryItem.fromMap(e)));
          _isLoadingMore = false;
          _hasMore = data.length >= 50;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Future<void> _loadPauseState() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final repo = ref.read(historyRepositoryProvider);
      final paused = await repo.isHistoryPaused(userId);
      
      if (mounted) {
        setState(() => _isPaused = paused);
      }
    } catch (e) {
      // Ignore error
    }
  }

  Future<void> _togglePause() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final newState = !_isPaused;
    setState(() => _isPaused = newState);

    try {
      final repo = ref.read(historyRepositoryProvider);
      await repo.setHistoryPaused(userId: userId, paused: newState);
      
      if (mounted) {
        AppToast.info(context, newState 
          ? AppStrings.of(ref).t('history.paused')
          : AppStrings.of(ref).t('history.resumed'));
      }
    } catch (e) {
      // Rollback on error
      setState(() => _isPaused = !newState);
      if (mounted) {
        AppToast.error(context, friendlyError(e));
      }
    }
  }

  Future<void> _clearAllHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.of(ref).t('history.clearAll')),
        content: Text(AppStrings.of(ref).t('history.clearConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.of(ref).t('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(AppStrings.of(ref).t('common.delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final repo = ref.read(historyRepositoryProvider);
      await repo.clearAllHistory(userId);

      setState(() {
        _historyItems = [];
      });

      if (mounted) {
        AppToast.success(context, AppStrings.of(ref).t('history.cleared'));
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, friendlyError(e));
      }
    }
  }

  Future<void> _removeItem(String id) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final repo = ref.read(historyRepositoryProvider);
      await repo.removeHistoryItem(userId: userId, historyId: id);

      setState(() {
        _historyItems.removeWhere((item) => item.id == id);
      });
    } catch (e) {
      if (mounted) {
        AppToast.error(context, friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.card,
        elevation: 0,
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: c.foreground),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          AppStrings.of(ref).t('settings.items.history'),
          style: TextStyle(
            color: c.foreground,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          // Pause toggle
          IconButton(
            icon: Icon(
              _isPaused ? LucideIcons.play : LucideIcons.pause,
              color: _isPaused ? Colors.orange : c.foreground,
            ),
            onPressed: _togglePause,
            tooltip: _isPaused ? 'Davom ettirish' : 'To\'xtatish',
          ),
          // More menu
          PopupMenuButton<String>(
            icon: Icon(LucideIcons.moreVertical, color: c.foreground),
            onSelected: (value) {
              if (value == 'clear') {
                _clearAllHistory();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(LucideIcons.trash2, size: 18, color: Colors.red),
                    const SizedBox(width: 12),
                    const Text(
                      'Barcha tarixni tozalash',
                      style: TextStyle(color: Colors.red),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Content type filter chips
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: c.card,
              border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.3))),
            ),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _filterChip('Hammasi', ContentTypeFilter.all, LucideIcons.list, c, theme),
                const SizedBox(width: 8),
                _filterChip('Videolar', ContentTypeFilter.video, LucideIcons.video, c, theme),
                const SizedBox(width: 8),
                _filterChip('Postlar', ContentTypeFilter.post, LucideIcons.fileText, c, theme),
                const SizedBox(width: 8),
                _filterChip('Mahsulotlar', ContentTypeFilter.product, LucideIcons.shoppingBag, c, theme),
                const SizedBox(width: 8),
                _filterChip('Kanallar', ContentTypeFilter.channel, LucideIcons.radio, c, theme),
              ],
            ),
          ),

          // Pause notice
          if (_isPaused)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.pause, size: 20, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tarix yozish to\'xtatilgan',
                      style: TextStyle(fontSize: 13, color: c.foreground),
                    ),
                  ),
                ],
              ),
            ),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _errorState(c)
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: _buildContent(c, theme),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, ContentTypeFilter filter, IconData icon, AlsamosColors c, ThemeData theme) {
    final isSelected = _selectedFilter == filter;
    final primary = theme.colorScheme.primary;

    return GestureDetector(
      onTap: () {
        setState(() => _selectedFilter = filter);
        _loadData();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? primary.withValues(alpha: 0.15) : c.muted.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? primary : c.mutedForeground),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? primary : c.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(AlsamosColors c, ThemeData theme) {
    if (_historyItems.isEmpty) {
      return _emptyState(c);
    }

    // Group items by date
    final groupedItems = _groupByDate(_historyItems);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: groupedItems.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == groupedItems.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final entry = groupedItems[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date header
            Padding(
              padding: EdgeInsets.only(bottom: 12, top: index == 0 ? 0 : 12),
              child: Text(
                entry.dateLabel,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: c.foreground,
                ),
              ),
            ),
            // Items for this date
            ...entry.items.map((item) => _historyItemTile(item, c, theme)),
          ],
        );
      },
    );
  }

  List<DateGroup> _groupByDate(List<ViewHistoryItem> items) {
    final groups = <String, List<ViewHistoryItem>>{};
    final now = DateTime.now();

    for (final item in items) {
      final date = item.viewedAt.toLocal();
      String label;

      if (_isSameDay(date, now)) {
        label = 'Bugun';
      } else if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
        label = 'Kecha';
      } else if (now.difference(date).inDays < 7) {
        label = DateFormat('EEEE').format(date); // Day name
      } else {
        label = DateFormat('dd MMMM yyyy').format(date);
      }

      groups.putIfAbsent(label, () => []).add(item);
    }

    return groups.entries
        .map((e) => DateGroup(dateLabel: e.key, items: e.value))
        .toList();
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _historyItemTile(ViewHistoryItem item, AlsamosColors c, ThemeData theme) {
    final icon = _getContentTypeIcon(item.contentType);
    final iconColor = _getContentTypeColor(item.contentType);
    final time = _formatRelativeTime(item.viewedAt);

    return GestureDetector(
      onTap: () => _navigateToContent(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              child: Container(
                width: 120,
                height: 90,
                color: c.muted,
                child: item.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: item.thumbnailUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Center(
                          child: Icon(icon, size: 32, color: iconColor.withValues(alpha: 0.5)),
                        ),
                        errorWidget: (_, __, ___) => Center(
                          child: Icon(icon, size: 32, color: iconColor.withValues(alpha: 0.5)),
                        ),
                      )
                    : Center(
                        child: Icon(icon, size: 32, color: iconColor.withValues(alpha: 0.5)),
                      ),
              ),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      item.title ?? 'Untitled',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.foreground,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // Author/Source
                    if (item.author != null)
                      Text(
                        item.author!,
                        style: TextStyle(
                          fontSize: 12,
                          color: c.mutedForeground,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),

                    const SizedBox(height: 6),

                    // Content type badge + time
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: iconColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon, size: 10, color: iconColor),
                              const SizedBox(width: 4),
                              Text(
                                _getContentTypeLabel(item.contentType),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: iconColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: 11,
                            color: c.mutedForeground.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),

                    // Progress bar for videos
                    if (item.contentType == 'video' && item.progress != null && item.progress! > 0) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: item.progress!,
                          backgroundColor: c.muted,
                          valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                          minHeight: 3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Overflow menu
            PopupMenuButton(
              icon: Icon(LucideIcons.moreVertical, size: 18, color: c.mutedForeground),
              itemBuilder: (context) => [
                PopupMenuItem(
                  onTap: () => _removeItem(item.id),
                  child: Row(
                    children: [
                      Icon(LucideIcons.trash2, size: 16, color: Colors.red),
                      const SizedBox(width: 12),
                      Text(
                        'Tarixdan o\'chirish',
                        style: TextStyle(color: Colors.red),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToContent(ViewHistoryItem item) {
    // Navigate to content based on type
    switch (item.contentType) {
      case 'video':
        context.push('/videos/${item.contentId}');
        break;
      case 'post':
        context.push('/posts/${item.contentId}');
        break;
      case 'product':
        context.push('/marketplace/products/${item.contentId}');
        break;
      case 'channel':
        context.push('/channels/${item.contentId}');
        break;
      case 'article':
        context.push('/articles/${item.contentId}');
        break;
    }
  }

  Widget _emptyState(AlsamosColors c) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.clock,
            size: 64,
            color: c.mutedForeground.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Tarix bo\'sh',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: c.foreground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ko\'rgan kontentlaringiz bu yerda ko\'rinadi',
            style: TextStyle(
              fontSize: 14,
              color: c.mutedForeground,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _errorState(AlsamosColors c) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.alertCircle, size: 64, color: Colors.red.withValues(alpha: 0.7)),
          const SizedBox(height: 16),
          Text(
            'Xatolik yuz berdi',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: c.foreground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error ?? 'Unknown error',
            style: TextStyle(fontSize: 14, color: c.mutedForeground),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Qayta urinish'),
          ),
        ],
      ),
    );
  }

  IconData _getContentTypeIcon(String contentType) {
    switch (contentType) {
      case 'video':
        return LucideIcons.video;
      case 'post':
        return LucideIcons.fileText;
      case 'product':
        return LucideIcons.shoppingBag;
      case 'channel':
        return LucideIcons.radio;
      case 'article':
        return LucideIcons.newspaper;
      case 'story':
        return LucideIcons.zap;
      default:
        return LucideIcons.file;
    }
  }

  Color _getContentTypeColor(String contentType) {
    switch (contentType) {
      case 'video':
        return Colors.red;
      case 'post':
        return Colors.blue;
      case 'product':
        return Colors.green;
      case 'channel':
        return Colors.purple;
      case 'article':
        return Colors.orange;
      case 'story':
        return Colors.pink;
      default:
        return Colors.grey;
    }
  }

  String _getContentTypeLabel(String contentType) {
    switch (contentType) {
      case 'video':
        return 'Video';
      case 'post':
        return 'Post';
      case 'product':
        return 'Mahsulot';
      case 'channel':
        return 'Kanal';
      case 'article':
        return 'Maqola';
      case 'story':
        return 'Hikoya';
      default:
        return contentType;
    }
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Hozirgina';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} daqiqa oldin';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} soat oldin';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} kun oldin';
    } else {
      return DateFormat('dd MMM yyyy').format(dateTime);
    }
  }
}

/// View history item model
class ViewHistoryItem {
  final String id;
  final String userId;
  final String contentType;
  final String contentId;
  final double? progress;
  final DateTime viewedAt;
  final String? title;
  final String? author;
  final String? thumbnailUrl;

  const ViewHistoryItem({
    required this.id,
    required this.userId,
    required this.contentType,
    required this.contentId,
    this.progress,
    required this.viewedAt,
    this.title,
    this.author,
    this.thumbnailUrl,
  });

  factory ViewHistoryItem.fromMap(Map<String, dynamic> m) => ViewHistoryItem(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        contentType: m['content_type'] as String,
        contentId: m['content_id'] as String,
        progress: m['progress'] != null ? (m['progress'] as num).toDouble() : null,
        viewedAt: DateTime.parse(m['viewed_at'] as String).toLocal(),
        title: m['title'] as String?,
        author: m['author'] as String?,
        thumbnailUrl: m['thumbnail_url'] as String?,
      );
}

/// Date group for history items
class DateGroup {
  final String dateLabel;
  final List<ViewHistoryItem> items;

  const DateGroup({
    required this.dateLabel,
    required this.items,
  });
}

/// Security event model
class SecurityEvent {
  final String id;
  final String userId;
  final String eventType;
  final String description;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;

  const SecurityEvent({
    required this.id,
    required this.userId,
    required this.eventType,
    required this.description,
    required this.createdAt,
    this.metadata,
  });

  factory SecurityEvent.fromMap(Map<String, dynamic> m) => SecurityEvent(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        eventType: m['event_type'] as String,
        description: m['description'] as String,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        metadata: m['metadata'] as Map<String, dynamic>?,
      );
}

/// Search history item model
class SearchHistoryItem {
  final String id;
  final String userId;
  final String query;
  final DateTime createdAt;

  const SearchHistoryItem({
    required this.id,
    required this.userId,
    required this.query,
    required this.createdAt,
  });

  factory SearchHistoryItem.fromMap(Map<String, dynamic> m) => SearchHistoryItem(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        query: m['query'] as String,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );
}
