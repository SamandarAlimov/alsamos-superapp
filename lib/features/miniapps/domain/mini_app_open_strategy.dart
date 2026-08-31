// Mini app ochish strategiyasi.
//
// Bu fayl `socialalsamos/src/features/miniapps/openStrategy.ts` bilan 1:1 mos.
// Qoidalar `docs/contracts/mini-apps/open-strategy.md` da hujjatlangan; bir tomonni
// o'zgartirsangiz ikkinchisini ham yangilash shart (aks holda web va mobil ajralib ketadi).

const Duration kMiniAppDirectTimeout = Duration(milliseconds: 8000);
const Duration kMiniAppProxyTimeout = Duration(milliseconds: 15000);

const List<String> _blockedSchemes = <String>[
  'javascript:',
  'data:',
  'blob:',
  'file:',
  'ftp:',
  'ws:',
  'wss:',
];

/// Iframe/WebView'da to'liq sayt sifatida ishlamaydigan hostlar.
const List<String> kFramingBlockedHosts = <String>[
  'facebook.com',
  'instagram.com',
  'x.com',
  'twitter.com',
  'linkedin.com',
  'web.whatsapp.com',
  'whatsapp.com',
  'tiktok.com',
  'accounts.google.com',
  'mail.google.com',
  'chat.openai.com',
  'github.com',
  'gmail.com',
];

enum MiniAppUrlRejectReason { empty, malformed, schemeNotAllowed, privateHost, noHost }

enum MiniAppOpenStepKind { embed, direct, proxy, external, native }

class NormalizedMiniAppUrl {
  const NormalizedMiniAppUrl._({
    required this.ok,
    this.url,
    this.host,
    this.punycode = false,
    this.reason,
  });

  factory NormalizedMiniAppUrl.success({
    required String url,
    required String host,
    required bool punycode,
  }) =>
      NormalizedMiniAppUrl._(ok: true, url: url, host: host, punycode: punycode);

  factory NormalizedMiniAppUrl.reject(MiniAppUrlRejectReason reason) =>
      NormalizedMiniAppUrl._(ok: false, reason: reason);

  final bool ok;
  final String? url;
  final String? host;
  final bool punycode;
  final MiniAppUrlRejectReason? reason;
}

class MiniAppOpenStep {
  const MiniAppOpenStep({
    required this.kind,
    required this.src,
    this.timeout = Duration.zero,
  });

  final MiniAppOpenStepKind kind;
  final String src;
  final Duration timeout;

  @override
  bool operator ==(Object other) =>
      other is MiniAppOpenStep &&
      other.kind == kind &&
      other.src == src &&
      other.timeout == timeout;

  @override
  int get hashCode => Object.hash(kind, src, timeout);
}

class MiniAppOpenPlan {
  const MiniAppOpenPlan({
    required this.steps,
    this.error,
    this.canonicalUrl,
    this.punycodeWarning = false,
  });

  final List<MiniAppOpenStep> steps;

  /// Reja tuzilmagan bo'lsa sababi (noto'g'ri URL yoki qo'llab-quvvatlanmaydigan tur).
  final MiniAppUrlRejectReason? error;
  final String? canonicalUrl;
  final bool punycodeWarning;

  bool get isEmpty => steps.isEmpty;
}

bool isPrivateMiniAppHost(String hostname) {
  final host = hostname.toLowerCase().replaceAll(RegExp(r'^\[|\]$'), '');
  if (host.isEmpty) return true;
  if (host == 'localhost' || host == '0.0.0.0' || host == '::1') return true;
  if (host.endsWith('.local') || host.endsWith('.internal') || host.endsWith('.localhost')) {
    return true;
  }
  if (host == 'metadata.google.internal' || host == '169.254.169.254') return true;
  if (host.startsWith('127.') || host.startsWith('10.') || host.startsWith('192.168.')) {
    return true;
  }
  if (host.startsWith('169.254.')) return true;
  if (RegExp(r'^172\.(1[6-9]|2[0-9]|3[01])\.').hasMatch(host)) return true;
  if (RegExp(r'^f[cd][0-9a-f]{0,2}:', caseSensitive: false).hasMatch(host)) return true;
  if (RegExp(r'^fe80:', caseSensitive: false).hasMatch(host)) return true;
  // Nuqtasiz va IP bo'lmagan host — ichki tarmoq nomi.
  if (!host.contains('.') && !host.contains(':')) return true;
  return false;
}

/// Foydalanuvchi kiritgan manzilni majburiy https ga keltiradi va xavfsizligini tekshiradi.
NormalizedMiniAppUrl normalizeMiniAppUrl(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) {
    return NormalizedMiniAppUrl.reject(MiniAppUrlRejectReason.empty);
  }

  final lower = value.toLowerCase();
  for (final scheme in _blockedSchemes) {
    if (lower.startsWith(scheme)) {
      return NormalizedMiniAppUrl.reject(MiniAppUrlRejectReason.schemeNotAllowed);
    }
  }

  var candidate = value;
  if (!RegExp(r'^[a-z][a-z0-9+.\-]*://', caseSensitive: false).hasMatch(candidate)) {
    candidate = 'https://$candidate';
  }

  Uri parsed;
  try {
    parsed = Uri.parse(candidate);
  } catch (_) {
    return NormalizedMiniAppUrl.reject(MiniAppUrlRejectReason.malformed);
  }

  final scheme = parsed.scheme.toLowerCase();
  if (scheme != 'https' && scheme != 'http') {
    return NormalizedMiniAppUrl.reject(MiniAppUrlRejectReason.schemeNotAllowed);
  }
  if (parsed.host.isEmpty) {
    return NormalizedMiniAppUrl.reject(MiniAppUrlRejectReason.noHost);
  }
  if (isPrivateMiniAppHost(parsed.host)) {
    return NormalizedMiniAppUrl.reject(MiniAppUrlRejectReason.privateHost);
  }

  final normalized = parsed.replace(
    scheme: 'https',
    path: parsed.path.isEmpty ? '/' : parsed.path,
  );
  final host = normalized.host.toLowerCase();

  return NormalizedMiniAppUrl.success(
    url: normalized.toString(),
    host: host,
    punycode: host.contains('xn--'),
  );
}

bool _hostMatches(String host, String entry) => host == entry || host.endsWith('.$entry');

String? _youtubeEmbed(Uri parsed) {
  final host = parsed.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  final segments = parsed.pathSegments.where((s) => s.isNotEmpty).toList();

  if (host == 'youtu.be') {
    return segments.isNotEmpty ? 'https://www.youtube.com/embed/${segments.first}' : null;
  }

  if (!_hostMatches(host, 'youtube.com') && host != 'youtube-nocookie.com') return null;

  final videoId = parsed.queryParameters['v'];
  if (videoId != null && videoId.isNotEmpty) {
    return 'https://www.youtube.com/embed/$videoId';
  }

  if (segments.length >= 2 && segments[0] == 'shorts') {
    return 'https://www.youtube.com/embed/${segments[1]}';
  }
  if (segments.length >= 2 && segments[0] == 'embed') {
    return parsed.toString();
  }

  final list = parsed.queryParameters['list'];
  if (list != null && list.isNotEmpty) {
    return 'https://www.youtube.com/embed/videoseries?list=$list';
  }

  // Kanal yoki asosiy sahifa uchun embed mavjud emas (soxta URL yasalmaydi).
  return null;
}

/// Embed havolasi topilsa qaytaradi, aks holda `null`.
String? resolveMiniAppEmbedUrl(String rawUrl) {
  final normalized = normalizeMiniAppUrl(rawUrl);
  if (!normalized.ok) return null;

  final parsed = Uri.parse(normalized.url!);
  final host = parsed.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  final segments = parsed.pathSegments.where((s) => s.isNotEmpty).toList();

  final youtube = _youtubeEmbed(parsed);
  if (youtube != null) return youtube;

  if (_hostMatches(host, 'vimeo.com')) {
    final id = segments.firstWhere(
      (segment) => RegExp(r'^\d+$').hasMatch(segment),
      orElse: () => '',
    );
    return id.isEmpty ? null : 'https://player.vimeo.com/video/$id';
  }

  if (_hostMatches(host, 'instagram.com')) {
    if (segments.length >= 2 &&
        <String>['p', 'reel', 'reels', 'tv'].contains(segments[0])) {
      final kind = segments[0] == 'reels' ? 'reel' : segments[0];
      return 'https://www.instagram.com/$kind/${segments[1]}/embed/';
    }
    return null;
  }

  if (host == 't.me' || _hostMatches(host, 'telegram.me')) {
    if (segments.isEmpty) return null;
    if (segments.first == 's') return parsed.toString();
    if (segments.first.toLowerCase().endsWith('bot')) return null;
    return 'https://t.me/s/${segments.join('/')}';
  }

  return null;
}

/// Sayt o'zini boshqa sahifa/WebView ichida ko'rsatishni bloklaydimi?
bool isMiniAppFramingBlocked(String rawUrl) {
  final normalized = normalizeMiniAppUrl(rawUrl);
  if (!normalized.ok) return false;
  final host = normalized.host!;
  return kFramingBlockedHosts.any((entry) => _hostMatches(host, entry));
}

String buildMiniAppProxyUrl(String apiBase, String targetUrl, [Object? cacheBuster]) {
  final base = apiBase.replaceAll(RegExp(r'/+$'), '');
  final suffix = cacheBuster == null ? '' : '&_ts=${Uri.encodeComponent(cacheBuster.toString())}';
  return '$base/functions/v1/mini-app-proxy?url=${Uri.encodeComponent(targetUrl)}$suffix';
}

/// Ochish qadamlari tartibini kontrakt bo'yicha tuzadi.
MiniAppOpenPlan buildMiniAppOpenPlan({
  required String? url,
  String displayMode = 'iframe',
  String appType = 'link',
  String? deepLink,
  String? apiBase,
  Object? cacheBuster,
}) {
  if (appType == 'native') {
    if (deepLink == null || deepLink.isEmpty) {
      return const MiniAppOpenPlan(steps: <MiniAppOpenStep>[], error: MiniAppUrlRejectReason.empty);
    }
    return MiniAppOpenPlan(
      steps: <MiniAppOpenStep>[
        MiniAppOpenStep(kind: MiniAppOpenStepKind.native, src: deepLink),
      ],
      canonicalUrl: deepLink,
    );
  }

  final normalized = normalizeMiniAppUrl(url);
  if (!normalized.ok) {
    return MiniAppOpenPlan(steps: const <MiniAppOpenStep>[], error: normalized.reason);
  }

  final target = normalized.url!;
  final embed = resolveMiniAppEmbedUrl(target);
  final proxyStep = (apiBase == null || apiBase.isEmpty)
      ? null
      : MiniAppOpenStep(
          kind: MiniAppOpenStepKind.proxy,
          src: buildMiniAppProxyUrl(apiBase, target, cacheBuster),
          timeout: kMiniAppProxyTimeout,
        );
  final externalStep = MiniAppOpenStep(kind: MiniAppOpenStepKind.external, src: target);

  final steps = <MiniAppOpenStep>[];

  if (displayMode == 'external' || (appType == 'bot' && embed == null)) {
    steps.add(externalStep);
  } else if (displayMode == 'proxy') {
    if (proxyStep != null) steps.add(proxyStep);
    steps.add(externalStep);
  } else if (displayMode == 'embed') {
    if (embed != null) {
      steps.add(MiniAppOpenStep(
        kind: MiniAppOpenStepKind.embed,
        src: embed,
        timeout: kMiniAppDirectTimeout,
      ));
    }
    if (proxyStep != null) steps.add(proxyStep);
    steps.add(externalStep);
  } else {
    // 'iframe' va 'webview'
    if (embed != null) {
      steps.add(MiniAppOpenStep(
        kind: MiniAppOpenStepKind.embed,
        src: embed,
        timeout: kMiniAppDirectTimeout,
      ));
    }
    if (!isMiniAppFramingBlocked(target)) {
      steps.add(MiniAppOpenStep(
        kind: MiniAppOpenStepKind.direct,
        src: target,
        timeout: kMiniAppDirectTimeout,
      ));
    }
    if (proxyStep != null) steps.add(proxyStep);
    steps.add(externalStep);
  }

  return MiniAppOpenPlan(
    steps: steps,
    canonicalUrl: target,
    punycodeWarning: normalized.punycode,
  );
}
