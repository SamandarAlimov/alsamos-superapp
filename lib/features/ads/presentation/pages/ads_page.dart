
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/ad_model.dart';
import '../providers/ads_provider.dart';

const List<String> _kCtaOptions = [
  'Learn More',
  'Shop Now',
  'Sign Up',
  'Download',
  'Get Offer',
  'Book Now',
  'Contact Us',
  'Watch More',
  'Apply Now',
  'Get Started',
];

/// Pixel-perfect port of `components/ads/AdsManagerPage.tsx`.
/// Sticky header + 5 stat cards + filter tabs + ad list with status badges +
/// 4-step create wizard (Media → Details → Targeting → Budget) + Stats dialog.
class AdsPage extends ConsumerStatefulWidget {
  const AdsPage({super.key});
  @override
  ConsumerState<AdsPage> createState() => _AdsPageState();
}

class _AdsPageState extends ConsumerState<AdsPage> {
  String _filter = 'all'; // all | active | paused | pending

  static const _filters = <(String, String)>[
    ('all', 'Hammasi'),
    ('active', 'Faol'),
    ('paused', "To'xtatilgan"),
    ('pending', 'Kutilmoqda'),
  ];

  String _fmt(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  Future<void> _openCreate() async {
    final uid = ref.read(authProvider).user?.id;
    if (uid == null) return;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateAdDialog(userId: uid),
    );
    // Realtime channel refreshes automatically; no invalidate needed.
  }

  Future<void> _openStats(Ad ad) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _AdStatsDialog(ad: ad),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final adsAsync = ref.watch(myAdsProvider);

    return Scaffold(
      backgroundColor: c.background,
      body: adsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Xatolik: $e')),
        data: (ads) {
          final filtered = _filter == 'all'
              ? ads
              : ads.where((a) => a.status == _filter).toList();
          final impressions = ads.fold<int>(0, (s, a) => s + a.impressions);
          final clicks = ads.fold<int>(0, (s, a) => s + a.clicks);
          final reach = ads.fold<int>(0, (s, a) => s + a.reach);
          final spent = ads.fold<num>(0, (s, a) => s + a.spent);
          final ctr = impressions > 0 ? (clicks / impressions) * 100 : 0.0;

          return CustomScrollView(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _HeaderDelegate(
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.background.withValues(alpha: 0.95),
                      border: Border(bottom: BorderSide(color: c.border)),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Ads Manager',
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700),
                              ),
                              Text(
                                'Reklamalaringizni boshqaring',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: c.mutedForeground),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _openCreate,
                          icon: const Icon(LucideIcons.plus, size: 18),
                          label: const Text('Yangi reklama'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Stats
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(
                  child: GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount:
                        MediaQuery.of(context).size.width > 700 ? 5 : 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.7,
                    children: [
                      _stat(c, LucideIcons.eye, "Ko'rishlar",
                          _fmt(impressions)),
                      _stat(c, LucideIcons.mousePointerClick, 'Kliklar',
                          _fmt(clicks)),
                      _stat(c, LucideIcons.users, 'Reach', _fmt(reach)),
                      _stat(c, LucideIcons.trendingUp, 'CTR',
                          '${ctr.toStringAsFixed(2)}%'),
                      _stat(c, LucideIcons.dollarSign, 'Sarflangan',
                          '\$${spent.toStringAsFixed(2)}'),
                    ],
                  ),
                ),
              ),
              // Filter tabs
              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: _filters.map((f) {
                      final count = f.$1 == 'all'
                          ? ads.length
                          : ads.where((a) => a.status == f.$1).length;
                      final active = _filter == f.$1;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _filter = f.$1);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: active ? primary : c.card,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: active ? primary : c.border),
                            ),
                            child: Text(
                              '${f.$2} ($count)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: active
                                    ? Theme.of(context)
                                        .colorScheme
                                        .onPrimary
                                    : c.foreground,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.barChart3,
                              size: 48,
                              color: c.mutedForeground
                                  .withValues(alpha: 0.5)),
                          const SizedBox(height: 16),
                          const Text("Reklamalar yo'q",
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('Birinchi reklamangizni yarating',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: c.mutedForeground)),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _openCreate,
                            icon: const Icon(LucideIcons.plus, size: 18),
                            label: const Text('Reklama yaratish'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) =>
                        _adCard(c, primary, filtered[i]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _stat(AlsamosColors c, IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: c.mutedForeground),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: c.mutedForeground),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  /// Mirrors web's shadcn `<Badge variant="...">`:
  ///   active    → default     (primary background)
  ///   pending   → secondary   (muted background)   label: "Tekshirilmoqda"
  ///   paused    → outline     (transparent + border)
  ///   rejected  → destructive (red background)
  ///   completed → secondary   (muted background)
  Widget _statusBadge(AlsamosColors c, String status) {
    final primary = Theme.of(context).colorScheme.primary;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    final entry = switch (status) {
      'active' => ('Faol', primary, onPrimary, false),
      'pending' => ('Tekshirilmoqda', c.muted, c.mutedForeground, false),
      'paused' => ("To'xtatilgan", Colors.transparent, c.foreground, true),
      'rejected' =>
        ('Rad etildi', const Color(0xFFEF4444), Colors.white, false),
      'completed' => ('Tugallandi', c.muted, c.mutedForeground, false),
      _ => ('—', c.muted, c.mutedForeground, false),
    };
    final (label, bg, fg, outline) = entry;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: outline ? Border.all(color: c.border) : null,
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  Widget _adCard(AlsamosColors c, Color primary, Ad ad) {
    final typeLabel = ad.adType == 'feed'
        ? '📰 Feed'
        : ad.adType == 'story'
            ? '📸 Story'
            : '✨ Hammasi';
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 92,
              height: 92,
              color: c.muted,
              child: (ad.mediaUrl ?? '').isEmpty
                  ? Icon(LucideIcons.image, color: c.mutedForeground)
                  : CachedNetworkImage(
                      imageUrl: ad.mediaUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          Icon(LucideIcons.image, color: c.mutedForeground),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            ad.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                          Text(
                            typeLabel,
                            style: TextStyle(
                                fontSize: 12, color: c.mutedForeground),
                          ),
                        ],
                      ),
                    ),
                    _statusBadge(c, ad.status),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    _quick(c, LucideIcons.eye, _fmt(ad.impressions)),
                    _quick(c, LucideIcons.mousePointerClick,
                        _fmt(ad.clicks)),
                    _quick(
                        c,
                        LucideIcons.dollarSign,
                        '\$${ad.spent.toStringAsFixed(2)} / \$${ad.budget}'),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _openStats(ad),
                      icon: const Icon(LucideIcons.barChart3, size: 15),
                      label: const Text('Statistika'),
                      style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                    ),
                    if (ad.status == 'active')
                      OutlinedButton.icon(
                        onPressed: () async {
                          // Realtime channel will refresh the list — no manual
                          // invalidate needed (would churn the channel).
                          await ref
                              .read(adsRepositoryProvider)
                              .pauseAd(ad.id);
                        },
                        icon: const Icon(LucideIcons.pause, size: 15),
                        label: const Text("To'xtatish"),
                        style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact),
                      ),
                    if (ad.status == 'paused')
                      OutlinedButton.icon(
                        onPressed: () async {
                          await ref
                              .read(adsRepositoryProvider)
                              .resumeAd(ad.id);
                        },
                        icon: const Icon(LucideIcons.play, size: 15),
                        label: const Text('Davom ettirish'),
                        style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact),
                      ),
                    // Mirrors web's `<DropdownMenu>` with `MoreHorizontal`
                    // trigger + a single "O'chirish" item in red.
                    PopupMenuButton<String>(
                      icon: Icon(LucideIcons.moreHorizontal,
                          color: c.mutedForeground, size: 18),
                      tooltip: '',
                      padding: EdgeInsets.zero,
                      position: PopupMenuPosition.under,
                      color: c.card,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: c.border),
                      ),
                      onSelected: (v) async {
                        if (v == 'delete') {
                          await ref
                              .read(adsRepositoryProvider)
                              .deleteAd(ad.id);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem<String>(
                          value: 'delete',
                          height: 38,
                          child: Row(children: [
                            Icon(LucideIcons.trash2,
                                size: 14, color: Color(0xFFEF4444)),
                            SizedBox(width: 8),
                            Text("O'chirish",
                                style: TextStyle(
                                    color: Color(0xFFEF4444), fontSize: 13)),
                          ]),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quick(AlsamosColors c, IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c.mutedForeground),
          const SizedBox(width: 4),
          Text(text,
              style:
                  TextStyle(fontSize: 12.5, color: c.mutedForeground)),
        ],
      );
}

class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  _HeaderDelegate({required this.child});
  final Widget child;
  @override
  double get minExtent => 70;
  @override
  double get maxExtent => 70;
  @override
  Widget build(BuildContext context, double shrinkOffset,
          bool overlapsContent) =>
      SizedBox.expand(child: child);
  @override
  bool shouldRebuild(covariant _HeaderDelegate oldDelegate) => false;
}

// =========================================================================
// 4-step Create Wizard
// =========================================================================
class _CreateAdDialog extends ConsumerStatefulWidget {
  const _CreateAdDialog({required this.userId});
  final String userId;
  @override
  ConsumerState<_CreateAdDialog> createState() => _CreateAdDialogState();
}

class _CreateAdDialogState extends ConsumerState<_CreateAdDialog> {
  static const _steps = ['media', 'details', 'targeting', 'budget'];
  int _stepIdx = 0;
  bool _uploading = false;
  bool _submitting = false;
  Uint8List? _previewBytes;
  String? _mediaUrl;
  String _mediaType = 'image';
  VideoPlayerController? _previewVideo;

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController(text: '10');
  final _dailyCtrl = TextEditingController();
  final _ageMinCtrl = TextEditingController();
  final _ageMaxCtrl = TextEditingController();

  String _cta = 'Learn More';
  String _adType = 'feed';
  String _billing = 'cpm';
  String _gender = 'all';

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _urlCtrl.dispose();
    _budgetCtrl.dispose();
    _dailyCtrl.dispose();
    _ageMinCtrl.dispose();
    _ageMaxCtrl.dispose();
    _previewVideo?.dispose();
    super.dispose();
  }

  String get _step => _steps[_stepIdx];

  bool get _canProceed {
    switch (_step) {
      case 'media':
        return _mediaUrl != null;
      case 'details':
        return _titleCtrl.text.trim().length >= 3;
      case 'targeting':
        return true;
      case 'budget':
        return (num.tryParse(_budgetCtrl.text.trim()) ?? 0) >= 1;
    }
    return false;
  }

  Future<void> _pick() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickMedia();
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last;
      final isVideo = picked.mimeType?.startsWith('video/') == true ||
          {'mp4', 'mov', 'webm'}.contains(ext.toLowerCase());
      setState(() {
        _previewBytes = bytes;
        _mediaType = isVideo ? 'video' : 'image';
        _uploading = true;
      });
      final url =
          await ref.read(adsRepositoryProvider).uploadAdMedia(
                bytes: bytes,
                extension: ext,
              );
      if (!mounted) return;
      // For video: initialize a playable preview from the uploaded URL
      // (web does this with URL.createObjectURL + `<video controls>`).
      if (isVideo) {
        await _previewVideo?.dispose();
        _previewVideo = VideoPlayerController.networkUrl(Uri.parse(url))
          ..setLooping(true);
        try {
          await _previewVideo!.initialize();
        } catch (_) {/* leave previewVideo uninitialized */}
      }
      if (!mounted) return;
      setState(() {
        _mediaUrl = url;
        _uploading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yuklashda xatolik')),
      );
    }
  }

  Future<void> _submit() async {
    if (_mediaUrl == null) return;
    setState(() => _submitting = true);
    try {
      await ref.read(adsRepositoryProvider).createAd(
            userId: widget.userId,
            title: _titleCtrl.text.trim(),
            description: _descCtrl.text.trim().isEmpty
                ? null
                : _descCtrl.text.trim(),
            mediaUrl: _mediaUrl!,
            mediaType: _mediaType,
            destinationUrl: _urlCtrl.text.trim().isEmpty
                ? null
                : _urlCtrl.text.trim(),
            callToAction: _cta,
            adType: _adType,
            budget: num.tryParse(_budgetCtrl.text.trim()) ?? 1,
            dailyBudget: num.tryParse(_dailyCtrl.text.trim()),
            billingType: _billing,
            targetGender: _gender == 'all' ? null : _gender,
            targetAgeMin: int.tryParse(_ageMinCtrl.text.trim()),
            targetAgeMax: int.tryParse(_ageMaxCtrl.text.trim()),
          );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yaratishda xatolik')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Dialog(
      backgroundColor: c.card,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(children: [
                Icon(LucideIcons.target,
                    size: 20, color: primary),
                const SizedBox(width: 8),
                const Text('Reklama yaratish',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(LucideIcons.x, size: 18),
                ),
              ]),
            ),
            // Step indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: List.generate(_steps.length, (i) {
                  final done = i < _stepIdx;
                  final active = i == _stepIdx;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: active
                              ? primary
                              : done
                                  ? primary.withValues(alpha: 0.5)
                                  : c.muted,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: switch (_step) {
                  'media' => _mediaStep(c),
                  'details' => _detailsStep(c),
                  'targeting' => _targetingStep(c),
                  'budget' => _budgetStep(c, primary),
                  _ => const SizedBox(),
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                if (_stepIdx > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () => setState(() => _stepIdx--),
                      child: const Text('Orqaga'),
                    ),
                  ),
                if (_stepIdx > 0) const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: !_canProceed || _submitting
                        ? null
                        : (_stepIdx == _steps.length - 1
                            ? _submit
                            : () => setState(() => _stepIdx++)),
                    child: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : (_stepIdx == _steps.length - 1
                            // Web final CTA: `<Eye/> Reklamani yuborish`
                            ? const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(LucideIcons.eye,
                                      size: 16, color: Colors.white),
                                  SizedBox(width: 6),
                                  Text('Reklamani yuborish'),
                                ],
                              )
                            : const Text('Keyingi')),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------- Steps ----------------------------------
  Widget _mediaStep(AlsamosColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_previewBytes != null)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _mediaType == 'image'
                      ? Image.memory(_previewBytes!, fit: BoxFit.cover)
                      : (_previewVideo != null &&
                              _previewVideo!.value.isInitialized)
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                Container(color: Colors.black),
                                Center(
                                  child: AspectRatio(
                                    aspectRatio:
                                        _previewVideo!.value.aspectRatio,
                                    child: VideoPlayer(_previewVideo!),
                                  ),
                                ),
                                Positioned(
                                  left: 8,
                                  bottom: 8,
                                  child: GestureDetector(
                                    onTap: () => setState(() {
                                      if (_previewVideo!.value.isPlaying) {
                                        _previewVideo!.pause();
                                      } else {
                                        _previewVideo!.play();
                                      }
                                    }),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.black
                                            .withValues(alpha: 0.6),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        _previewVideo!.value.isPlaying
                                            ? LucideIcons.pause
                                            : LucideIcons.play,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Container(
                              color: Colors.black,
                              alignment: Alignment.center,
                              child: const Icon(LucideIcons.film,
                                  color: Colors.white54, size: 40),
                            ),
                ),
                if (_uploading)
                  ColoredBox(
                    color: Colors.black.withValues(alpha: 0.5),
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: c.card,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.hardEdge,
                    child: InkWell(
                      onTap: () => setState(() {
                        _previewBytes = null;
                        _mediaUrl = null;
                        _previewVideo?.dispose();
                        _previewVideo = null;
                      }),
                      child: const SizedBox(
                          width: 32,
                          height: 32,
                          child: Icon(LucideIcons.x, size: 16)),
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          GestureDetector(
            onTap: _pick,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                      color: c.border, style: BorderStyle.solid, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: c.muted,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(LucideIcons.image,
                            color: c.mutedForeground),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: c.muted,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(LucideIcons.film,
                            color: c.mutedForeground),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    const Text('Rasm yoki video yuklang',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    Text('Tap to upload',
                        style: TextStyle(
                            fontSize: 12,
                            color: c.mutedForeground)),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        _label('Reklama joylashuvi'),
        const SizedBox(height: 6),
        _select(c, _adType, const [
          ('feed', '📰 Feed'),
          ('story', '📸 Stories'),
          ('both', '✨ Hammasi'),
        ], (v) => setState(() => _adType = v)),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _detailsStep(AlsamosColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label('Sarlavha *'),
        const SizedBox(height: 6),
        _input(c, _titleCtrl, 'Reklama sarlavhasi', onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        _label('Tavsif'),
        const SizedBox(height: 6),
        _input(c, _descCtrl, 'Qisqa tavsif...', maxLines: 3),
        const SizedBox(height: 12),
        _label('Havola URL'),
        const SizedBox(height: 6),
        _input(c, _urlCtrl, 'https://example.com'),
        const SizedBox(height: 4),
        // Web FormDescription: "Foydalanuvchi bosganida ochiladi"
        Text('Foydalanuvchi bosganida ochiladi',
            style: TextStyle(fontSize: 12, color: c.mutedForeground)),
        const SizedBox(height: 12),
        _label('Call to Action'),
        const SizedBox(height: 6),
        _select(
          c,
          _cta,
          _kCtaOptions.map((o) => (o, o)).toList(),
          (v) => setState(() => _cta = v),
        ),
      ],
    );
  }

  Widget _targetingStep(AlsamosColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.muted.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            Icon(LucideIcons.target,
                size: 28, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 6),
            const Text('Auditoriya sozlamalari',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text("Reklamangiz kimga ko'rsatilishini tanlang",
                style: TextStyle(
                    fontSize: 12, color: c.mutedForeground)),
          ]),
        ),
        const SizedBox(height: 12),
        _label('Jins'),
        const SizedBox(height: 6),
        _select(c, _gender, const [
          ('all', 'Hammasi'),
          ('male', 'Erkaklar'),
          ('female', 'Ayollar'),
        ], (v) => setState(() => _gender = v)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('Min yosh'),
                const SizedBox(height: 6),
                _input(c, _ageMinCtrl, '13',
                    keyboard: TextInputType.number),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('Max yosh'),
                const SizedBox(height: 6),
                _input(c, _ageMaxCtrl, '65',
                    keyboard: TextInputType.number),
              ],
            ),
          ),
        ]),
      ],
    );
  }

  Widget _budgetStep(AlsamosColors c, Color primary) {
    final budget = num.tryParse(_budgetCtrl.text.trim()) ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.muted.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            Icon(LucideIcons.dollarSign, size: 28, color: primary),
            const SizedBox(height: 6),
            const Text('Byudjet sozlamalari',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('Qancha sarflashni xohlaysiz?',
                style: TextStyle(
                    fontSize: 12, color: c.mutedForeground)),
          ]),
        ),
        const SizedBox(height: 12),
        _label("To'lov turi"),
        const SizedBox(height: 6),
        _select(c, _billing, const [
          ('cpm', "CPM (1000 ta ko'rish)"),
          ('cpc', 'CPC (Har bir bosish)'),
        ], (v) => setState(() => _billing = v)),
        const SizedBox(height: 12),
        _label('Umumiy byudjet (USD)'),
        const SizedBox(height: 6),
        _input(c, _budgetCtrl, '10',
            keyboard: TextInputType.number,
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 4),
        // Web FormDescription: "Minimum: $1"
        Text('Minimum: \$1',
            style: TextStyle(fontSize: 12, color: c.mutedForeground)),
        const SizedBox(height: 12),
        _label('Kunlik limit (ixtiyoriy)'),
        const SizedBox(height: 6),
        _input(c, _dailyCtrl, "Limit yo'q",
            keyboard: TextInputType.number),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _kvRow(c, "To'lov turi:",
                  _billing == 'cpm' ? 'CPM' : 'CPC'),
              _kvRow(c, 'Umumiy byudjet:', '\$$budget'),
              _kvRow(
                c,
                "Taxminiy ko'rishlar:",
                '~${_thousands(((num.tryParse(_budgetCtrl.text.trim()) ?? 0) * 1000).round())}',
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------- Helpers -------------------------------
  Widget _label(String s) => Text(s,
      style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600));

  Widget _input(AlsamosColors c, TextEditingController ctrl, String hint,
      {int maxLines = 1,
      TextInputType? keyboard,
      void Function(String)? onChanged}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboard,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: c.muted.withValues(alpha: 0.4),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.border),
        ),
      ),
    );
  }

  Widget _select(AlsamosColors c, String value, List<(String, String)> opts,
      void Function(String) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          dropdownColor: c.card,
          items: opts
              .map((o) => DropdownMenuItem(value: o.$1, child: Text(o.$2)))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  Widget _kvRow(AlsamosColors c, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k,
                style: TextStyle(
                    fontSize: 12.5, color: c.mutedForeground)),
            Text(v,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

// =========================================================================
// Stats Dialog
// =========================================================================
String _thousands(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

class _AdStatsDialog extends ConsumerStatefulWidget {
  const _AdStatsDialog({required this.ad});
  final Ad ad;
  @override
  ConsumerState<_AdStatsDialog> createState() => _AdStatsDialogState();
}

class _AdStatsDialogState extends ConsumerState<_AdStatsDialog> {
  late Ad _ad;
  late Future<List<AdDailyStats>> _future;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _ad = widget.ad;
    _future = ref.read(adsRepositoryProvider).fetchDailyStats(_ad.id);

    // Web: `supabase.channel(`ad-stats-${adId}`).on('postgres_changes',
    //   { event: '*', schema: 'public', table: 'ads', filter: `id=eq.${adId}` },
    //   () => fetchStats());`
    final supa = Supabase.instance.client;
    _channel = supa.channel('ad-stats-${_ad.id}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'ads',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: _ad.id,
        ),
        callback: (_) => _refresh(),
      )
      ..subscribe();
  }

  Future<void> _refresh() async {
    try {
      final row = await Supabase.instance.client
          .from('ads')
          .select('*')
          .eq('id', _ad.id)
          .maybeSingle();
      final newDaily =
          ref.read(adsRepositoryProvider).fetchDailyStats(_ad.id);
      if (!mounted) return;
      setState(() {
        if (row != null) _ad = Ad.fromMap(row);
        _future = newDaily;
      });
    } catch (_) {/* swallow */}
  }

  @override
  void dispose() {
    final ch = _channel;
    if (ch != null) Supabase.instance.client.removeChannel(ch);
    super.dispose();
  }

  String _fmt(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final ad = _ad;

    return Dialog(
      backgroundColor: c.card,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(children: [
                Icon(LucideIcons.barChart3, size: 20, color: primary),
                const SizedBox(width: 8),
                const Text('Reklama statistikasi',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(LucideIcons.x, size: 18),
                ),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.5,
                      children: [
                        _statCard(c, LucideIcons.eye, "Ko'rishlar",
                            _fmt(ad.impressions)),
                        _statCard(c, LucideIcons.mousePointerClick,
                            'Kliklar', _fmt(ad.clicks)),
                        _statCard(c, LucideIcons.users, 'Reach',
                            _fmt(ad.reach)),
                        _statCard(c, LucideIcons.trendingUp, 'CTR',
                            '${ad.ctr.toStringAsFixed(2)}%'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: c.muted.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Row(children: [
                            Icon(LucideIcons.dollarSign,
                                size: 16, color: c.mutedForeground),
                            const SizedBox(width: 6),
                            Text('Sarflangan',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: c.mutedForeground)),
                          ]),
                          Text(
                            '\$${ad.spent.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Oxirgi 7 kun',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    FutureBuilder<List<AdDailyStats>>(
                      future: _future,
                      builder: (_, snap) {
                        if (snap.connectionState !=
                            ConnectionState.done) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                                child: CircularProgressIndicator()),
                          );
                        }
                        final rows = snap.data ?? const <AdDailyStats>[];
                        if (rows.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text("Ma'lumot yo'q",
                                style: TextStyle(
                                    color: c.mutedForeground)),
                          );
                        }
                        final maxImp = rows
                            .map((r) => r.impressions)
                            .fold<int>(0, (a, b) => a > b ? a : b);
                        return Column(
                          children: rows.map((d) {
                            final ratio =
                                maxImp == 0 ? 0.0 : d.impressions / maxImp;
                            return Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 8),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(d.date,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color:
                                                  c.mutedForeground)),
                                      Text(
                                        "${d.impressions} ko'rish, ${d.clicks} klik",
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: c.mutedForeground),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(20),
                                    child: LinearProgressIndicator(
                                      value: ratio,
                                      minHeight: 6,
                                      backgroundColor: c.muted,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                              primary),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(
      AlsamosColors c, IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(children: [
            Icon(icon, size: 14, color: c.mutedForeground),
            const SizedBox(width: 6),
            Text(label,
                style:
                    TextStyle(fontSize: 11, color: c.mutedForeground)),
          ]),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
