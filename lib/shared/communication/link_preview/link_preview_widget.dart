import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_theme.dart';
import 'link_preview_engine.dart';

enum LinkPreviewStyle { card, compact, minimal }

class LinkPreviewWidget extends ConsumerStatefulWidget {
  final String url;
  final LinkPreviewStyle style;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const LinkPreviewWidget({
    super.key,
    required this.url,
    this.style = LinkPreviewStyle.card,
    this.onTap,
    this.onRemove,
  });

  @override
  ConsumerState<LinkPreviewWidget> createState() => _LinkPreviewWidgetState();
}

class _LinkPreviewWidgetState extends ConsumerState<LinkPreviewWidget> {
  LinkPreviewData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant LinkPreviewWidget old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final engine = ref.read(linkPreviewEngineProvider);
    final data = await engine.fetchPreview(widget.url);
    if (mounted) setState(() { _data = data; _loading = false; });
  }

  void _openUrl() {
    if (widget.onTap != null) {
      widget.onTap!();
      return;
    }
    launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _buildSkeleton(context);
    }
    if (_data == null || !(_data!.hasContent)) {
      return const SizedBox.shrink();
    }

    return switch (widget.style) {
      LinkPreviewStyle.card => _buildCard(context),
      LinkPreviewStyle.compact => _buildCompact(context),
      LinkPreviewStyle.minimal => _buildMinimal(context),
    };
  }

  Widget _buildCard(BuildContext context) {
    final c = AlsamosColors.of(context);
    return InkWell(
      onTap: _openUrl,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_data!.imageUrl != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: CachedNetworkImage(
                    imageUrl: _data!.imageUrl!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_data!.domain != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          _data!.domain!,
                          style: TextStyle(
                            fontSize: 11,
                            color: c.mutedForeground,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    if (_data!.title != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          _data!.title!,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (_data!.description != null)
                      Text(
                        _data!.description!,
                        style: TextStyle(fontSize: 12, color: c.mutedForeground),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.onRemove != null)
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: Icon(LucideIcons.x, size: 14, color: c.mutedForeground),
                onPressed: widget.onRemove,
                iconSize: 14,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _buildCompact(BuildContext context) {
    final c = AlsamosColors.of(context);
    return InkWell(
      onTap: _openUrl,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: c.primary, width: 3)),
          color: c.muted.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          if (_data!.imageUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: _data!.imageUrl!,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox(width: 44, height: 44),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_data!.title != null)
                  Text(
                    _data!.title!,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (_data!.domain != null)
                  Text(
                    _data!.domain!,
                    style: TextStyle(fontSize: 10, color: c.mutedForeground),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildMinimal(BuildContext context) {
    final c = AlsamosColors.of(context);
    return InkWell(
      onTap: _openUrl,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.link, size: 12, color: c.mutedForeground),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              _data!.title ?? _data!.domain ?? widget.url,
              style: TextStyle(
                fontSize: 12,
                color: c.primary,
                decoration: TextDecoration.underline,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: c.muted,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(height: 10, width: 120, color: c.muted),
              const SizedBox(height: 4),
              Container(height: 8, width: 80, color: c.muted),
            ],
          ),
        ),
      ]),
    );
  }
}
