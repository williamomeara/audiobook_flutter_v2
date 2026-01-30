import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// Migration V8: Add segment type and metadata columns to segments table
///
/// Adds columns for storing segment type classification and metadata:
/// - segment_type: The type of segment (text, figure, heading, quote)
/// - metadata_json: JSON-encoded metadata (e.g., imagePath, altText for figures)
///
/// These columns enable:
/// - Displaying images in books during playback
/// - Skipping non-text segments during TTS
class MigrationV8 {
  static Future<void> up(Database db) async {
    // Add segment_type column if it doesn't exist
    try {
      await db.rawQuery('SELECT segment_type FROM segments LIMIT 1');
    } catch (e) {
      // Column doesn't exist, add it
      // Default to 'text' for existing segments
      await db.execute('''
        ALTER TABLE segments ADD COLUMN segment_type TEXT DEFAULT 'text'
      ''');
    }

    // Add metadata_json column if it doesn't exist
    try {
      await db.rawQuery('SELECT metadata_json FROM segments LIMIT 1');
    } catch (e) {
      // Column doesn't exist, add it
      await db.execute('''
        ALTER TABLE segments ADD COLUMN metadata_json TEXT
      ''');
    }
    
    // Backfill: Detect figure segments from text content
    // Segments with text = 'image' or 'Image' are figure placeholders
    await db.execute('''
      UPDATE segments 
      SET segment_type = 'figure' 
      WHERE LOWER(text) = 'image'
    ''');

    // Insert the schema version record
    await db.insert('schema_version', {
      'version': 8,
      'applied_at': DateTime.now().millisecondsSinceEpoch,
      'description': 'Added segment type and metadata columns (V8)',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
  
  /// Encode metadata map to JSON string for storage.
  static String? encodeMetadata(Map<String, dynamic>? metadata) {
    if (metadata == null || metadata.isEmpty) return null;
    return jsonEncode(metadata);
  }
  
  /// Decode JSON string to metadata map.
  static Map<String, dynamic>? decodeMetadata(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }
}
