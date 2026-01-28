import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mini_player.dart';

/// Wraps a screen with a mini-player at the bottom when playback is active.
///
/// Usage:
/// ```dart
/// MiniPlayerScaffold(
///   child: LibraryScreen(),
/// )
/// ```
///
/// The mini-player only appears when:
/// - Audio is currently playing or paused
/// - showMiniPlayer is true (default)
class MiniPlayerScaffold extends ConsumerWidget {
  const MiniPlayerScaffold({
    super.key,
    required this.child,
    this.showMiniPlayer = true,
  });

  final Widget child;
  final bool showMiniPlayer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!showMiniPlayer) return child;

    return Column(
      children: [
        Expanded(child: child),
        const MiniPlayer(),
      ],
    );
  }
}
