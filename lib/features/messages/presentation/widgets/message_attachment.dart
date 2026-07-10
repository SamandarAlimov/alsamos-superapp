import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/theme/app_theme.dart';
import 'voice_message_player.dart';

enum MessageAttachmentType { image, video, audio, document }

/// Ports `src/components/MessageAttachment.tsx`. Routes by type to the right player/viewer.
class MessageAttachment extends StatelessWidget {
  const MessageAttachment({
    super.key,
    required this.url,
    required this.type,
    this.name,
    this.isMine = false,
    this.senderName,
  });
  final String url;
  final MessageAttachmentType type;
  final String? name;
  final bool isMine;
  final String? senderName;

  static MessageAttachmentType fromString(String s) {
    switch (s) {
      case 'image': return MessageAttachmentType.image;
      case 'video': return MessageAttachmentType.video;
      case 'audio': return MessageAttachmentType.audio;
      default: return MessageAttachmentType.document;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGif = url.contains('giphy.com') || url.toLowerCase().endsWith('.gif');
    if (type == MessageAttachmentType.image || isGif) {
      return GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _Fullscreen(url: url))),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280, maxHeight: 360),
            child: CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
          ),
        ),
      );
    }
    if (type == MessageAttachmentType.video) return _VideoAttachment(url: url);
    if (type == MessageAttachmentType.audio) {
      return VoiceMessagePlayer(url: url, isMine: isMine, senderName: senderName);
    }
    // Document
    final fileName = name ?? url.split('/').last;
    final ext = fileName.contains('.') ? fileName.split('.').last.toUpperCase() : 'FILE';
    final fg = isMine ? Colors.white : theme.colorScheme.primary;
    final bg = isMine ? Colors.white.withValues(alpha: 0.18) : theme.colorScheme.primary.withValues(alpha: 0.1);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Container(
        constraints: const BoxConstraints(minWidth: 200),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: isMine ? Colors.white.withValues(alpha: 0.1) : Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)), child: Icon(LucideIcons.fileText, color: fg, size: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isMine ? Colors.white : Theme.of(context).textTheme.bodyMedium?.color)),
              const SizedBox(height: 2),
              Text(ext, style: TextStyle(fontSize: 11, color: isMine ? Colors.white70 : AlsamosColors.of(context).mutedForeground)),
            ]),
          ),
          Icon(LucideIcons.download, size: 16, color: isMine ? Colors.white70 : AlsamosColors.of(context).mutedForeground),
        ]),
      ),
    );
  }
}

class _VideoAttachment extends StatefulWidget {
  const _VideoAttachment({required this.url});
  final String url;
  @override
  State<_VideoAttachment> createState() => _VideoAttachmentState();
}

class _VideoAttachmentState extends State<_VideoAttachment> {
  late VideoPlayerController _c;
  @override
  void initState() {
    super.initState();
    _c = VideoPlayerController.networkUrl(Uri.parse(widget.url))..initialize().then((_) => mounted ? setState(() {}) : null);
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280, maxHeight: 360),
        child: AspectRatio(
          aspectRatio: _c.value.isInitialized ? _c.value.aspectRatio : 16 / 9,
          child: Stack(alignment: Alignment.center, children: [
            if (_c.value.isInitialized) VideoPlayer(_c) else Container(color: Colors.black),
            GestureDetector(
              onTap: () => setState(() => _c.value.isPlaying ? _c.pause() : _c.play()),
              child: Container(
                width: 48, height: 48,
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: Icon(_c.value.isPlaying ? LucideIcons.pause : LucideIcons.play, color: Colors.white, size: 22),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Fullscreen extends StatelessWidget {
  const _Fullscreen({required this.url});
  final String url;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          Center(child: InteractiveViewer(minScale: 1, maxScale: 4, child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain))),
          Positioned(
            top: 8, right: 8,
            child: IconButton(icon: const Icon(LucideIcons.x, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
          ),
        ]),
      ),
    );
  }
}
