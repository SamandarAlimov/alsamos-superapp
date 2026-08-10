import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:alsamos_flutter/core/responsive/breakpoints.dart';

void main() {
  group('resolveNavMode — no dead zones from 320px to 1400px', () {
    test('every width maps to exactly one NavMode', () {
      for (double w = 320; w <= 1400; w += 1) {
        final mode = resolveNavMode(w);
        expect(
          NavMode.values.contains(mode),
          isTrue,
          reason: 'Width $w must resolve to a valid NavMode',
        );
      }
    });

    test('boundaries resolve correctly', () {
      expect(resolveNavMode(320), NavMode.bottomNav);
      expect(resolveNavMode(599), NavMode.bottomNav);
      expect(resolveNavMode(600), NavMode.bottomNav);
      expect(resolveNavMode(899), NavMode.bottomNav);
      expect(resolveNavMode(900), NavMode.sidebarRail);
      expect(resolveNavMode(1199), NavMode.sidebarRail);
      expect(resolveNavMode(1200), NavMode.sidebarExpanded);
      expect(resolveNavMode(1400), NavMode.sidebarExpanded);
    });

    test('no width has zero navigation (sweep every 10px)', () {
      for (double w = 320; w <= 1400; w += 10) {
        final mode = resolveNavMode(w);
        final hasSidebar =
            mode == NavMode.sidebarExpanded || mode == NavMode.sidebarRail;
        final hasBottomNav = mode == NavMode.bottomNav;

        expect(
          hasSidebar || hasBottomNav,
          isTrue,
          reason:
              'Width $w must have either a docked sidebar or bottom nav bar',
        );
        expect(
          hasSidebar && hasBottomNav,
          isFalse,
          reason: 'Width $w must not have both sidebar and bottom nav',
        );
      }
    });

    test('transition at exactly 900px is clean (no gap)', () {
      final below = resolveNavMode(899.9);
      final at = resolveNavMode(900);
      expect(below, NavMode.bottomNav);
      expect(at, NavMode.sidebarRail);
    });

    test('transition at exactly 1200px is clean (no gap)', () {
      final below = resolveNavMode(1199.9);
      final at = resolveNavMode(1200);
      expect(below, NavMode.sidebarRail);
      expect(at, NavMode.sidebarExpanded);
    });

    test('Responsive class agrees with resolveNavMode', () {
      for (double w = 320; w <= 1400; w += 50) {
        final responsive = Responsive(Size(w, 800));
        final expected = resolveNavMode(w);
        expect(
          responsive.navMode,
          expected,
          reason: 'Responsive.navMode at $w must match resolveNavMode',
        );
      }
    });

    test('showDockedSidebar and showBottomNav are mutually exclusive', () {
      for (double w = 320; w <= 1400; w += 10) {
        final responsive = Responsive(Size(w, 800));
        final docked = responsive.showDockedSidebar;
        final bottom = responsive.showBottomNav;

        expect(
          docked ^ bottom,
          isTrue,
          reason:
              'Width $w: exactly one of showDockedSidebar ($docked) or showBottomNav ($bottom) must be true',
        );
      }
    });
  });
}
