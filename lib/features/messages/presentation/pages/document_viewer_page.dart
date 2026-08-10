import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';

class DocumentViewerPage extends StatelessWidget {
  final String url;
  final String fileName;

  const DocumentViewerPage({
    super.key,
    required this.url,
    required this.fileName,
  });

  String get _displayName {
    final explicit = fileName.trim();
    if (explicit.isNotEmpty && explicit != url) return explicit;
    final uri = Uri.tryParse(url);
    final segment = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : url.split('/').last;
    return Uri.decodeComponent(segment.split('?').first);
  }

  String get _normalizedName => _displayName.toLowerCase().split('?').first;

  bool get _isPdf => _normalizedName.endsWith('.pdf');
  
  bool get _isImage {
    final lower = _normalizedName;
    return lower.endsWith('.jpg') || lower.endsWith('.jpeg') || 
           lower.endsWith('.png') || lower.endsWith('.gif') || 
           lower.endsWith('.webp') || lower.endsWith('.bmp');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.8),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          _displayName,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.externalLink),
            onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            tooltip: 'Tashqi dasturda ochish',
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isPdf) {
      return SfPdfViewer.network(
        url,
        canShowScrollHead: false,
        canShowScrollStatus: false,
        canShowPaginationDialog: false,
        onDocumentLoadFailed: (details) {
          debugPrint('[DocumentViewer] PDF load failed: ${details.description}');
        },
      );
    } else if (_isImage) {
      return InteractiveViewer(
        minScale: 1.0,
        maxScale: 5.0,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          placeholder: (context, url) => const CircularProgressIndicator(color: Colors.white),
          errorWidget: (context, url, error) => const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.imageOff, color: Colors.white54, size: 48),
              SizedBox(height: 16),
              Text('Rasmni yuklashda xatolik', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    } else {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.fileQuestion, color: Colors.white54, size: 64),
          const SizedBox(height: 16),
          const Text('Bu fayl turini oldindan ko\'rib bo\'lmaydi',
              style: TextStyle(color: Colors.white)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            icon: const Icon(LucideIcons.download),
            label: const Text('Faylni yuklab olish / Ochish'),
          ),
        ],
      );
    }
  }
}
