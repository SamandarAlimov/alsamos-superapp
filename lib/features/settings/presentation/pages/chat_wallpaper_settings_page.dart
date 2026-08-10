import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/error_mapper.dart';
import '../../../messages/presentation/providers/chat_background_provider.dart';
import '../../../messages/presentation/widgets/chat_wallpaper.dart';

class ChatWallpaperSettingsPage extends ConsumerStatefulWidget {
  final String? conversationId;

  const ChatWallpaperSettingsPage({super.key, this.conversationId});

  @override
  ConsumerState<ChatWallpaperSettingsPage> createState() =>
      _ChatWallpaperSettingsPageState();
}

class _ChatWallpaperSettingsPageState
    extends ConsumerState<ChatWallpaperSettingsPage> {
  static const _presets = [
    'wallpaper1.svg',
    'wallpaper2.svg',
    'wallpaper3.svg',
    'wallpaper4.svg',
  ];
  static const _colors = [
    '#F97316',
    '#0F172A',
    '#2563EB',
    '#16A34A',
    '#DC2626',
    '#9333EA',
    '#0891B2',
    '#F59E0B',
    '#64748B',
    '#FFFFFF',
    '#111827',
    '#FCE7F3',
  ];
  static const _gradients = [
    ('#FF7A1A', '#2DD4BF', 135.0),
    ('#2563EB', '#A855F7', 45.0),
    ('#22C55E', '#FACC15', 120.0),
    ('#0F172A', '#F97316', 35.0),
  ];

  late ChatWallpaperConfig _draft;
  late bool _perChat;
  final _hexCtrl = TextEditingController();
  final _gradientA = TextEditingController(text: '#FF7A1A');
  final _gradientB = TextEditingController(text: '#2DD4BF');
  double _angle = 135;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _perChat = widget.conversationId != null;
    final current =
        ref.read(chatWallpaperProvider).effectiveFor(widget.conversationId);
    _draft = current;
    _hydrateEditors(current);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = widget.conversationId;
      if (id != null) {
        ref.read(chatWallpaperProvider.notifier).loadForConversation(id);
      }
    });
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    _gradientA.dispose();
    _gradientB.dispose();
    super.dispose();
  }

  void _hydrateEditors(ChatWallpaperConfig config) {
    if (config.type == ChatWallpaperType.color) _hexCtrl.text = config.value;
    if (config.type == ChatWallpaperType.gradient) {
      try {
        final data = jsonDecode(config.value) as Map<String, dynamic>;
        _gradientA.text = data['a'] as String? ?? _gradientA.text;
        _gradientB.text = data['b'] as String? ?? _gradientB.text;
        _angle = (data['angle'] as num?)?.toDouble() ?? _angle;
      } catch (_) {}
    }
  }

  Future<void> _apply(ChatWallpaperConfig config) async {
    setState(() => _draft = config);
    final notifier = ref.read(chatWallpaperProvider.notifier);
    if (_perChat && widget.conversationId != null) {
      await notifier.setForConversation(widget.conversationId!, config);
    } else {
      await notifier.setGlobal(config);
    }
  }

  Future<void> _reset() async {
    final notifier = ref.read(chatWallpaperProvider.notifier);
    if (_perChat && widget.conversationId != null) {
      await notifier.resetConversation(widget.conversationId!);
    } else {
      await notifier.resetGlobal();
    }
    final next =
        ref.read(chatWallpaperProvider).effectiveFor(widget.conversationId);
    setState(() => _draft = next);
  }

  Future<void> _upload() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
      maxWidth: 2600,
    );
    if (file == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final config = await ref
          .read(chatWallpaperProvider.notifier)
          .uploadCustomImage(file);
      if (config != null) await _apply(config);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.card,
        elevation: 0,
        title: const Text('Chat Wallpaper'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: 210,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  WallpaperPaint(config: _draft),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PreviewBubble(text: 'Assalomu alaykum!', c: c),
                        Align(
                          alignment: Alignment.centerRight,
                          child: _PreviewBubble(
                            text: 'Wallpaper shunday ko‘rinadi',
                            c: c,
                            outgoing: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (widget.conversationId != null)
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('All chats')),
                ButtonSegment(value: true, label: Text('This chat')),
              ],
              selected: {_perChat},
              onSelectionChanged: (value) {
                setState(() {
                  _perChat = value.first;
                  _draft = ref
                      .read(chatWallpaperProvider)
                      .effectiveFor(_perChat ? widget.conversationId : null);
                });
              },
            ),
          const SizedBox(height: 18),
          _SectionTitle('Presets', c: c),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _presets.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.72,
            ),
            itemBuilder: (_, i) {
              final value = _presets[i];
              return _WallpaperOption(
                selected: _draft.type == ChatWallpaperType.preset &&
                    _draft.value == value,
                onTap: () => _apply(_draft.copyWith(
                  type: ChatWallpaperType.preset,
                  value: value,
                )),
                child: WallpaperPaint(
                  config: ChatWallpaperConfig(
                    type: ChatWallpaperType.preset,
                    value: value,
                    dim: 0,
                    blur: 0,
                    updatedAt: DateTime.now(),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          _SectionTitle('Colors', c: c),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final hex in _colors)
                _ColorDot(
                  hex: hex,
                  selected: _draft.type == ChatWallpaperType.color &&
                      _draft.value == hex,
                  onTap: () {
                    _hexCtrl.text = hex;
                    _apply(_draft.copyWith(
                      type: ChatWallpaperType.color,
                      value: hex,
                    ));
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _hexCtrl,
                decoration: const InputDecoration(
                  labelText: 'Custom HEX',
                  hintText: '#F97316',
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: () => _apply(_draft.copyWith(
                type: ChatWallpaperType.color,
                value: _hexCtrl.text.trim(),
              )),
              child: const Text('Apply'),
            ),
          ]),
          const SizedBox(height: 18),
          _SectionTitle('Gradient', c: c),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final g in _gradients)
                _WallpaperOption(
                  selected: false,
                  onTap: () {
                    _gradientA.text = g.$1;
                    _gradientB.text = g.$2;
                    _angle = g.$3;
                    _apply(_draft.copyWith(
                      type: ChatWallpaperType.gradient,
                      value: jsonEncode({'a': g.$1, 'b': g.$2, 'angle': g.$3}),
                    ));
                  },
                  child: WallpaperPaint(
                    config: ChatWallpaperConfig(
                      type: ChatWallpaperType.gradient,
                      value: jsonEncode({'a': g.$1, 'b': g.$2, 'angle': g.$3}),
                      dim: 0,
                      blur: 0,
                      updatedAt: DateTime.now(),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _gradientA)),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _gradientB)),
          ]),
          Slider(
            value: _angle,
            min: 0,
            max: 360,
            divisions: 36,
            label: '${_angle.round()}°',
            onChanged: (v) => setState(() => _angle = v),
            onChangeEnd: (_) => _apply(_draft.copyWith(
              type: ChatWallpaperType.gradient,
              value: jsonEncode({
                'a': _gradientA.text.trim(),
                'b': _gradientB.text.trim(),
                'angle': _angle,
              }),
            )),
          ),
          const SizedBox(height: 18),
          _SectionTitle('Upload', c: c),
          OutlinedButton.icon(
            onPressed: _uploading ? null : _upload,
            icon: _uploading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.imagePlus, size: 18),
            label: Text(_uploading ? 'Uploading...' : 'Choose image'),
          ),
          const SizedBox(height: 18),
          _SectionTitle('Appearance', c: c),
          _SliderTile(
            label: 'Dim',
            value: _draft.dim,
            max: 0.75,
            onChanged: (v) => setState(() => _draft = _draft.copyWith(dim: v)),
            onChangeEnd: (v) => _apply(_draft.copyWith(dim: v)),
          ),
          _SliderTile(
            label: 'Blur',
            value: _draft.blur,
            max: 12,
            onChanged: (v) => setState(() => _draft = _draft.copyWith(blur: v)),
            onChangeEnd: (v) => _apply(_draft.copyWith(blur: v)),
          ),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: _reset,
            icon: Icon(LucideIcons.rotateCcw, color: primary, size: 18),
            label: const Text('Reset to default'),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final AlsamosColors c;
  const _SectionTitle(this.text, {required this.c});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: TextStyle(
            color: c.foreground,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _WallpaperOption extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  const _WallpaperOption({
    required this.selected,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 72,
        height: 96,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? primary : Colors.black.withValues(alpha: 0.10),
            width: selected ? 2 : 1,
          ),
        ),
        child: child,
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final String hex;
  final bool selected;
  final VoidCallback onTap;

  const _ColorDot({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.black.withValues(alpha: 0.12),
            width: selected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _SliderTile({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(width: 56, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.clamp(0, max),
          min: 0,
          max: max,
          divisions: max > 1 ? max.round() : 15,
          label: value.toStringAsFixed(1),
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ),
    ]);
  }
}

class _PreviewBubble extends StatelessWidget {
  final String text;
  final AlsamosColors c;
  final bool outgoing;

  const _PreviewBubble({
    required this.text,
    required this.c,
    this.outgoing = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: const BoxConstraints(maxWidth: 250),
      decoration: BoxDecoration(
        color: outgoing
            ? Theme.of(context).colorScheme.primary
            : c.card.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        text,
        style: TextStyle(color: outgoing ? Colors.white : c.foreground),
      ),
    );
  }
}
