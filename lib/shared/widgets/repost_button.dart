import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../app/theme/app_colors.dart';

/// Repost button with bottom-sheet menu (Repost / Quote).
class RepostButton extends StatefulWidget {
  const RepostButton({
    super.key,
    required this.postId,
    required this.postUserId,
    required this.initialCount,
    this.iconSize = 20,
    this.darkRail = false,
    this.showLabel = true,
    required this.onRepost,
  });

  final String postId;
  final String postUserId;
  final int initialCount;
  final double iconSize;
  final bool darkRail;
  final bool showLabel;
  final Future<bool> Function({String? quote}) onRepost;

  @override
  State<RepostButton> createState() => _RepostButtonState();
}

class _RepostButtonState extends State<RepostButton> {
  late int _count = widget.initialCount;
  bool _isReposted = false;
  bool _busy = false;

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  Future<void> _doRepost({String? quote}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await widget.onRepost(quote: quote);
    if (mounted) {
      setState(() {
        _busy = false;
        if (ok) {
          _isReposted = true;
          _count += 1;
        }
      });
    }
  }

  Future<void> _openSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.repeat2,
                  color: Color(0xFF22C55E)),
              title: const Text('Repost'),
              onTap: () => Navigator.pop(c, 'repost'),
            ),
            ListTile(
              leading: const Icon(LucideIcons.quote),
              title: const Text('Iqtibos bilan repost'),
              onTap: () => Navigator.pop(c, 'quote'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == 'repost') {
      await _doRepost();
    } else if (choice == 'quote') {
      final ctrl = TextEditingController();
      // ignore: use_build_context_synchronously
      final quote = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Iqtibos bilan repost'),
          content: TextField(
            controller: ctrl,
            maxLines: 3,
            maxLength: 280,
            decoration: const InputDecoration(
              hintText: 'Fikringizni qo\'shing...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Bekor'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, ctrl.text.trim()),
              child: const Text('Joylash'),
            ),
          ],
        ),
      );
      if (quote != null && quote.isNotEmpty) {
        await _doRepost(quote: quote);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _isReposted
        ? const Color(0xFF22C55E)
        : (widget.darkRail
            ? Colors.white
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85));
    return InkWell(
      onTap: _openSheet,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.repeat2, size: widget.iconSize, color: color),
            if (widget.showLabel) ...[
              const SizedBox(width: 6),
              Text(
                _fmt(_count),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// keep AppColors import alive for future styling parity
// ignore: unused_element
const _orangeRef = AppColors.alsamosOrange;
