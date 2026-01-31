import 'dart:io';

import 'package:flutter/material.dart';

/// Widget for figure/image display.
///
/// Shows the actual image when imagePath is provided and the file exists,
/// otherwise shows a placeholder icon.
///
/// Supports optional width/height to constrain image display to its natural
/// aspect ratio instead of filling the available width.
class FigureBlockWidget extends StatelessWidget {
  const FigureBlockWidget({
    super.key,
    required this.caption,
    required this.isDarkMode,
    required this.isActive,
    required this.onTap,
    this.imagePath,
    this.onSkip,
    this.width,
    this.height,
  });

  /// The figure caption (from alt text or placeholder).
  final String caption;

  /// Path to the extracted image file.
  final String? imagePath;

  /// Original image width in pixels (used to constrain aspect ratio).
  final int? width;

  /// Original image height in pixels (used to constrain aspect ratio).
  final int? height;

  /// Whether to use dark mode styling.
  final bool isDarkMode;

  /// Whether this is the currently active segment.
  final bool isActive;

  /// Called when tapped for navigation.
  final VoidCallback onTap;

  /// Called when user wants to skip this figure.
  final VoidCallback? onSkip;

  /// Check if the image file exists.
  bool get _imageExists {
    if (imagePath == null || imagePath!.isEmpty) return false;
    return File(imagePath!).existsSync();
  }

  /// Calculate the aspect ratio from width/height.
  double? get _aspectRatio {
    if (width != null && height != null && height! > 0) {
      return width! / height!;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = isActive
        ? Colors.amber.shade400
        : (isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300);
    final bgColor = isDarkMode ? Colors.grey.shade900 : Colors.grey.shade100;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: borderColor,
            width: isActive ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with figure label and skip button
            _buildHeader(context),
            // Image or placeholder
            Padding(
              padding: const EdgeInsets.all(12),
              child: _imageExists ? _buildImage() : _buildPlaceholder(),
            ),
            // Caption
            if (caption.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Text(
                  caption,
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: isDarkMode
                        ? Colors.grey.shade400
                        : Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final headerColor =
        isDarkMode ? const Color(0xFF2D2D2D) : const Color(0xFFE8E8E8);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: headerColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(7),
          topRight: Radius.circular(7),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.image,
            size: 14,
            color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
          const SizedBox(width: 6),
          Text(
            'FIGURE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
          const Spacer(),
          if (onSkip != null)
            _SkipButton(onTap: onSkip!, isDarkMode: isDarkMode),
        ],
      ),
    );
  }

  Widget _buildImage() {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.file(
        File(imagePath!),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholder();
        },
      ),
    );

    // If we have aspect ratio info, constrain the image to avoid "blowing up"
    // small images to full width
    if (_aspectRatio != null) {
      // Calculate max width based on screen size - limit small images
      // to roughly their natural size (with some scaling for high DPI)
      return LayoutBuilder(
        builder: (context, constraints) {
          // For small images, don't expand beyond ~2x their natural size
          // For larger images, allow them to fill available width
          final maxWidth = (width != null && width! < constraints.maxWidth / 2)
              ? (width! * 2.0).clamp(100.0, constraints.maxWidth)
              : constraints.maxWidth;

          // Calculate height from aspect ratio
          final constrainedWidth = maxWidth.clamp(0.0, constraints.maxWidth);
          final constrainedHeight = constrainedWidth / _aspectRatio!;

          // Limit max height to prevent very tall images from dominating
          final maxHeight = constraints.maxWidth * 1.5; // 1.5:1 max height ratio
          final finalHeight = constrainedHeight.clamp(0.0, maxHeight);
          final finalWidth = finalHeight * _aspectRatio!;

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: finalWidth,
                maxHeight: finalHeight,
              ),
              child: AspectRatio(
                aspectRatio: _aspectRatio!,
                child: image,
              ),
            ),
          );
        },
      );
    }

    // Fallback: no dimension info, let it fill naturally but limit height
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 400),
      child: image,
    );
  }

  Widget _buildPlaceholder() {
    return Column(
      children: [
        Icon(
          Icons.image_not_supported_outlined,
          size: 48,
          color: isDarkMode ? Colors.grey.shade600 : Colors.grey.shade400,
        ),
        const SizedBox(height: 8),
        Text(
          'Image not available',
          style: TextStyle(
            fontSize: 12,
            color: isDarkMode ? Colors.grey.shade600 : Colors.grey.shade500,
          ),
        ),
      ],
    );
  }
}

/// Skip button for figures.
class _SkipButton extends StatelessWidget {
  const _SkipButton({
    required this.onTap,
    required this.isDarkMode,
  });

  final VoidCallback onTap;
  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    final color = isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.skip_next,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              'Skip',
              style: TextStyle(
                fontSize: 11,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
