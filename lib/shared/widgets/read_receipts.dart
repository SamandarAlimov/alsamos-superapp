// v34: ReadReceipts — port of web `src/components/ReadReceipts.tsx` (132L)
// Xabar ostida "Ko'rganlar" avatar stack (overlapping) + tooltip list.
// UI faqat — receipt'lar tashqaridan beriladi (provider/repo orqali).

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../app/theme/app_theme.dart';

class ReadReceipt {
  final String userId;
  final DateTime readAt;
  final String? displayName;
  final String? username;
  final String? avatarUrl;
  const ReadReceipt({
    required this.userId,
    required this.readAt,
    this.displayName,
    this.username,
    this.avatarUrl,
  });

  String get label =>
      (displayName != null && displayName!.isNotEmpty)
          ? displayName!
          : (username != null && username!.isNotEmpty ? username! : 'User');
  String get initial => label.isNotEmpty ? label[0].toUpperCase() : 'U';
}

class ReadReceipts extends StatelessWidget {
  final List<ReadReceipt> receipts;
  final int maxAvatars;
  final double avatarSize;
  const ReadReceipts({
    super.key,
    required this.receipts,
    this.maxAvatars = 3,
    this.avatarSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    if (receipts.isEmpty) return const SizedBox.shrink();
    final c = AlsamosColors.of(context);
    final visible = receipts.take(maxAvatars).toList();
    final remaining = receipts.length - visible.length;
    final overlap = avatarSize * 0.5;
    final width = avatarSize +
        (visible.length - 1) * (avatarSize - overlap) +
        (remaining > 0 ? avatarSize - overlap : 0);

    return Tooltip(
      richMessage: WidgetSpan(
        child: _SeenByPopup(receipts: receipts),
      ),
      preferBelow: false,
      child: SizedBox(
        width: width,
        height: avatarSize,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (int i = 0; i < visible.length; i++)
              Positioned(
                left: i * (avatarSize - overlap),
                child: _StackedAvatar(
                  receipt: visible[i],
                  size: avatarSize,
                  borderColor: c.background,
                ),
              ),
            if (remaining > 0)
              Positioned(
                left: visible.length * (avatarSize - overlap),
                child: Container(
                  width: avatarSize,
                  height: avatarSize,
                  decoration: BoxDecoration(
                    color: c.muted,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.background, width: 1),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '+$remaining',
                    style: TextStyle(
                      fontSize: 8,
                      color: c.mutedForeground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StackedAvatar extends StatelessWidget {
  final ReadReceipt receipt;
  final double size;
  final Color borderColor;
  const _StackedAvatar({
    required this.receipt,
    required this.size,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final hasImg = receipt.avatarUrl != null && receipt.avatarUrl!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 1),
        color: c.muted,
      ),
      child: ClipOval(
        child: hasImg
            ? CachedNetworkImage(
                imageUrl: receipt.avatarUrl!,
                fit: BoxFit.cover,
                width: size,
                height: size,
                placeholder: (_, __) => Container(color: c.muted),
                errorWidget: (_, __, ___) => _Fallback(text: receipt.initial, size: size),
              )
            : _Fallback(text: receipt.initial, size: size),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  final String text;
  final double size;
  const _Fallback({required this.text, required this.size});
  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Container(
      width: size,
      height: size,
      color: c.muted,
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          fontSize: size * 0.5,
          fontWeight: FontWeight.w600,
          color: c.mutedForeground,
        ),
      ),
    );
  }
}

class _SeenByPopup extends StatelessWidget {
  final List<ReadReceipt> receipts;
  const _SeenByPopup({required this.receipts});
  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final fmt = DateFormat('HH:mm');
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Ko\'rganlar',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: c.foreground,
            ),
          ),
          const SizedBox(height: 4),
          for (final r in receipts)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      r.label,
                      style: TextStyle(fontSize: 11, color: c.foreground),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    fmt.format(r.readAt.toLocal()),
                    style: TextStyle(fontSize: 10, color: c.mutedForeground),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
