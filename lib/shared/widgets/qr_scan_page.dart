import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/theme/app_theme.dart';
import 'app_toast.dart';

class AlsamosQrScanPage extends StatefulWidget {
  const AlsamosQrScanPage({super.key});

  static Future<String?> open(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<String>(
      MaterialPageRoute(builder: (_) => const AlsamosQrScanPage()),
    );
  }

  @override
  State<AlsamosQrScanPage> createState() => _AlsamosQrScanPageState();
}

class _AlsamosQrScanPageState extends State<AlsamosQrScanPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final _manual = TextEditingController();
  bool _handled = false;

  @override
  void dispose() {
    _manual.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _complete(String? raw) {
    final value = raw?.trim();
    if (_handled || value == null || value.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              onDetect: (capture) {
                for (final barcode in capture.barcodes) {
                  final value = barcode.rawValue;
                  if (value != null && value.trim().isNotEmpty) {
                    _complete(value);
                    return;
                  }
                }
              },
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.52),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      IconButton.filledTonal(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(LucideIcons.x),
                      ),
                      const Spacer(),
                      const Text(
                        'QR skaner',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      IconButton.filledTonal(
                        onPressed: () => _controller.toggleTorch(),
                        icon: const Icon(LucideIcons.flashlight),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
                const Spacer(),
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.card.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _manual,
                          decoration: const InputDecoration(
                            hintText: 'QR havolani qo‘lda kiriting',
                            border: InputBorder.none,
                          ),
                          onSubmitted: _complete,
                        ),
                      ),
                      IconButton(
                        onPressed: () => _complete(_manual.text),
                        icon: const Icon(LucideIcons.arrowRight),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void resolveAlsamosQr(BuildContext context, String raw) {
  final value = raw.trim();
  String? route;
  final uri = Uri.tryParse(value);
  if (value.startsWith('@') && value.length > 1) {
    route = '/user/${value.substring(1)}';
  } else if (uri != null && uri.pathSegments.isNotEmpty) {
    final host = uri.host.toLowerCase();
    final trusted = host.isEmpty ||
        host == 'alsamos.app' ||
        host == 'alsamos.com' ||
        host.endsWith('.alsamos.app') ||
        host.endsWith('.alsamos.com');
    if (trusted) {
      final first = uri.pathSegments.first;
      final second = uri.pathSegments.length > 1 ? uri.pathSegments[1] : null;
      if (first == 'user' && second != null) route = '/user/$second';
      if ((first == 'group' || first == 'channel' || first == 'messages') &&
          second != null) {
        route = '/messages/$second';
      }
    }
  }

  if (route == null) {
    AppToast.info(context, 'Alsamos QR havolasi tanilmadi');
    return;
  }
  context.push(route);
}
