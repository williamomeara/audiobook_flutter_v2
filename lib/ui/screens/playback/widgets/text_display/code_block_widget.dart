import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';

/// Widget for rendering code blocks with syntax highlighting.
/// 
/// Used in the playback view to display code segments with
/// appropriate styling and optional skip functionality.
class CodeBlockWidget extends StatelessWidget {
  const CodeBlockWidget({
    super.key,
    required this.text,
    required this.language,
    required this.isDarkMode,
    required this.isActive,
    required this.onTap,
    this.onSkip,
  });
  
  /// The code text to display (may include [CODE]/[/CODE] markers).
  final String text;
  
  /// The detected programming language for syntax highlighting.
  final String language;
  
  /// Whether to use dark mode theme.
  final bool isDarkMode;
  
  /// Whether this is the currently active segment.
  final bool isActive;
  
  /// Called when the code block is tapped (for navigation).
  final VoidCallback onTap;
  
  /// Called when user wants to skip this code block.
  final VoidCallback? onSkip;
  
  /// Clean the code text by removing markers.
  String get cleanCode {
    return text
        .replaceAll(RegExp(r'\[CODE\]'), '')
        .replaceAll(RegExp(r'\[/CODE\]'), '')
        .trim();
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = isDarkMode ? atomOneDarkTheme : githubTheme;
    final borderColor = isActive 
        ? Colors.amber.shade400 
        : (isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300);
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF6F8FA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: borderColor,
            width: isActive ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with language badge and copy button
            _buildHeader(context),
            // Code content with syntax highlighting
            ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(7),
                bottomRight: Radius.circular(7),
              ),
              child: HighlightView(
                cleanCode,
                language: _mapLanguage(language),
                theme: theme,
                padding: const EdgeInsets.all(12),
                textStyle: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildHeader(BuildContext context) {
    final headerColor = isDarkMode 
        ? const Color(0xFF2D2D2D) 
        : const Color(0xFFE8E8E8);
    
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
          // Language badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              language.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? Colors.grey.shade300 : Colors.grey.shade700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // "Code" label
          Icon(
            Icons.code,
            size: 14,
            color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
          const Spacer(),
          // Copy button
          _CopyButton(code: cleanCode, isDarkMode: isDarkMode),
          if (onSkip != null) ...[
            const SizedBox(width: 4),
            // Skip button
            _SkipButton(onTap: onSkip!, isDarkMode: isDarkMode),
          ],
        ],
      ),
    );
  }
  
  /// Map our detected language to highlight.js language identifier.
  String _mapLanguage(String detected) {
    // highlight.js uses specific language identifiers
    switch (detected.toLowerCase()) {
      case 'python':
        return 'python';
      case 'javascript':
      case 'js':
        return 'javascript';
      case 'typescript':
      case 'ts':
        return 'typescript';
      case 'dart':
        return 'dart';
      case 'java':
        return 'java';
      case 'kotlin':
        return 'kotlin';
      case 'swift':
        return 'swift';
      case 'html':
        return 'xml';
      case 'xml':
        return 'xml';
      case 'css':
        return 'css';
      case 'json':
        return 'json';
      case 'yaml':
      case 'yml':
        return 'yaml';
      case 'sql':
        return 'sql';
      case 'bash':
      case 'shell':
      case 'sh':
        return 'bash';
      case 'ruby':
        return 'ruby';
      case 'go':
        return 'go';
      case 'rust':
        return 'rust';
      case 'c':
        return 'c';
      case 'cpp':
      case 'c++':
        return 'cpp';
      case 'csharp':
      case 'c#':
        return 'csharp';
      case 'php':
        return 'php';
      case 'django':
      case 'jinja':
        return 'django';
      default:
        return 'plaintext';
    }
  }
}

/// Copy to clipboard button.
class _CopyButton extends StatefulWidget {
  const _CopyButton({
    required this.code,
    required this.isDarkMode,
  });
  
  final String code;
  final bool isDarkMode;
  
  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;
  
  void _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (mounted) {
      setState(() => _copied = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final color = widget.isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600;
    
    return InkWell(
      onTap: _copyToClipboard,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _copied ? Icons.check : Icons.copy,
              size: 14,
              color: _copied ? Colors.green : color,
            ),
            const SizedBox(width: 4),
            Text(
              _copied ? 'Copied!' : 'Copy',
              style: TextStyle(
                fontSize: 11,
                color: _copied ? Colors.green : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Skip button for code blocks.
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

/// Widget for figure/image display.
/// 
/// Shows the actual image when imagePath is provided and the file exists,
/// otherwise shows a placeholder icon.
class FigureBlockWidget extends StatelessWidget {
  const FigureBlockWidget({
    super.key,
    required this.caption,
    required this.isDarkMode,
    required this.isActive,
    required this.onTap,
    this.imagePath,
    this.onSkip,
  });
  
  /// The figure caption (from alt text or placeholder).
  final String caption;
  
  /// Path to the extracted image file.
  final String? imagePath;
  
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
  
  @override
  Widget build(BuildContext context) {
    final borderColor = isActive 
        ? Colors.amber.shade400 
        : (isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300);
    final bgColor = isDarkMode 
        ? Colors.grey.shade900 
        : Colors.grey.shade100;
    
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
              child: _imageExists 
                  ? _buildImage() 
                  : _buildPlaceholder(),
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
                    color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600,
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
    final headerColor = isDarkMode 
        ? const Color(0xFF2D2D2D) 
        : const Color(0xFFE8E8E8);
    
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.file(
        File(imagePath!),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholder();
        },
      ),
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
