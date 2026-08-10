import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../data/ai_models_v2.dart';
import '../../data/intent_detector.dart';
import '../providers/ai_provider.dart';

class AiComposer extends ConsumerStatefulWidget {
  final VoidCallback? onSend;

  const AiComposer({super.key, this.onSend});

  @override
  ConsumerState<AiComposer> createState() => _AiComposerState();
}

class _AiComposerState extends ConsumerState<AiComposer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  DetectedIntent? _detectedIntent;
  bool _showIntentHint = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _controller.text.trim();
    setState(() {});

    if (text.isEmpty) {
      if (_detectedIntent != null || _showIntentHint) {
        setState(() {
          _detectedIntent = null;
          _showIntentHint = false;
        });
      }
      return;
    }

    if (text.length > 12) {
      final intent = IntentDetector.detect(text);
      if (intent.type != IntentType.chat && intent.isHighConfidence) {
        if (_detectedIntent?.type != intent.type) {
          setState(() {
            _detectedIntent = intent;
            _showIntentHint = true;
          });
          Future.delayed(const Duration(seconds: 4), () {
            if (mounted) setState(() => _showIntentHint = false);
          });
        }
      } else if (_detectedIntent != null) {
        setState(() {
          _detectedIntent = null;
          _showIntentHint = false;
        });
      }
    }
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final state = ref.read(aiProvider);
    if (state.isBusy) return;

    _controller.clear();
    HapticFeedback.lightImpact();
    ref.read(aiProvider.notifier).send(text);
    widget.onSend?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final state = ref.watch(aiProvider);
    final isMobile = MediaQuery.of(context).size.width < 768;
    final hasText = _controller.text.trim().isNotEmpty;
    final busy = state.isBusy;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: c.background,
        border: Border(top: BorderSide(color: c.border.withValues(alpha: 0.15))),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_showIntentHint && _detectedIntent != null)
                  _intentHintBanner(c, _detectedIntent!),
                if (state.attachments.isNotEmpty) _attachmentsRow(c, state),
                _inputContainer(c, hasText: hasText, busy: busy, isMobile: isMobile),
                const SizedBox(height: 6),
                _bottomRow(c, state),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _intentHintBanner(AlsamosColors c, DetectedIntent intent) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            AppColors.alsamosOrange.withValues(alpha: 0.08),
            AppColors.alsamosOrangeDark.withValues(alpha: 0.04),
          ]),
          border: Border.all(color: AppColors.alsamosOrange.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(IntentDetector.getIntentIconData(intent.type),
                size: 15, color: AppColors.alsamosOrange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                IntentDetector.getIntentDescription(intent.type),
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.alsamosOrange),
              ),
            ),
            InkWell(
              onTap: () => setState(() => _showIntentHint = false),
              child: Icon(LucideIcons.x, size: 13, color: c.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }

  Widget _attachmentsRow(AlsamosColors c, AiState state) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: state.attachments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => _attachmentChip(c, state.attachments[i], i),
      ),
    );
  }

  Widget _attachmentChip(AlsamosColors c, AttachedFile file, int index) {
    return Container(
      width: 110,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_fileIcon(file.type), size: 18, color: AppColors.alsamosOrange),
              const SizedBox(height: 4),
              Text(file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
              Text(file.sizeFormatted,
                  style: TextStyle(fontSize: 9, color: c.mutedForeground)),
            ],
          ),
          Positioned(
            top: -4,
            right: -4,
            child: InkWell(
              onTap: () => ref.read(aiProvider.notifier).removeAttachment(index),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: c.destructive, shape: BoxShape.circle),
                child: const Icon(LucideIcons.x, size: 8, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputContainer(AlsamosColors c,
      {required bool hasText, required bool busy, required bool isMobile}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(
          color: _focus.hasFocus
              ? AppColors.alsamosOrange.withValues(alpha: 0.4)
              : c.border.withValues(alpha: 0.4),
          width: _focus.hasFocus ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          if (_focus.hasFocus)
            BoxShadow(
              color: AppColors.alsamosOrange.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMobile)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 8),
              child: _iconBtn(c, LucideIcons.plus, () {}, tooltip: 'Biriktirma'),
            ),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48, maxHeight: 180),
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                minLines: 1,
                maxLines: 6,
                enabled: !busy,
                textInputAction: TextInputAction.newline,
                onSubmitted: (_) => _send(),
                style: const TextStyle(fontSize: 14, height: 1.45),
                decoration: InputDecoration(
                  hintText: 'Xabar yozing, rasm yarating, kod yozing...',
                  hintStyle: TextStyle(
                      fontSize: 13, color: c.mutedForeground.withValues(alpha: 0.6)),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.fromLTRB(
                      isMobile ? 16 : 8, 14, 0, 14),
                ),
              ),
            ),
          ),
          if (!isMobile)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _iconBtn(c, LucideIcons.mic, () {}, tooltip: 'Ovozli yozuv'),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 8, 8),
            child: _sendButton(c, hasText: hasText, busy: busy),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(AlsamosColors c, IconData icon, VoidCallback onTap, {String? tooltip}) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 16,
        icon: Icon(icon, color: c.mutedForeground),
        onPressed: onTap,
        tooltip: tooltip,
      ),
    );
  }

  Widget _sendButton(AlsamosColors c, {required bool hasText, required bool busy}) {
    final enabled = hasText && !busy;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? _send : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: enabled
                ? const LinearGradient(
                    colors: [AppColors.alsamosOrange, AppColors.alsamosOrangeDark])
                : null,
            color: enabled ? null : c.muted,
            borderRadius: BorderRadius.circular(12),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: AppColors.alsamosOrange.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: busy
              ? const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                )
              : Icon(LucideIcons.arrowUp,
                  size: 16, color: enabled ? Colors.white : c.mutedForeground),
        ),
      ),
    );
  }

  Widget _bottomRow(AlsamosColors c, AiState state) {
    return Row(
      children: [
        Expanded(
          child: Text(
            "Alsamos AI xato qilishi mumkin. Muhim ma'lumotlarni tekshiring.",
            style: TextStyle(fontSize: 10, color: c.mutedForeground.withValues(alpha: 0.6)),
          ),
        ),
        _modelSelector(c, state),
      ],
    );
  }

  Widget _modelSelector(AlsamosColors c, AiState state) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => _showModelPicker(c),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: c.muted.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.zap, size: 11, color: AppColors.alsamosOrange),
            const SizedBox(width: 5),
            Text(
              state.selectedModel ?? 'Gemini 3 Flash',
              style: TextStyle(fontSize: 10, color: c.mutedForeground),
            ),
            const SizedBox(width: 2),
            Icon(LucideIcons.chevronDown, size: 10, color: c.mutedForeground),
          ],
        ),
      ),
    );
  }

  void _showModelPicker(AlsamosColors c) {
    showModalBottomSheet(
      context: context,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Model tanlang',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.foreground)),
            ),
            const SizedBox(height: 12),
            _modelOption(c, 'Gemini 3 Flash', 'Tez va samarali', true),
            _modelOption(c, 'Gemini 3 Pro', 'Chuqur tahlil uchun', false),
            _modelOption(c, 'Extended Thinking', 'Murakkab masalalar uchun', false),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _modelOption(AlsamosColors c, String name, String desc, bool selected) {
    return ListTile(
      leading: Icon(
        selected ? LucideIcons.circleCheck : LucideIcons.circle,
        size: 18,
        color: selected ? AppColors.alsamosOrange : c.mutedForeground,
      ),
      title: Text(name, style: TextStyle(fontSize: 13, color: c.foreground)),
      subtitle: Text(desc, style: TextStyle(fontSize: 11, color: c.mutedForeground)),
      onTap: () {
        ref.read(aiProvider.notifier).setModel(name);
        Navigator.pop(context);
      },
    );
  }

  IconData _fileIcon(AttachmentType type) {
    return switch (type) {
      AttachmentType.image => LucideIcons.image,
      AttachmentType.video => LucideIcons.video,
      AttachmentType.audio => LucideIcons.music,
      AttachmentType.document => LucideIcons.fileText,
      AttachmentType.spreadsheet => LucideIcons.sheet,
      AttachmentType.code => LucideIcons.code,
      AttachmentType.other => LucideIcons.file,
    };
  }
}
