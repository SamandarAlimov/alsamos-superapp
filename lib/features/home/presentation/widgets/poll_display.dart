import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// Ports `src/components/PollDisplay.tsx`.
/// Vote stored locally via SharedPreferences (matches web localStorage).
class PollOption {
  final String id;
  final String text;
  int votes;
  PollOption({required this.id, required this.text, this.votes = 0});
  factory PollOption.fromMap(Map<String, dynamic> m) => PollOption(id: m['id'] as String, text: m['text'] as String, votes: (m['votes'] as int?) ?? 0);
  Map<String, dynamic> toMap() => {'id': id, 'text': text, 'votes': votes};
}

class PollData {
  final String question;
  final List<PollOption> options;
  final String duration; // '1h' | '6h' | '1d' | '3d' | '7d'
  final bool allowMultiple;
  final bool isAnonymous;
  final DateTime createdAt;
  PollData({required this.question, required this.options, required this.duration, this.allowMultiple = false, this.isAnonymous = false, required this.createdAt});
  factory PollData.fromMap(Map<String, dynamic> m) => PollData(
        question: m['question'] as String? ?? '',
        options: ((m['options'] as List?) ?? []).map((e) => PollOption.fromMap(e as Map<String, dynamic>)).toList(),
        duration: m['duration'] as String? ?? '1d',
        allowMultiple: (m['allowMultiple'] as bool?) ?? false,
        isAnonymous: (m['isAnonymous'] as bool?) ?? false,
        createdAt: DateTime.tryParse(m['createdAt']?.toString() ?? '') ?? DateTime.now(),
      );
}

/// Parses `<!--POLL:{...}-->` marker from post content.
Map<String, dynamic>? parsePollFromContent(String content) {
  final r = RegExp(r'<!--POLL:(\{.*?\})-->', dotAll: true).firstMatch(content);
  if (r == null) return {'pollData': null, 'cleanContent': content};
  try {
    final data = PollData.fromMap(jsonDecode(r.group(1)!) as Map<String, dynamic>);
    return {'pollData': data, 'cleanContent': content.replaceFirst(r.group(0)!, '').trim()};
  } catch (_) {
    return {'pollData': null, 'cleanContent': content};
  }
}

class PollDisplay extends ConsumerStatefulWidget {
  const PollDisplay({super.key, required this.postId, required this.pollData});
  final String postId;
  final PollData pollData;
  @override
  ConsumerState<PollDisplay> createState() => _PollDisplayState();
}

class _PollDisplayState extends ConsumerState<PollDisplay> {
  late List<PollOption> _options;
  Set<String> _selected = {};
  bool _hasVoted = false;
  bool _voting = false;

  @override
  void initState() {
    super.initState();
    _options = widget.pollData.options.map((o) => PollOption(id: o.id, text: o.text, votes: o.votes)).toList();
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('poll_vote_${widget.postId}');
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        setState(() {
          _hasVoted = true;
          _selected = Set<String>.from(m['optionIds'] as List);
        });
      } catch (_) {}
    }
    // restore aggregate votes
    final votesRaw = sp.getString('poll_votes_${widget.postId}');
    if (votesRaw != null) {
      try {
        final m = jsonDecode(votesRaw) as Map<String, dynamic>;
        setState(() {
          for (final o in _options) {
            o.votes = (m[o.id] as int?) ?? o.votes;
          }
        });
      } catch (_) {}
    }
  }

  DateTime get _expiryDate {
    final c = widget.pollData.createdAt;
    switch (widget.pollData.duration) {
      case '1h': return c.add(const Duration(hours: 1));
      case '6h': return c.add(const Duration(hours: 6));
      case '3d': return c.add(const Duration(days: 3));
      case '7d': return c.add(const Duration(days: 7));
      case '1d':
      default: return c.add(const Duration(days: 1));
    }
  }

  bool get _expired => DateTime.now().isAfter(_expiryDate);
  int get _totalVotes => _options.fold(0, (s, o) => s + o.votes);

  Future<void> _vote() async {
    if (_selected.isEmpty || _voting || _hasVoted || _expired) return;
    final me = ref.read(authProvider).user?.id;
    if (me == null) return;
    setState(() => _voting = true);
    final sp = await SharedPreferences.getInstance();
    for (final id in _selected) {
      final o = _options.firstWhere((e) => e.id == id);
      o.votes += 1;
    }
    await sp.setString('poll_vote_${widget.postId}', jsonEncode({'optionIds': _selected.toList(), 'votedAt': DateTime.now().toIso8601String()}));
    await sp.setString('poll_votes_${widget.postId}', jsonEncode({for (final o in _options) o.id: o.votes}));
    if (!mounted) return;
    setState(() { _hasVoted = true; _voting = false; });
  }

  String _timeLeft() {
    if (_expired) return 'Poll ended';
    final d = _expiryDate.difference(DateTime.now());
    if (d.inDays > 0) return '${d.inDays}d left';
    if (d.inHours > 0) return '${d.inHours}h left';
    if (d.inMinutes > 0) return '${d.inMinutes}m left';
    return 'Ending soon';
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    final showResults = _hasVoted || _expired;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.barChart3, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(child: Text(widget.pollData.question, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 10),
        ..._options.map((opt) {
          final pct = _totalVotes == 0 ? 0.0 : opt.votes / _totalVotes;
          final selected = _selected.contains(opt.id);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: showResults
                ? Stack(children: [
                    Container(
                      height: 36,
                      decoration: BoxDecoration(color: c.muted.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(8)),
                    ),
                    FractionallySizedBox(
                      widthFactor: pct,
                      child: Container(
                        height: 36,
                        decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(children: [
                        if (_selected.contains(opt.id)) Icon(LucideIcons.check, size: 14, color: theme.colorScheme.primary),
                        if (_selected.contains(opt.id)) const SizedBox(width: 4),
                        Expanded(child: Text(opt.text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                        Text('${(pct * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ])
                : InkWell(
                    onTap: () {
                      setState(() {
                        if (widget.pollData.allowMultiple) {
                          if (selected) { _selected.remove(opt.id); } else { _selected.add(opt.id); }
                        } else {
                          _selected = {opt.id};
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: selected ? theme.colorScheme.primary.withValues(alpha: 0.1) : c.muted.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: selected ? theme.colorScheme.primary : c.border),
                      ),
                      child: Row(children: [
                        widget.pollData.allowMultiple
                            ? Icon(selected ? LucideIcons.checkSquare : LucideIcons.square, size: 16, color: selected ? theme.colorScheme.primary : c.mutedForeground)
                            : Icon(selected ? LucideIcons.circleDot : LucideIcons.circle, size: 16, color: selected ? theme.colorScheme.primary : c.mutedForeground),
                        const SizedBox(width: 10),
                        Expanded(child: Text(opt.text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                      ]),
                    ),
                  ),
          );
        }),
        const SizedBox(height: 6),
        Row(children: [
          Icon(LucideIcons.users, size: 12, color: c.mutedForeground),
          const SizedBox(width: 4),
          Text('$_totalVotes vote${_totalVotes == 1 ? '' : 's'}', style: TextStyle(fontSize: 11, color: c.mutedForeground)),
          const SizedBox(width: 10),
          Icon(LucideIcons.clock, size: 12, color: c.mutedForeground),
          const SizedBox(width: 4),
          Text(_timeLeft(), style: TextStyle(fontSize: 11, color: c.mutedForeground)),
          const Spacer(),
          if (!showResults)
            SizedBox(
              height: 28,
              child: FilledButton(
                onPressed: _selected.isEmpty || _voting ? null : _vote,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), textStyle: const TextStyle(fontSize: 12)),
                child: _voting
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Vote'),
              ),
            ),
        ]),
      ]),
    );
  }
}
