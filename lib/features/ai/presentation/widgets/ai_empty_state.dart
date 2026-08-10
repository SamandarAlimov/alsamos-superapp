import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../shared/content/utils/content_metadata.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/ai_provider.dart';

class AiEmptyState extends ConsumerWidget {
  final TextEditingController? inputController;
  final FocusNode? focusNode;

  const AiEmptyState({super.key, this.inputController, this.focusNode});

  static const _suggestions = <_Suggestion>[
    _Suggestion(LucideIcons.lightbulb, 'Fikr generatsiya',
        "Yangi g'oyalar yarating", "Menga ijtimoiy tarmoq uchun yangi kontent g'oyalarini taklif qil"),
    _Suggestion(LucideIcons.code2, 'Kod yozish',
        'Dasturlashda yordam', 'React komponent yaratishda yordam ber'),
    _Suggestion(LucideIcons.image, 'Rasm yaratish',
        'AI rasmlar generatsiyasi', 'Professional logotip dizayni yarat'),
    _Suggestion(LucideIcons.fileText, 'Matn tahriri',
        'Professional matnlar', 'Professional bio yozishda yordam ber'),
    _Suggestion(LucideIcons.globe, 'Tarjima',
        "Ko'p tilli tarjima", 'Quyidagi matnni ingliz tiliga tarjima qil'),
    _Suggestion(LucideIcons.barChart3, 'Tahlil',
        "Ma'lumotlar tahlili", "Bu ma'lumotlarni tahlil qil va xulosa chiqar"),
  ];

  static const _postSuggestions = <_Suggestion>[
    _Suggestion(LucideIcons.lightbulb, "Shunga o'xshash yoz", '',
        "Shu postga o'xshash kontent yozib ber, lekin yangicha uslubda"),
    _Suggestion(LucideIcons.brain, 'Tahlil qil', '',
        'Bu post haqida chuqur tahlil ber: nima yaxshi, nima yaxshilash mumkin'),
    _Suggestion(LucideIcons.fileText, 'Javob yoz', '',
        'Bu postga professional va qiziqarli javob yozib ber'),
    _Suggestion(LucideIcons.globe, 'Tarjima qil', '',
        'Bu post matnini ingliz tiliga professional tarjima qil'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final state = ref.watch(aiProvider);
    final profile = ref.watch(authProvider).profile;
    final name = profile?.displayName ?? profile?.username;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              _heroSection(c, name),
              const SizedBox(height: 32),
              if (state.forwardedPost != null)
                _forwardedPostCard(c, state.forwardedPost!, ref)
              else
                _suggestionGrid(c, ref),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroSection(AlsamosColors c, String? name) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.alsamosOrange, AppColors.alsamosOrangeDark],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.alsamosOrange.withValues(alpha: 0.25),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(LucideIcons.sparkles, size: 38, color: Colors.white),
        ),
        const SizedBox(height: 20),
        Text(
          name != null ? 'Salom, $name!' : 'Salom!',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Bugun sizga qanday yordam bera olaman?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: c.mutedForeground, height: 1.4),
        ),
      ],
    );
  }

  Widget _suggestionGrid(AlsamosColors c, WidgetRef ref) {
    final wide = WidgetsBinding.instance.platformDispatcher.views.first.physicalSize.width /
            WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio >
        540;

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: wide ? 3 : 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: wide ? 2.4 : 2.2,
      children: _suggestions.map((s) => _suggestionCard(c, s)).toList(),
    );
  }

  Widget _suggestionCard(AlsamosColors c, _Suggestion s) {
    return Builder(builder: (context) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            inputController?.text = s.prompt;
            inputController?.selection =
                TextSelection.fromPosition(TextPosition(offset: s.prompt.length));
            focusNode?.requestFocus();
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.card.withValues(alpha: 0.6),
              border: Border.all(color: c.border.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.alsamosOrange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(s.icon, size: 16, color: AppColors.alsamosOrange),
                ),
                const SizedBox(height: 8),
                Text(s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                if (s.desc.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(s.desc,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: c.mutedForeground)),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _forwardedPostCard(AlsamosColors c, ForwardedPost p, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: c.card.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.alsamosOrange.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.alsamosOrange.withValues(alpha: 0.08),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.sparkles, size: 14, color: AppColors.alsamosOrange),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Post yuborildi',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.alsamosOrange)),
                    ),
                    InkWell(
                      onTap: () => ref.read(aiProvider.notifier).clearForwardedPost(),
                      child: Icon(LucideIcons.x, size: 14, color: c.mutedForeground),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (p.mediaUrl != null && p.mediaUrl!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CachedNetworkImage(
                            imageUrl: p.mediaUrl!,
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    Text('@${p.authorName ?? 'Foydalanuvchi'}',
                        style: TextStyle(fontSize: 11, color: c.mutedForeground)),
                    if (stripPostMetadata(p.content).isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(stripPostMetadata(p.content),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, height: 1.4)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _postSuggestions.map((s) => _postChip(c, s)).toList(),
        ),
      ],
    );
  }

  Widget _postChip(AlsamosColors c, _Suggestion s) {
    return Builder(builder: (context) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            inputController?.text = s.prompt;
            inputController?.selection =
                TextSelection.fromPosition(TextPosition(offset: s.prompt.length));
            focusNode?.requestFocus();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c.card.withValues(alpha: 0.5),
              border: Border.all(color: c.border.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(s.icon, size: 13, color: AppColors.alsamosOrange),
                const SizedBox(width: 8),
                Text(s.title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _Suggestion {
  final IconData icon;
  final String title;
  final String desc;
  final String prompt;
  const _Suggestion(this.icon, this.title, this.desc, this.prompt);
}
