import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Centralized haptic feedback utility for the app.
/// 
/// Provides methods for different haptic intensities and respects
/// the user's haptic feedback preference setting.
class AppHaptics {
  static bool _enabled = true;

  /// Enable or disable haptic feedback globally.
  static void setEnabled(bool enabled) {
    _enabled = enabled;
    if (kDebugMode) debugPrint('[AppHaptics] setEnabled: $enabled');
  }

  /// Check if haptic feedback is currently enabled.
  static bool get isEnabled => _enabled;

  /// Light impact for subtle confirmations (play, tap).
  static void light() {
    if (kDebugMode) debugPrint('[AppHaptics] light() called, enabled=$_enabled');
    if (_enabled) HapticFeedback.lightImpact();
  }

  /// Medium impact for significant actions (pause, chapter change).
  static void medium() {
    if (kDebugMode) debugPrint('[AppHaptics] medium() called, enabled=$_enabled');
    if (_enabled) HapticFeedback.mediumImpact();
  }

  /// Heavy impact for hard boundaries (limits, errors).
  static void heavy() {
    if (kDebugMode) debugPrint('[AppHaptics] heavy() called, enabled=$_enabled');
    if (_enabled) HapticFeedback.heavyImpact();
  }

  /// Selection click for incremental changes (speed, volume steps).
  static void selection() {
    if (kDebugMode) debugPrint('[AppHaptics] selection() called, enabled=$_enabled');
    if (_enabled) HapticFeedback.selectionClick();
  }

  /// Vibrate for general feedback (fallback).
  static void vibrate() {
    if (kDebugMode) debugPrint('[AppHaptics] vibrate() called, enabled=$_enabled');
    if (_enabled) HapticFeedback.vibrate();
  }
}
