import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';

class CreateStoryTextControls extends StatelessWidget {
  final AlsamosColors colors;
  final Color primary;
  final TextAlign textAlign;
  final ValueChanged<TextAlign> onTextAlignChanged;
  final String selectedFont;
  final List<(String, String, FontWeight)> fonts;
  final ValueChanged<String> onFontChanged;
  final double textSize;
  final ValueChanged<double> onTextSizeChanged;
  final VoidCallback onResetPosition;

  const CreateStoryTextControls({
    super.key,
    required this.colors,
    required this.primary,
    required this.textAlign,
    required this.onTextAlignChanged,
    required this.selectedFont,
    required this.fonts,
    required this.onFontChanged,
    required this.textSize,
    required this.onTextSizeChanged,
    required this.onResetPosition,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.type, size: 16, color: primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Matn uslubi',
                  style: TextStyle(
                    color: c.foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<TextAlign>(
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: WidgetStateProperty.all(
                  const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
              segments: const [
                ButtonSegment(
                  value: TextAlign.left,
                  icon: Icon(LucideIcons.alignLeft, size: 15),
                ),
                ButtonSegment(
                  value: TextAlign.center,
                  icon: Icon(LucideIcons.alignCenter, size: 15),
                ),
                ButtonSegment(
                  value: TextAlign.right,
                  icon: Icon(LucideIcons.alignRight, size: 15),
                ),
              ],
              selected: {textAlign},
              onSelectionChanged: (value) =>
                  onTextAlignChanged(value.first),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final font in fonts)
                ChoiceChip(
                  label: Text(font.$2),
                  selected: selectedFont == font.$1,
                  onSelected: (_) => onFontChanged(font.$1),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'A',
                style: TextStyle(
                  color: c.mutedForeground,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Expanded(
                child: Slider(
                  value: textSize,
                  min: 18,
                  max: 48,
                  divisions: 15,
                  label: textSize.round().toString(),
                  onChanged: onTextSizeChanged,
                ),
              ),
              Text(
                'A',
                style: TextStyle(
                  color: c.foreground,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onResetPosition,
              icon: const Icon(LucideIcons.move, size: 15),
              label: const Text('Markazga'),
            ),
          ),
        ],
      ),
    );
  }
}
