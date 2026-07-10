// v37: chat composer 4 ta "Tez orada" tugmasini almashtirish uchun
// real interactiv dialoglar. Backend hali ulanmaganligi sababli faqat UI.

import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/app_colors.dart';

class ComposerExtras {
  static Future<void> showLocationPicker(BuildContext context,
      {required void Function(String address) onShare}) async {
    final c = AlsamosColors.of(context);
    final ctrl = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
            left: 8, right: 8, top: 8),
        child: Container(
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Icon(LucideIcons.mapPin, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Text('Joylashuv yuborish',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.foreground)),
              ]),
              const SizedBox(height: 14),
              Container(
                height: 140,
                decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(12)),
                child: Stack(alignment: Alignment.center, children: [
                  Icon(LucideIcons.map, size: 56, color: c.mutedForeground.withValues(alpha: 0.3)),
                  Positioned(bottom: 8, child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.border),
                    ),
                    child: Text('Xarita preview', style: TextStyle(fontSize: 10, color: c.mutedForeground)),
                  )),
                ]),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  hintText: 'Manzil yoki tavsif',
                  prefixIcon: const Icon(LucideIcons.mapPin, size: 16),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  final addr = ctrl.text.trim();
                  if (addr.isEmpty) return;
                  Navigator.pop(ctx);
                  onShare(addr);
                },
                style: FilledButton.styleFrom(backgroundColor: AppColors.alsamosOrange),
                icon: const Icon(LucideIcons.send, size: 16),
                label: const Text('Yuborish'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> showContactPicker(BuildContext context,
      {required void Function(String name, String phone) onShare}) async {
    final c = AlsamosColors.of(context);
    final name = TextEditingController();
    final phone = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
            left: 8, right: 8, top: 8),
        child: Container(
          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.border)),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Icon(LucideIcons.user, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Text('Kontakt yuborish',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.foreground)),
              ]),
              const SizedBox(height: 14),
              TextField(
                controller: name,
                decoration: InputDecoration(
                  hintText: 'Ism',
                  prefixIcon: const Icon(LucideIcons.user, size: 16),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: '+998 ...',
                  prefixIcon: const Icon(LucideIcons.phone, size: 16),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  final n = name.text.trim();
                  final p = phone.text.trim();
                  if (n.isEmpty || p.isEmpty) return;
                  Navigator.pop(ctx);
                  onShare(n, p);
                },
                style: FilledButton.styleFrom(backgroundColor: AppColors.alsamosOrange),
                icon: const Icon(LucideIcons.send, size: 16),
                label: const Text('Yuborish'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> showPollCreator(BuildContext context,
      {required void Function(String question, List<String> options) onCreate}) async {
    final c = AlsamosColors.of(context);
    final q = TextEditingController();
    final opts = <TextEditingController>[TextEditingController(), TextEditingController()];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
            left: 8, right: 8, top: 8),
        child: Container(
          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.border)),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Icon(LucideIcons.barChart3, color: Colors.teal, size: 20),
                const SizedBox(width: 8),
                Text("So\u2018rovnoma yaratish",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.foreground)),
              ]),
              const SizedBox(height: 14),
              TextField(
                controller: q,
                decoration: InputDecoration(
                  hintText: 'Savol',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                ),
              ),
              const SizedBox(height: 10),
              for (int i = 0; i < opts.length; i++) ...[
                Row(children: [
                  Expanded(child: TextField(
                    controller: opts[i],
                    decoration: InputDecoration(
                      hintText: 'Variant ${i + 1}',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                    ),
                  )),
                  if (opts.length > 2)
                    IconButton(icon: const Icon(LucideIcons.x, size: 16), onPressed: () => setState(() => opts.removeAt(i))),
                ]),
                const SizedBox(height: 8),
              ],
              if (opts.length < 6)
                TextButton.icon(
                  onPressed: () => setState(() => opts.add(TextEditingController())),
                  icon: const Icon(LucideIcons.plus, size: 14),
                  label: const Text('Variant qo\u2018shish', style: TextStyle(fontSize: 12)),
                ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () {
                  final question = q.text.trim();
                  final values = opts.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
                  if (question.isEmpty || values.length < 2) return;
                  Navigator.pop(ctx);
                  onCreate(question, values);
                },
                style: FilledButton.styleFrom(backgroundColor: AppColors.alsamosOrange),
                icon: const Icon(LucideIcons.send, size: 16),
                label: const Text('Yaratish'),
              ),
            ],
          ),
        ),
      )),
    );
  }

  static Future<void> showAudioRecorder(BuildContext context,
      {required void Function(Duration length) onSend}) async {
    final c = AlsamosColors.of(context);
    bool recording = false;
    int seconds = 0;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) => SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.border)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                const Icon(LucideIcons.mic, color: Colors.indigo, size: 20),
                const SizedBox(width: 8),
                Text("Ovozli xabar",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.foreground)),
              ]),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () {
                  setState(() {
                    recording = !recording;
                    if (recording) {
                      seconds = 0;
                      Future.doWhile(() async {
                        await Future.delayed(const Duration(seconds: 1));
                        if (!recording) return false;
                        setState(() => seconds++);
                        return seconds < 120;
                      });
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: recording ? Colors.red : AppColors.alsamosOrange,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (recording ? Colors.red : AppColors.alsamosOrange).withValues(alpha: 0.4),
                        blurRadius: recording ? 20 : 10,
                        spreadRadius: recording ? 4 : 0,
                      ),
                    ],
                  ),
                  child: Icon(recording ? LucideIcons.square : LucideIcons.mic, color: Colors.white, size: 32),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: c.foreground,
                    fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              const SizedBox(height: 6),
              Text(
                recording ? 'Yozilmoqda\u2026 To\u2018xtatish uchun bosing' : 'Boshlash uchun bosing',
                style: TextStyle(fontSize: 12, color: c.mutedForeground),
              ),
              const SizedBox(height: 16),
              if (seconds > 0 && !recording)
                FilledButton.icon(
                  onPressed: () { Navigator.pop(ctx); onSend(Duration(seconds: seconds)); },
                  style: FilledButton.styleFrom(backgroundColor: AppColors.alsamosOrange),
                  icon: const Icon(LucideIcons.send, size: 16),
                  label: const Text('Yuborish'),
                ),
            ],
          ),
        ),
      )),
    );
  }
}
