import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';

class CreateLiveTab extends StatelessWidget {
  const CreateLiveTab({
    super.key,
    required this.colors,
    required this.primary,
    required this.identityRow,
    required this.topicController,
    required this.previewText,
    required this.chatEnabled,
    required this.reactionsEnabled,
    required this.recordingEnabled,
    required this.onTopicChanged,
    required this.onChatChanged,
    required this.onReactionsChanged,
    required this.onRecordingChanged,
    required this.onStart,
  });

  final AlsamosColors colors;
  final Color primary;
  final Widget identityRow;
  final TextEditingController topicController;
  final String previewText;
  final bool chatEnabled;
  final bool reactionsEnabled;
  final bool recordingEnabled;
  final ValueChanged<String> onTopicChanged;
  final ValueChanged<bool> onChatChanged;
  final ValueChanged<bool> onReactionsChanged;
  final ValueChanged<bool> onRecordingChanged;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 880;
              final preview = Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: c.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 32,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF111827),
                              Color(0xFF020617),
                              Color(0xFF1C0F06),
                            ],
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: CustomPaint(painter: _LiveGridPainter()),
                      ),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                color: primary.withValues(alpha: 0.16),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: primary.withValues(alpha: 0.45),
                                  width: 2,
                                ),
                              ),
                              child: Icon(LucideIcons.radioTower,
                                  color: primary, size: 34),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Live preview',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              previewText.trim().isEmpty
                                  ? 'Mavzu kiritilganda shu yerda ko\'rinadi'
                                  : previewText.trim(),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 16,
                        top: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.radio,
                                  color: Colors.white, size: 14),
                              SizedBox(width: 6),
                              Text(
                                'LIVE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        right: 16,
                        top: 16,
                        child: Row(
                          children: [
                            _LivePill(
                              icon: LucideIcons.users,
                              label: '0',
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            _LivePill(
                              icon: LucideIcons.messageCircle,
                              label: chatEnabled ? 'Chat' : 'Off',
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );

              final controls = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  identityRow,
                  const SizedBox(height: 16),
                  TextField(
                    controller: topicController,
                    maxLength: 150,
                    onChanged: onTopicChanged,
                    decoration: InputDecoration(
                      hintText: 'Live efir mavzusini kiriting...',
                      filled: true,
                      fillColor: c.muted,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: c.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: c.border),
                      ),
                      counterStyle:
                          TextStyle(color: c.mutedForeground, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(
                      children: [
                        _LiveSwitchTile(
                          icon: LucideIcons.messageCircle,
                          title: 'Jonli chat',
                          subtitle: 'Tomoshabinlar yozishi mumkin',
                          value: chatEnabled,
                          onChanged: onChatChanged,
                          colors: c,
                        ),
                        Divider(height: 1, color: c.border),
                        _LiveSwitchTile(
                          icon: LucideIcons.heart,
                          title: 'Reaksiyalar',
                          subtitle: 'Like va real-time reaksiyalar',
                          value: reactionsEnabled,
                          onChanged: onReactionsChanged,
                          colors: c,
                        ),
                        Divider(height: 1, color: c.border),
                        _LiveSwitchTile(
                          icon: LucideIcons.clapperboard,
                          title: 'Yozib olish',
                          subtitle: 'Live tugagach replay saqlanadi',
                          value: recordingEnabled,
                          onChanged: onRecordingChanged,
                          colors: c,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(
                      children: [
                        _LiveFeatureItem(
                          icon: LucideIcons.shieldCheck,
                          title: 'Xavfsiz efir',
                          subtitle: 'Moderatorlar va report oqimi tayyor',
                          c: c,
                        ),
                        const SizedBox(height: 14),
                        _LiveFeatureItem(
                          icon: LucideIcons.radioTower,
                          title: 'Past kechikish',
                          subtitle: 'Tomoshabinlar bilan tez muloqot',
                          c: c,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: onStart,
                      icon: const Icon(LucideIcons.radio, size: 22),
                      label: const Text(
                        'Efirni boshlash',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              );

              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: preview),
                        const SizedBox(width: 34),
                        Expanded(flex: 5, child: controls),
                      ],
                    )
                  : Column(
                      children: [
                        preview,
                        const SizedBox(height: 24),
                        controls,
                      ],
                    );
            },
          ),
        ),
      ),
    );
  }
}

class _LiveSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final AlsamosColors colors;

  const _LiveSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeThumbColor: Theme.of(context).colorScheme.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        secondary: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors.muted,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: colors.mutedForeground, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: colors.mutedForeground, fontSize: 12),
        ),
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _LivePill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    const gap = 42.0;
    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LiveFeatureItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final AlsamosColors c;

  const _LiveFeatureItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: c.muted,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 22, color: c.mutedForeground),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(color: c.mutedForeground, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}
