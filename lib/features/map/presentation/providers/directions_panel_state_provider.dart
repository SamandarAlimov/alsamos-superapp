// Directions Panel State Persistence Provider
// Saves last panel state (collapsed/half/expanded for mobile, collapsed state for desktop)
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/draggable_directions_sheet.dart';

// ═══════════════════════════════════════════════════════════════════════════
// State Classes
// ═══════════════════════════════════════════════════════════════════════════

class DirectionsPanelState {
  final SheetSnapState mobileSheetState;
  final bool desktopCollapsed;
  final double desktopPanelWidth;

  const DirectionsPanelState({
    this.mobileSheetState = SheetSnapState.half, // default
    this.desktopCollapsed = false,
    this.desktopPanelWidth = 400,
  });

  DirectionsPanelState copyWith({
    SheetSnapState? mobileSheetState,
    bool? desktopCollapsed,
    double? desktopPanelWidth,
  }) {
    return DirectionsPanelState(
      mobileSheetState: mobileSheetState ?? this.mobileSheetState,
      desktopCollapsed: desktopCollapsed ?? this.desktopCollapsed,
      desktopPanelWidth: desktopPanelWidth ?? this.desktopPanelWidth,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// State Notifier
// ═══════════════════════════════════════════════════════════════════════════

class DirectionsPanelStateNotifier extends StateNotifier<DirectionsPanelState> {
  DirectionsPanelStateNotifier() : super(const DirectionsPanelState()) {
    _loadState();
  }

  static const _keyMobileState = 'directions_mobile_state';
  static const _keyDesktopCollapsed = 'directions_desktop_collapsed';
  static const _keyDesktopWidth = 'directions_desktop_width';

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load mobile state
      final mobileStateStr = prefs.getString(_keyMobileState);
      SheetSnapState mobileState = SheetSnapState.half;
      if (mobileStateStr != null) {
        switch (mobileStateStr) {
          case 'collapsed':
            mobileState = SheetSnapState.collapsed;
            break;
          case 'half':
            mobileState = SheetSnapState.half;
            break;
          case 'expanded':
            mobileState = SheetSnapState.expanded;
            break;
        }
      }

      // Load desktop state
      final desktopCollapsed = prefs.getBool(_keyDesktopCollapsed) ?? false;
      final desktopWidth = prefs.getDouble(_keyDesktopWidth) ?? 400;

      state = DirectionsPanelState(
        mobileSheetState: mobileState,
        desktopCollapsed: desktopCollapsed,
        desktopPanelWidth: desktopWidth,
      );
    } catch (e) {
      // Ignore errors, use defaults
    }
  }

  Future<void> setMobileSheetState(SheetSnapState newState) async {
    state = state.copyWith(mobileSheetState: newState);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyMobileState, newState.name);
    } catch (e) {
      // Ignore save errors
    }
  }

  Future<void> setDesktopCollapsed(bool collapsed) async {
    state = state.copyWith(desktopCollapsed: collapsed);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyDesktopCollapsed, collapsed);
    } catch (e) {
      // Ignore save errors
    }
  }

  Future<void> setDesktopPanelWidth(double width) async {
    state = state.copyWith(desktopPanelWidth: width);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyDesktopWidth, width);
    } catch (e) {
      // Ignore save errors
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Provider
// ═══════════════════════════════════════════════════════════════════════════

final directionsPanelStateProvider =
    StateNotifierProvider<DirectionsPanelStateNotifier, DirectionsPanelState>(
  (ref) => DirectionsPanelStateNotifier(),
);
