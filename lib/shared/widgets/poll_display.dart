// v32: PollDisplay widget — port of web `src/components/PollDisplay.tsx` (296L).
// UI-only: ovoz berish holati local state'da; backend wiring (polls table)
// keyingi bosqichda. Web bilan 1:1 visual parity.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app/theme/app_theme.dart';
import 'app_toast.dart';
import 'error_mapper.dart';

class PollOption {
  final String id;
  final String text;
  final int votes;
  final String? mediaUrl;
  final String? mediaType;
  final bool isCorrect;
  const PollOption({
    required this.id,
    required this.text,
    required this.votes,
    this.mediaUrl,
    this.mediaType,
    this.isCorrect = false,
  });

  PollOption copyWith({int? votes}) => PollOption(
        id: id,
        text: text,
        votes: votes ?? this.votes,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        isCorrect: isCorrect,
      );

  factory PollOption.fromMap(Map<String, dynamic> m) => PollOption(
        id: m['id'] as String,
        text: (m['text'] as String?) ?? '',
        votes: (m['votes'] as int?) ?? 0,
        mediaUrl: m['mediaUrl']?.toString() ?? m['media_url']?.toString(),
        mediaType: m['mediaType']?.toString() ?? m['media_type']?.toString(),
        isCorrect: m['isCorrect'] == true || m['is_correct'] == true,
      );

  factory PollOption.fromAny(Object? value, int index) {
    if (value is Map) {
      return PollOption.fromMap(Map<String, dynamic>.from(value));
    }
    return PollOption(
      id: 'opt_${index + 1}',
      text: value?.toString() ?? '',
      votes: 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'text': text,
        'votes': votes,
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
        if (mediaType != null) 'mediaType': mediaType,
        if (isCorrect) 'isCorrect': true,
      };
}

class PollData {
  final String question;
  final List<PollOption> options;

  /// '1h' | '6h' | '1d' | '3d' | '7d'
  final String duration;
  final bool allowMultiple;
  final bool isAnonymous;
  final bool isQuiz;
  final String resultsMode;
  final DateTime createdAt;
  final DateTime? expiresAt;

  const PollData({
    required this.question,
    required this.options,
    required this.duration,
    required this.allowMultiple,
    required this.isAnonymous,
    required this.isQuiz,
    required this.resultsMode,
    required this.createdAt,
    this.expiresAt,
  });

  DateTime get expiryDate {
    if (expiresAt != null) return expiresAt!;
    switch (duration) {
      case '1h':
      case 'hour':
        return createdAt.add(const Duration(hours: 1));
      case '6h':
      case 'sixHours':
        return createdAt.add(const Duration(hours: 6));
      case '1d':
      case 'day':
        return createdAt.add(const Duration(days: 1));
      case '3d':
      case 'threeDays':
        return createdAt.add(const Duration(days: 3));
      case '7d':
      case 'week':
        return createdAt.add(const Duration(days: 7));
      case '14d':
      case 'twoWeeks':
        return createdAt.add(const Duration(days: 14));
      default:
        return createdAt.add(const Duration(days: 1));
    }
  }

  bool get isExpired => DateTime.now().isAfter(expiryDate);

  factory PollData.fromMap(Map<String, dynamic> m) => PollData(
        question: (m['question'] as String?) ?? '',
        options: [
          for (var i = 0; i < ((m['options'] as List?) ?? const []).length; i++)
            PollOption.fromAny(((m['options'] as List?) ?? const [])[i], i),
        ],
        duration: (m['duration'] as String?) ?? '1d',
        allowMultiple: (m['allowMultiple'] as bool?) ?? false,
        isAnonymous: (m['isAnonymous'] as bool?) ?? false,
        isQuiz: (m['isQuiz'] as bool?) ?? false,
        resultsMode: (m['resultsMode'] as String?) ?? 'afterVote',
        createdAt: DateTime.tryParse((m['createdAt'] as String?) ?? '') ??
            DateTime.now(),
        expiresAt: DateTime.tryParse((m['expiresAt'] as String?) ?? ''),
      );

  /// Web ekvivalenti `parsePollFromContent()` — `[POLL]{...}[/POLL]` blokini
  /// post content'idan ajratib oladi.
  static (PollData?, String) parseFromContent(String content) {
    final reg = RegExp(r'\[POLL\](.*?)\[/POLL\]', dotAll: true);
    final match = reg.firstMatch(content);
    if (match == null) return (null, content);
    try {
      final raw = match.group(1) ?? '';
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final data = PollData.fromMap(decoded);
      final clean = content.replaceFirst(reg, '').trim();
      return (data, clean);
    } catch (_) {
      return (null, content);
    }
  }
}

class PollDisplay extends StatefulWidget {
  final String postId;
  final PollData pollData;
  final VoidCallback? onVote;
  const PollDisplay(
      {super.key, required this.postId, required this.pollData, this.onVote});

  @override
  State<PollDisplay> createState() => _PollDisplayState();
}

class _PollDisplayState extends State<PollDisplay> {
  late List<PollOption> _options;
  final Set<String> _selected = {};
  RealtimeChannel? _votesChannel;
  bool _hasVoted = false;
  bool _isVoting = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _options = List.of(widget.pollData.options);
    _loadUserVote();
    _subscribeToVotes();
  }

  @override
  void didUpdateWidget(covariant PollDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postId != widget.postId) {
      _unsubscribeFromVotes();
      _options = List.of(widget.pollData.options);
      _selected.clear();
      _hasVoted = false;
      _isLoading = true;
      _loadUserVote();
      _subscribeToVotes();
    }
  }

  @override
  void dispose() {
    _unsubscribeFromVotes();
    super.dispose();
  }

  void _subscribeToVotes() {
    final supa = Supabase.instance.client;
    _votesChannel = supa
        .channel('post_poll_votes:${widget.postId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'poll_votes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'post_id',
            value: widget.postId,
          ),
          callback: (_) => _loadUserVote(showSpinner: false),
        )
        .subscribe();
  }

  void _unsubscribeFromVotes() {
    final channel = _votesChannel;
    if (channel == null) return;
    _votesChannel = null;
    Supabase.instance.client.removeChannel(channel);
  }

  Future<void> _loadUserVote({bool showSpinner = true}) async {
    try {
      final supa = Supabase.instance.client;
      final userId = supa.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      if (showSpinner && mounted) {
        setState(() => _isLoading = true);
      }

      final response = await supa
          .from('poll_votes')
          .select('option_id,user_id')
          .eq('post_id', widget.postId)
          .order('updated_at', ascending: false);

      final counts = {for (final option in _options) option.id: 0};
      final selected = <String>{};
      for (final row in response as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final ids = _parseVoteIds(map['option_id']?.toString());
        for (final id in ids) {
          if (counts.containsKey(id)) counts[id] = counts[id]! + 1;
        }
        if (map['user_id']?.toString() == userId) {
          selected.addAll(ids);
        }
      }
      if (mounted) {
        setState(() {
          _options = _options
              .map((option) =>
                  option.copyWith(votes: counts[option.id] ?? option.votes))
              .toList();
          _selected
            ..clear()
            ..addAll(selected);
          _hasVoted = selected.isNotEmpty;
        });
      }
    } catch (e) {
      print('Error loading user vote: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  int get _totalVotes => _options.fold<int>(0, (s, o) => s + o.votes);
  int _percentage(int votes) =>
      _totalVotes == 0 ? 0 : ((votes / _totalVotes) * 100).round();

  List<String> _parseVoteIds(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    return raw
        .split(',')
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  void _tap(String id) {
    if (_hasVoted || widget.pollData.isExpired || _isLoading) return;
    setState(() {
      if (widget.pollData.allowMultiple) {
        if (_selected.contains(id)) {
          _selected.remove(id);
        } else {
          _selected.add(id);
        }
      } else {
        _selected
          ..clear()
          ..add(id);
      }
    });
  }

  Future<void> _vote() async {
    if (_selected.isEmpty ||
        _hasVoted ||
        widget.pollData.isExpired ||
        _isLoading) {
      return;
    }

    setState(() => _isVoting = true);

    // Optimistic update
    final originalOptions = List<PollOption>.from(_options);
    setState(() {
      _options = _options
          .map((o) =>
              _selected.contains(o.id) ? o.copyWith(votes: o.votes + 1) : o)
          .toList();
      _hasVoted = true;
    });

    try {
      final supa = Supabase.instance.client;
      final userId = supa.auth.currentUser?.id;
      if (userId == null) throw Exception('Not authenticated');

      await supa.from('poll_votes').upsert({
        'post_id': widget.postId,
        'user_id': userId,
        'option_id': _selected.join(','),
        'updated_at': DateTime.now().toIso8601String(),
      });

      widget.onVote?.call();
    } catch (e) {
      // Rollback on error
      if (mounted) {
        setState(() {
          _options = originalOptions;
          _hasVoted = false;
        });
        AppToast.error(context, friendlyError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _isVoting = false);
      }
    }
  }

  String _timeLeftLabel() {
    if (widget.pollData.isExpired) return 'So\'rovnoma yakunlandi';
    final diff = widget.pollData.expiryDate.difference(DateTime.now());
    if (diff.inMinutes < 60) return 'Tugaydi: ${diff.inMinutes} daq.';
    if (diff.inHours < 24) return 'Tugaydi: ${diff.inHours} soat';
    return 'Tugaydi: ${diff.inDays} kun';
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    final showResults = widget.pollData.resultsMode == 'always' ||
        widget.pollData.isExpired ||
        (widget.pollData.resultsMode == 'afterVote' && _hasVoted);

    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondary.withValues(alpha: 0.30),
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary.withValues(alpha: 0.30),
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(LucideIcons.barChart3, color: c.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.pollData.question,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 18)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(LucideIcons.users,
                              size: 14, color: c.mutedForeground),
                          const SizedBox(width: 4),
                          Text('$_totalVotes ovoz',
                              style: TextStyle(
                                  fontSize: 12, color: c.mutedForeground)),
                        ]),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(LucideIcons.clock,
                              size: 14, color: c.mutedForeground),
                          const SizedBox(width: 4),
                          Text(_timeLeftLabel(),
                              style: TextStyle(
                                  fontSize: 12, color: c.mutedForeground)),
                        ]),
                        if (widget.pollData.isQuiz)
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(LucideIcons.badgeCheck,
                                size: 14, color: c.mutedForeground),
                            const SizedBox(width: 4),
                            Text('Quiz',
                                style: TextStyle(
                                    fontSize: 12, color: c.mutedForeground)),
                          ]),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final o in _options) ...[
            _OptionRow(
              option: o,
              isSelected: _selected.contains(o.id),
              showResults: showResults,
              percentage: _percentage(o.votes),
              allowMultiple: widget.pollData.allowMultiple,
              isQuiz: widget.pollData.isQuiz,
              onTap: () => _tap(o.id),
            ),
            const SizedBox(height: 8),
          ],
          if (!_hasVoted && !widget.pollData.isExpired) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: ElevatedButton(
                onPressed: _selected.isEmpty || _isVoting ? null : _vote,
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.primary,
                  foregroundColor: c.primaryForeground,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(_isVoting ? 'Yuborilmoqda…' : 'Ovoz berish'),
              ),
            ),
          ],
          if (widget.pollData.isAnonymous) ...[
            const SizedBox(height: 8),
            Center(
              child: Text('Ovoz berish anonim',
                  style: TextStyle(fontSize: 11, color: c.mutedForeground)),
            ),
          ],
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final PollOption option;
  final bool isSelected;
  final bool showResults;
  final int percentage;
  final bool allowMultiple;
  final bool isQuiz;
  final VoidCallback onTap;
  const _OptionRow({
    required this.option,
    required this.isSelected,
    required this.showResults,
    required this.percentage,
    required this.allowMultiple,
    required this.isQuiz,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return GestureDetector(
      onTap: showResults ? null : onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            if (showResults)
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: percentage / 100.0,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    color: isSelected
                        ? c.primary.withValues(alpha: 0.20)
                        : c.muted.withValues(alpha: 0.50),
                  ),
                ),
              ),
            Container(
              decoration: showResults
                  ? null
                  : BoxDecoration(
                      border: Border.all(
                          color: isSelected ? c.primary : c.border,
                          width: isSelected ? 2 : 1),
                      borderRadius: BorderRadius.circular(10),
                    ),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (option.mediaUrl != null &&
                      option.mediaUrl!.isNotEmpty) ...[
                    _PollOptionMedia(option: option),
                    const SizedBox(width: 10),
                  ],
                  if (!showResults) ...[
                    if (allowMultiple)
                      Icon(
                        isSelected
                            ? LucideIcons.checkSquare
                            : LucideIcons.square,
                        size: 18,
                        color: isSelected ? c.primary : c.mutedForeground,
                      )
                    else
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: isSelected ? c.primary : c.mutedForeground,
                              width: 2),
                        ),
                        child: isSelected
                            ? Center(
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                      color: c.primary, shape: BoxShape.circle),
                                ),
                              )
                            : null,
                      ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      option.text,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: showResults && isSelected ? c.primary : null,
                      ),
                    ),
                  ),
                  if (showResults && isSelected) ...[
                    Icon(LucideIcons.check, size: 16, color: c.primary),
                    const SizedBox(width: 6),
                  ],
                  if (showResults && isQuiz && option.isCorrect) ...[
                    const Icon(LucideIcons.badgeCheck,
                        size: 16, color: Color(0xFF22C55E)),
                    const SizedBox(width: 6),
                  ],
                  if (showResults)
                    SizedBox(
                      width: 44,
                      child: Text(
                        '$percentage%',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: isSelected ? c.primary : c.mutedForeground,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PollOptionMedia extends StatelessWidget {
  final PollOption option;

  const _PollOptionMedia({required this.option});

  @override
  Widget build(BuildContext context) {
    final url = option.mediaUrl!;
    final type = option.mediaType ?? '';
    final isVideo = type == 'video' ||
        RegExp(r'\.(mp4|mov|m4v|webm)(\?|$)', caseSensitive: false)
            .hasMatch(url);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 56,
        height: 42,
        color: Colors.black12,
        child: isVideo
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const _PollVideoPlaceholder(),
                  ),
                  Container(color: Colors.black.withValues(alpha: 0.24)),
                  const Center(
                    child:
                        Icon(LucideIcons.play, size: 18, color: Colors.white),
                  ),
                ],
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(LucideIcons.imageOff, size: 16),
                ),
              ),
      ),
    );
  }
}

class _PollVideoPlaceholder extends StatelessWidget {
  const _PollVideoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF111827),
      child: Center(
        child: Icon(
          LucideIcons.video,
          size: 16,
          color: Colors.white70,
        ),
      ),
    );
  }
}
