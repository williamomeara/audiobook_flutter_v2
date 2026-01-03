import 'package:core_domain/core_domain.dart';

/// Specification for a downloadable asset.
class AssetSpec {
  const AssetSpec({
    required this.key,
    required this.displayName,
    required this.downloadUrl,
    required this.installPath,
    this.sizeBytes,
    this.checksum,
    this.isCore = false,
    this.engineType,
  });

  /// Unique key for this asset.
  final String key;

  /// Human-readable name.
  final String displayName;

  /// URL to download from.
  final String downloadUrl;

  /// Path where asset should be installed.
  final String installPath;

  /// Expected file size in bytes (for verification).
  final int? sizeBytes;

  /// Expected checksum (SHA-256) for verification.
  final String? checksum;

  /// Whether this is a core (shared) model vs per-voice asset.
  final bool isCore;

  /// Engine this asset belongs to.
  final EngineType? engineType;

  @override
  String toString() => 'AssetSpec($key, ${sizeBytes ?? "unknown"} bytes)';
}

/// Asset key for cache/state lookups.
class AssetKey {
  const AssetKey(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssetKey && runtimeType == other.runtimeType && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'AssetKey($value)';
}
