import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import 'transfer_dialog.dart';

/// v27: QR scan dialog — placeholder UI before `mobile_scanner` integration.
/// Has a fake animated scanner frame + manual code entry fallback.
class QrScanDialog extends StatefulWidget {
  const QrScanDialog({super.key});
  static Future<void> show(BuildContext context) =>
      showDialog(context: context, builder: (_) => const QrScanDialog());
  @override
  State<QrScanDialog> createState() => _QrScanDialogState();
}

class _QrScanDialogState extends State<QrScanDialog> with SingleTickerProviderStateMixin {
  final _code = TextEditingController();
  late final AnimationController _anim = AnimationController(
      vsync: this, duration: const Duration(seconds: 2))
    ..repeat(reverse: true);

  @override
  void dispose() { _code.dispose(); _anim.dispose(); super.dispose(); }

  void _manualSubmit() {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    Navigator.pop(context);
    // Open transfer dialog with the manually-entered identifier.
    Future.microtask(() => TransferDialog.show(context));
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Dialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(LucideIcons.qrCode, color: primary, size: 22)),
              const SizedBox(width: 12),
              Expanded(child: Text("QR to'lov",
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.foreground))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(LucideIcons.x, size: 20)),
            ]),
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black, borderRadius: BorderRadius.circular(14)),
                child: Stack(children: [
                  // 4 corner brackets
                  Positioned.fill(child: CustomPaint(painter: _CornerPainter(primary))),
                  // Animated scan line
                  AnimatedBuilder(
                    animation: _anim,
                    builder: (_, __) {
                      return Positioned(
                        left: 24, right: 24,
                        top: 24 + (_anim.value * (200)),
                        child: Container(height: 2,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              primary.withValues(alpha: 0.0),
                              primary,
                              primary.withValues(alpha: 0.0),
                            ]),
                            boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.6), blurRadius: 8)],
                          ),
                        ),
                      );
                    },
                  ),
                  Center(child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      "Kamera tez orada ulanadi.\nQR ramkasini kodga yo'naltiring",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, height: 1.4),
                    ),
                  )),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Text("Yoki kodni qo'lda kiriting",
                style: TextStyle(fontSize: 12, color: c.mutedForeground)),
            const SizedBox(height: 8),
            TextField(
              controller: _code,
              decoration: InputDecoration(
                hintText: 'QR kod / havola',
                isDense: true, filled: true, fillColor: c.muted,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                suffixIcon: IconButton(onPressed: _manualSubmit,
                    icon: Icon(LucideIcons.arrowRight, color: primary)),
              ),
              onSubmitted: (_) => _manualSubmit(),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  _CornerPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..strokeWidth = 3..style = PaintingStyle.stroke;
    const len = 30.0;
    const inset = 18.0;
    // top-left
    canvas.drawLine(Offset(inset, inset), Offset(inset + len, inset), p);
    canvas.drawLine(Offset(inset, inset), Offset(inset, inset + len), p);
    // top-right
    canvas.drawLine(Offset(size.width - inset, inset), Offset(size.width - inset - len, inset), p);
    canvas.drawLine(Offset(size.width - inset, inset), Offset(size.width - inset, inset + len), p);
    // bottom-left
    canvas.drawLine(Offset(inset, size.height - inset), Offset(inset + len, size.height - inset), p);
    canvas.drawLine(Offset(inset, size.height - inset), Offset(inset, size.height - inset - len), p);
    // bottom-right
    canvas.drawLine(Offset(size.width - inset, size.height - inset), Offset(size.width - inset - len, size.height - inset), p);
    canvas.drawLine(Offset(size.width - inset, size.height - inset), Offset(size.width - inset, size.height - inset - len), p);
  }
  @override bool shouldRepaint(_) => false;
}
