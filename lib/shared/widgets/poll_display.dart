// v32: PollDisplay widget — port of web `src/components/PollDisplay.tsx` (296L).
// UI-only: ovoz berish holati local state'da; backend wiring (polls table)
// keyingi bosqichda. Web bilan 1:1 visual parity.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../app/theme/app_theme.dart';

class PollOption {
  final String id;
  final String text;
  final int votes;
  const PollOption({required this.id, required this.text, required this.votes});

  PollOption copyWith({int? votes}) => PollOption(id: id, text: text, votes: votes ?? this.votes);

  factory PollOption.fromMap(Map<String, dynamic> m) => PollOption(
        id: m['id'] as String,
        text: (m['text'] as String?) ?? '',
        votes: (m['votes'] as int?) ?? 0,
      );

  Map<String, dynamic> toMap() => {'id': id, 'text': text, 'votes': votes};
}

class PollData {
  final String question;
  final List<PollOption> options;
  /// '1h' | '6h' | '1d' | '3d' | '7d'
  final String duration;
  final bool allowMultiple;
  final bool isAnonymous;
  final DateTime createdAt;

  const PollData({
    required this.question,
    required this.options,
    required this.duration,
    required this.allowMultiple,
    required this.isAnonymous,
    required this.createdAt,
  });

  DateTime get expiryDate {
    switch (duration) {
      case '1h':
        return createdAt.add(const Duration(hours: 1));
      case '6h':
        return createdAt.add(const Duration(hours: 6));
      case '1d':
        return createdAt.add(const Duration(days: 1));
      case '3d':
        return createdAt.add(const Duration(days: 3));
      case '7d':
        return createdAt.add(const Duration(days: 7));
      default:
        return createdAt.add(const Duration(days: 1));
    }
  }

  bool get isExpired => DateTime.now().isAfter(expiryDate);

  factory PollData.fromMap(Map<String, dynamic> m) => PollData(
        question: (m['question'] as String?) ?? '',
        options: ((m['options'] as List?) ?? const [])
            .map((e) => PollOption.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        duration: (m['duration'] as String?) ?? '1d',
        allowMultiple: (m['allowMultiple'] as bool?) ?? false,
        isAnonymous: (m['isAnonymous'] as bool?) ?? false,
        createdAt: DateTime.tryParse((m['createdAt'] as String?) ?? '') ?? DateTime.now(),
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
  const PollDisplay({super.key, required this.postId, required this.pollData, this.onVote});

  @override
  State<PollDisplay> createState() => _PollDisplayState();
}

class _PollDisplayState extends State<PollDisplay> {
  late List<PollOption> _options;
  final Set<String> _selected = {};
  bool _hasVoted = false;
  bool _isVoting = false;

  @override
  void initState() {
    super.initState();
    _options = List.of(widget.pollData.options);
  }

  int get _totalVotes => _options.fold<int>(0, (s, o) => s + o.votes);
  int _percentage(int votes) => _totalVotes == 0 ? 0 : ((votes / _totalVotes) * 100).round();

  void _tap(String id) {
    if (_hasVoted || widget.pollData.isExpired) return;
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
    if (_selected.isEmpty || _hasVoted || widget.pollData.isExpired) return;
    setState(() => _isVoting = true);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    setState(() {
      _options = _options
          .map((o) => _selected.contains(o.id) ? o.copyWith(votes: o.votes + 1) : o)
          .toList();
      _hasVoted = true;
      _isVoting = false;
    });
    widget.onVote?.call();
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
    final showResults = _hasVoted || widget.pollData.isExpired;
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
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(LucideIcons.users, size: 14, color: c.mutedForeground),
                      const SizedBox(width: 4),
                      Text('$_totalVotes ovoz',
                          style: TextStyle(fontSize: 12, color: c.mutedForeground)),
                      const SizedBox(width: 12),
                      Icon(LucideIcons.clock, size: 14, color: c.mutedForeground),
                      const SizedBox(width: 4),
                      Text(_timeLeftLabel(),
                          style: TextStyle(fontSize: 12, color: c.mutedForeground)),
                    ]),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
  final VoidCallback onTap;
  const _OptionRow({
    required this.option,
    required this.isSelected,
    required this.showResults,
    required this.percentage,
    required this.allowMultiple,
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
                    color: isSelected ? c.primary.withValues(alpha: 0.20) : c.muted.withValues(alpha: 0.50),
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
                  if (!showResults) ...[
                    if (allowMultiple)
                      Icon(
                        isSelected ? LucideIcons.checkSquare : LucideIcons.square,
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
                              color: isSelected ? c.primary : c.mutedForeground, width: 2),
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
