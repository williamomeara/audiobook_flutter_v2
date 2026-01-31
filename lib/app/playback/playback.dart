/// Playback state machine module
///
/// This module provides a clean state machine architecture for playback navigation.
/// It uses sealed classes and explicit events to ensure impossible states cannot occur.
library;

export 'state/playback_view_state.dart';
export 'state/playback_event.dart';
export 'state/playback_side_effect.dart';
export 'state/playback_state_machine.dart';
export 'playback_view_notifier.dart';
