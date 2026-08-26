import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/communication/emoji/animated_emoji.dart';

/// v22: lightweight emoji picker (no external package). Returns the tapped
/// emoji string or null on dismiss. Web uses `emoji-mart`, we ship a curated
/// 8-category grid that covers ~90% of real-world chat usage.
class EmojiPickerSheet extends StatefulWidget {
  final bool reactionMode;

  const EmojiPickerSheet({
    super.key,
    this.reactionMode = false,
  });

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const EmojiPickerSheet(),
    );
  }

  static Future<String?> showReactions(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const EmojiPickerSheet(reactionMode: true),
    );
  }

  @override
  State<EmojiPickerSheet> createState() => _EmojiPickerSheetState();
}

class _EmojiPickerSheetState extends State<EmojiPickerSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tab =
      TabController(length: _cats.length, vsync: this);

  static const _cats = <(String, String, List<String>)>[
    (
      '\u{1F600}',
      'Smileys',
      [
        '\u{1F600}',
        '\u{1F603}',
        '\u{1F604}',
        '\u{1F601}',
        '\u{1F606}',
        '\u{1F605}',
        '\u{1F923}',
        '\u{1F602}',
        '\u{1F642}',
        '\u{1F643}',
        '\u{1F609}',
        '\u{1F60A}',
        '\u{1F607}',
        '\u{1F970}',
        '\u{1F60D}',
        '\u{1F929}',
        '\u{1F618}',
        '\u{1F617}',
        '\u{1F61A}',
        '\u{1F619}',
        '\u{1F60B}',
        '\u{1F61B}',
        '\u{1F61C}',
        '\u{1F92A}',
        '\u{1F914}',
        '\u{1F910}',
        '\u{1F928}',
        '\u{1F610}',
        '\u{1F611}',
        '\u{1F636}',
        '\u{1F60F}',
        '\u{1F612}',
        '\u{1F644}',
        '\u{1F62C}',
        '\u{1F62A}',
        '\u{1F634}',
        '\u{1F637}',
        '\u{1F912}',
        '\u{1F915}',
        '\u{1F922}',
        '\u{1F92E}',
        '\u{1F927}',
        '\u{1F975}',
        '\u{1F976}',
        '\u{1F974}',
        '\u{1F635}',
        '\u{1F92F}',
        '\u{1F920}',
      ]
    ),
    (
      '\u{2764}',
      'Hearts',
      [
        '\u{2764}',
        '\u{1F9E1}',
        '\u{1F49B}',
        '\u{1F49A}',
        '\u{1F499}',
        '\u{1F49C}',
        '\u{1F90E}',
        '\u{1F5A4}',
        '\u{1F90D}',
        '\u{1F495}',
        '\u{1F49E}',
        '\u{1F493}',
        '\u{1F497}',
        '\u{1F496}',
        '\u{1F498}',
        '\u{1F49D}',
        '\u{1F492}',
        '\u{1F494}',
      ]
    ),
    (
      '\u{1F44D}',
      'Gestures',
      [
        '\u{1F44D}',
        '\u{1F44E}',
        '\u{1F44C}',
        '\u{270C}',
        '\u{1F91E}',
        '\u{1F91F}',
        '\u{1F918}',
        '\u{1F919}',
        '\u{1F448}',
        '\u{1F449}',
        '\u{1F446}',
        '\u{1F447}',
        '\u{1F44B}',
        '\u{1F91A}',
        '\u{1F590}',
        '\u{270B}',
        '\u{1F596}',
        '\u{1F44A}',
        '\u{270A}',
        '\u{1F44F}',
        '\u{1F64C}',
        '\u{1F450}',
        '\u{1F932}',
        '\u{1F91D}',
        '\u{1F64F}',
        '\u{1F4AA}',
      ]
    ),
    (
      '\u{1F436}',
      'Animals',
      [
        '\u{1F436}',
        '\u{1F431}',
        '\u{1F42D}',
        '\u{1F439}',
        '\u{1F430}',
        '\u{1F98A}',
        '\u{1F43B}',
        '\u{1F43C}',
        '\u{1F428}',
        '\u{1F42F}',
        '\u{1F981}',
        '\u{1F42E}',
        '\u{1F437}',
        '\u{1F438}',
        '\u{1F435}',
        '\u{1F648}',
        '\u{1F412}',
        '\u{1F414}',
        '\u{1F427}',
        '\u{1F426}',
      ]
    ),
    (
      '\u{1F354}',
      'Food',
      [
        '\u{1F354}',
        '\u{1F35F}',
        '\u{1F355}',
        '\u{1F32D}',
        '\u{1F32E}',
        '\u{1F32F}',
        '\u{1F37F}',
        '\u{1F361}',
        '\u{1F363}',
        '\u{1F371}',
        '\u{1F359}',
        '\u{1F35A}',
        '\u{1F35B}',
        '\u{1F35C}',
        '\u{1F35D}',
        '\u{1F35E}',
        '\u{1F356}',
        '\u{1F357}',
        '\u{1F358}',
        '\u{1F368}',
        '\u{1F36A}',
        '\u{1F36B}',
        '\u{1F36C}',
        '\u{1F367}',
        '\u{1F370}',
        '\u{2615}',
        '\u{1F37A}',
        '\u{1F377}',
        '\u{1F378}',
        '\u{1F379}',
      ]
    ),
    (
      '\u{26BD}',
      'Activity',
      [
        '\u{26BD}',
        '\u{1F3C0}',
        '\u{1F3C8}',
        '\u{26BE}',
        '\u{1F3BE}',
        '\u{1F3D0}',
        '\u{1F3C9}',
        '\u{1F3B1}',
        '\u{1F3D3}',
        '\u{1F3F8}',
        '\u{1F3CF}',
        '\u{1F3D2}',
        '\u{26F3}',
        '\u{1F3AF}',
        '\u{1F3B2}',
        '\u{265F}',
        '\u{1F3AE}',
        '\u{1F3B0}',
        '\u{1F3B5}',
        '\u{1F3B6}',
      ]
    ),
    (
      '\u{2708}',
      'Travel',
      [
        '\u{2708}',
        '\u{1F697}',
        '\u{1F695}',
        '\u{1F699}',
        '\u{1F68C}',
        '\u{1F68E}',
        '\u{1F6B2}',
        '\u{1F6F4}',
        '\u{1F6F5}',
        '\u{1F6E5}',
        '\u{1F6A2}',
        '\u{2693}',
        '\u{1F680}',
        '\u{1F6F0}',
        '\u{1F30D}',
        '\u{1F30E}',
        '\u{1F30F}',
        '\u{1F5FA}',
        '\u{1F5FD}',
        '\u{1F3D6}',
      ]
    ),
    (
      '\u{1F4A1}',
      'Objects',
      [
        '\u{1F4A1}',
        '\u{1F526}',
        '\u{1F56F}',
        '\u{1F4DA}',
        '\u{1F4D6}',
        '\u{1F4DD}',
        '\u{2702}',
        '\u{1F4CE}',
        '\u{1F4CC}',
        '\u{1F4CD}',
        '\u{1F4F1}',
        '\u{1F4BB}',
        '\u{2328}',
        '\u{1F5A8}',
        '\u{1F5B2}',
        '\u{1F4BE}',
        '\u{1F4BF}',
        '\u{1F4C0}',
        '\u{1F39E}',
        '\u{1F3A5}',
        '\u{1F4F7}',
        '\u{1F4F9}',
        '\u{1F4FC}',
        '\u{1F50D}',
        '\u{1F50E}',
        '\u{1F56F}',
        '\u{1F4A1}',
        '\u{1F526}',
        '\u{1F4A3}',
        '\u{1F389}',
      ]
    ),
  ];

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final size = MediaQuery.of(context).size;
    final sheetHeight =
        widget.reactionMode ? size.height * 0.58 : size.height * 0.5;
    return Container(
      height: sheetHeight.clamp(320.0, 520.0),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        Container(
          margin: const EdgeInsets.only(top: 8, bottom: 6),
          width: 38,
          height: 4,
          decoration: BoxDecoration(
              color: c.mutedForeground.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2)),
        ),
        TabBar(
          controller: _tab,
          isScrollable: true,
          labelColor: primary,
          unselectedLabelColor: c.mutedForeground,
          indicatorColor: primary,
          indicatorWeight: 2,
          tabAlignment: TabAlignment.start,
          tabs: _cats.map((e) => Tab(text: e.$1)).toList(),
        ),
        Expanded(child: _buildGrid()),
      ]),
    );
  }

  Widget _buildGrid() {
    return TabBarView(
      controller: _tab,
      children: _cats
          .map(
            (cat) => LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount =
                    (constraints.maxWidth / (widget.reactionMode ? 62 : 44))
                        .floor()
                        .clamp(6, 10);
                return GridView.builder(
                  padding: EdgeInsets.fromLTRB(
                    widget.reactionMode ? 18 : 8,
                    widget.reactionMode ? 16 : 8,
                    widget.reactionMode ? 18 : 8,
                    24,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: widget.reactionMode ? 10 : 4,
                    crossAxisSpacing: widget.reactionMode ? 10 : 4,
                  ),
                  itemCount: cat.$3.length,
                  itemBuilder: (_, i) {
                    final emoji = cat.$3[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.pop(context, emoji),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeOutCubic,
                        decoration:
                            const BoxDecoration(color: Colors.transparent),
                        child: Center(
                          child: widget.reactionMode
                              ? AnimatedEmoji(
                                  emoji: emoji,
                                  size: 40,
                                  animate: true,
                                  replayOnTap: false,
                                )
                              : Text(
                                  emoji,
                                  style: const TextStyle(fontSize: 26),
                                ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          )
          .toList(),
    );
  }
}
