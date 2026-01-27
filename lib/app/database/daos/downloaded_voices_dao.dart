import 'package:sqflite/sqflite.dart';

/// Data Access Object for downloaded_voices table.
///
/// Tracks which voice models are installed locally.
/// This provides fast queries for "is voice X installed?" without filesystem checks.
///
/// Note: .manifest files are still used for atomic install verification.
/// This table is for query optimization and UI display.
class DownloadedVoicesDao {
  final Database _db;

  DownloadedVoicesDao(this._db);

  /// Check if a voice is installed.
  Future<bool> isInstalled(String voiceId) async {
    final result = await _db.rawQuery(
      'SELECT 1 FROM downloaded_voices WHERE voice_id = ? LIMIT 1',
      [voiceId],
    );
    return result.isNotEmpty;
  }

  /// Get a downloaded voice by ID.
  Future<Map<String, dynamic>?> getVoice(String voiceId) async {
    final results = await _db.query(
      'downloaded_voices',
      where: 'voice_id = ?',
      whereArgs: [voiceId],
      limit: 1,
    );
    return results.isEmpty ? null : results.first;
  }

  /// Get all downloaded voices.
  Future<List<Map<String, dynamic>>> getAllVoices() async {
    return await _db.query(
      'downloaded_voices',
      orderBy: 'downloaded_at DESC',
    );
  }

  /// Get all downloaded voices for an engine type.
  Future<List<Map<String, dynamic>>> getVoicesForEngine(String engineType) async {
    return await _db.query(
      'downloaded_voices',
      where: 'engine_type = ?',
      whereArgs: [engineType],
      orderBy: 'display_name ASC',
    );
  }

  /// Record a voice as downloaded.
  Future<void> markInstalled(Map<String, dynamic> voice) async {
    await _db.insert(
      'downloaded_voices',
      voice,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Remove a voice from the installed list.
  Future<void> markUninstalled(String voiceId) async {
    await _db.delete(
      'downloaded_voices',
      where: 'voice_id = ?',
      whereArgs: [voiceId],
    );
  }

  /// Get total storage used by downloaded voices.
  Future<int> getTotalStorageBytes() async {
    final result = await _db.rawQuery(
      'SELECT SUM(size_bytes) as total FROM downloaded_voices',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get count of downloaded voices.
  Future<int> getVoiceCount() async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) as count FROM downloaded_voices',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get downloaded voice IDs as a set (for fast membership checks).
  Future<Set<String>> getInstalledVoiceIds() async {
    final results = await _db.query(
      'downloaded_voices',
      columns: ['voice_id'],
    );
    return results.map((r) => r['voice_id'] as String).toSet();
  }

  /// Update the install path for a voice.
  Future<void> updateInstallPath(String voiceId, String installPath) async {
    await _db.update(
      'downloaded_voices',
      {'install_path': installPath},
      where: 'voice_id = ?',
      whereArgs: [voiceId],
    );
  }

  /// Delete all voices for an engine type.
  Future<void> deleteVoicesForEngine(String engineType) async {
    await _db.delete(
      'downloaded_voices',
      where: 'engine_type = ?',
      whereArgs: [engineType],
    );
  }
}
