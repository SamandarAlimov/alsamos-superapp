import 'package:alsamos_flutter/features/miniapps/domain/mini_app_open_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

const String apiBase = 'https://project.supabase.co';

void main() {
  group('isPrivateMiniAppHost', () {
    test('ichki manzillar bloklanadi', () {
      for (final host in <String>[
        'localhost',
        '127.0.0.1',
        '10.1.2.3',
        '192.168.0.1',
        '172.16.0.1',
        '169.254.169.254',
        'metadata.google.internal',
        'router.local',
        'db.internal',
        '::1',
        'intranet',
      ]) {
        expect(isPrivateMiniAppHost(host), isTrue, reason: host);
      }
    });

    test('ommaviy domenlarga ruxsat', () {
      for (final host in <String>['islom.uz', 'www.youtube.com', 'alsamos.uz', '8.8.8.8']) {
        expect(isPrivateMiniAppHost(host), isFalse, reason: host);
      }
    });
  });

  group('normalizeMiniAppUrl', () {
    test('sxemasiz domen https ga keltiriladi', () {
      final result = normalizeMiniAppUrl('islom.uz');
      expect(result.ok, isTrue);
      expect(result.url, 'https://islom.uz/');
    });

    test('http https ga majburlanadi', () {
      final result = normalizeMiniAppUrl('http://islom.uz/quran');
      expect(result.ok, isTrue);
      expect(result.url!.startsWith('https://'), isTrue);
    });

    test('xavfli sxemalar rad etiladi', () {
      for (final bad in <String>[
        'javascript:alert(1)',
        'JAVASCRIPT:alert(1)',
        'data:text/html,x',
        'file:///etc/passwd',
        'blob:https://a.b/c',
      ]) {
        final result = normalizeMiniAppUrl(bad);
        expect(result.ok, isFalse, reason: bad);
        expect(result.reason, MiniAppUrlRejectReason.schemeNotAllowed);
      }
    });

    test('ichki tarmoq manzili rad etiladi', () {
      final result = normalizeMiniAppUrl('http://192.168.1.10:8080');
      expect(result.ok, isFalse);
      expect(result.reason, MiniAppUrlRejectReason.privateHost);
    });

    test('bo\u2019sh qiymat rad etiladi', () {
      expect(normalizeMiniAppUrl('   ').ok, isFalse);
      expect(normalizeMiniAppUrl(null).ok, isFalse);
    });

    test('punycode domen belgilanadi', () {
      final result = normalizeMiniAppUrl('https://xn--80ak6aa92e.com');
      expect(result.ok, isTrue);
      expect(result.punycode, isTrue);
    });
  });

  group('resolveMiniAppEmbedUrl', () {
    test('YouTube video', () {
      expect(
        resolveMiniAppEmbedUrl('https://www.youtube.com/watch?v=abc123'),
        'https://www.youtube.com/embed/abc123',
      );
    });

    test('youtu.be', () {
      expect(
        resolveMiniAppEmbedUrl('https://youtu.be/abc123'),
        'https://www.youtube.com/embed/abc123',
      );
    });

    test('Shorts', () {
      expect(
        resolveMiniAppEmbedUrl('https://www.youtube.com/shorts/abc123'),
        'https://www.youtube.com/embed/abc123',
      );
    });

    test('playlist', () {
      expect(
        resolveMiniAppEmbedUrl('https://www.youtube.com/playlist?list=PL1'),
        'https://www.youtube.com/embed/videoseries?list=PL1',
      );
    });

    test('kanal uchun soxta embed yasalmaydi', () {
      expect(resolveMiniAppEmbedUrl('https://www.youtube.com/@islomuz'), isNull);
      expect(resolveMiniAppEmbedUrl('https://www.youtube.com/channel/UC123'), isNull);
    });

    test('Instagram post va reel', () {
      expect(
        resolveMiniAppEmbedUrl('https://www.instagram.com/p/XYZ/'),
        'https://www.instagram.com/p/XYZ/embed/',
      );
      expect(
        resolveMiniAppEmbedUrl('https://www.instagram.com/reel/XYZ/'),
        'https://www.instagram.com/reel/XYZ/embed/',
      );
    });

    test('Instagram profil uchun embed yo\u2019q', () {
      expect(resolveMiniAppEmbedUrl('https://www.instagram.com/islom.uz/'), isNull);
    });

    test('Telegram kanal', () {
      expect(resolveMiniAppEmbedUrl('https://t.me/islomuz'), 'https://t.me/s/islomuz');
    });

    test('Telegram bot uchun embed yo\u2019q', () {
      expect(resolveMiniAppEmbedUrl('https://t.me/AlsamosBot'), isNull);
    });

    test('Vimeo', () {
      expect(
        resolveMiniAppEmbedUrl('https://vimeo.com/123456'),
        'https://player.vimeo.com/video/123456',
      );
    });

    test('oddiy sayt uchun null', () {
      expect(resolveMiniAppEmbedUrl('https://islom.uz'), isNull);
    });
  });

  group('isMiniAppFramingBlocked', () {
    test('bloklaydigan hostlar', () {
      expect(isMiniAppFramingBlocked('https://www.facebook.com/meta'), isTrue);
      expect(isMiniAppFramingBlocked('https://x.com/meta'), isTrue);
      expect(isMiniAppFramingBlocked('https://web.whatsapp.com'), isTrue);
    });

    test('boshqa saytlar', () {
      expect(isMiniAppFramingBlocked('https://islom.uz'), isFalse);
    });
  });

  group('buildMiniAppOpenPlan', () {
    test('oddiy sayt: direct -> proxy -> external', () {
      final plan = buildMiniAppOpenPlan(url: 'https://islom.uz', apiBase: apiBase);
      expect(
        plan.steps.map((step) => step.kind).toList(),
        <MiniAppOpenStepKind>[
          MiniAppOpenStepKind.direct,
          MiniAppOpenStepKind.proxy,
          MiniAppOpenStepKind.external,
        ],
      );
      expect(plan.steps.first.timeout, kMiniAppDirectTimeout);
      expect(plan.steps[1].timeout, kMiniAppProxyTimeout);
    });

    test('embed birinchi qadam bo\u2019ladi', () {
      final plan = buildMiniAppOpenPlan(url: 'https://youtu.be/abc123', apiBase: apiBase);
      expect(plan.steps.first.kind, MiniAppOpenStepKind.embed);
    });

    test('framing bloklangan saytda direct tushib qoladi', () {
      final plan = buildMiniAppOpenPlan(url: 'https://www.facebook.com/meta', apiBase: apiBase);
      expect(
        plan.steps.map((step) => step.kind).toList(),
        <MiniAppOpenStepKind>[MiniAppOpenStepKind.proxy, MiniAppOpenStepKind.external],
      );
    });

    test('display_mode=external darhol tashqi ochadi', () {
      final plan = buildMiniAppOpenPlan(
        url: 'https://islom.uz',
        displayMode: 'external',
        apiBase: apiBase,
      );
      expect(plan.steps.length, 1);
      expect(plan.steps.first.kind, MiniAppOpenStepKind.external);
    });

    test('apiBase bo\u2019lmasa proxy qadami qo\u2019shilmaydi', () {
      final plan = buildMiniAppOpenPlan(url: 'https://islom.uz');
      expect(
        plan.steps.map((step) => step.kind).toList(),
        <MiniAppOpenStepKind>[MiniAppOpenStepKind.direct, MiniAppOpenStepKind.external],
      );
    });

    test('native ilova deep_link bilan ochiladi', () {
      final plan = buildMiniAppOpenPlan(
        url: null,
        appType: 'native',
        deepLink: 'alsamos://wallet',
      );
      expect(plan.steps.first.kind, MiniAppOpenStepKind.native);
      expect(plan.steps.first.src, 'alsamos://wallet');
    });

    test('noto\u2019g\u2019ri URL uchun reja bo\u2019sh', () {
      final plan = buildMiniAppOpenPlan(url: 'javascript:alert(1)', apiBase: apiBase);
      expect(plan.isEmpty, isTrue);
      expect(plan.error, MiniAppUrlRejectReason.schemeNotAllowed);
    });

    test('bot turi tashqi ochiladi', () {
      final plan = buildMiniAppOpenPlan(
        url: 'https://t.me/AlsamosBot',
        appType: 'bot',
        apiBase: apiBase,
      );
      expect(plan.steps.length, 1);
      expect(plan.steps.first.kind, MiniAppOpenStepKind.external);
    });

    test('proxy URL kodlanishi web bilan bir xil', () {
      final proxied = buildMiniAppProxyUrl(apiBase, 'https://islom.uz/a?b=1', 42);
      expect(
        proxied,
        '$apiBase/functions/v1/mini-app-proxy?url='
            '${Uri.encodeComponent('https://islom.uz/a?b=1')}&_ts=42',
      );
    });
  });
}
