/// Voice engine type enumeration.
enum EngineType {
  /// Device's built-in TTS engine.
  device,

  /// Piper (VITS-based) neural TTS.
  piper,

  /// Supertonic ONNX TTS.
  supertonic,

  /// Kokoro sherpa-onnx TTS.
  kokoro,
}

/// Represents a TTS voice configuration.
class Voice {
  const Voice({
    required this.id,
    required this.displayName,
    required this.engine,
    this.languageCode = 'en',
    this.speakerId,
    this.description,
  });

  /// Unique voice identifier (persisted in settings/books).
  final String id;

  /// Human-friendly display name.
  final String displayName;

  /// Which TTS engine this voice belongs to.
  final EngineType engine;

  /// Language code (e.g., 'en', 'en_US').
  final String languageCode;

  /// Engine-specific speaker ID (e.g., Kokoro speaker index).
  final int? speakerId;

  /// Optional description of the voice characteristics.
  final String? description;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Voice && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Voice(id: $id, name: $displayName, engine: $engine)';
}

/// Voice identifiers used across the app.
///
/// Keep these stable as they are persisted in storage.
class VoiceIds {
  VoiceIds._();

  static const device = 'device';

  // Supertonic voices (M = Male, F = Female)
  static const supertonicM1 = 'supertonic_m1';
  static const supertonicM2 = 'supertonic_m2';
  static const supertonicM3 = 'supertonic_m3';
  static const supertonicM4 = 'supertonic_m4';
  static const supertonicM5 = 'supertonic_m5';
  static const supertonicF1 = 'supertonic_f1';
  static const supertonicF2 = 'supertonic_f2';
  static const supertonicF3 = 'supertonic_f3';
  static const supertonicF4 = 'supertonic_f4';
  static const supertonicF5 = 'supertonic_f5';

  static const supertonicVoices = [
    supertonicM1,
    supertonicM2,
    supertonicM3,
    supertonicM4,
    supertonicM5,
    supertonicF1,
    supertonicF2,
    supertonicF3,
    supertonicF4,
    supertonicF5,
  ];

  // Kokoro voices (AF = American Female, AM = American Male, BF = British Female, BM = British Male)
  static const kokoroAfDefault = 'kokoro_af';
  static const kokoroAfBella = 'kokoro_af_bella';
  static const kokoroAfNicole = 'kokoro_af_nicole';
  static const kokoroAfSarah = 'kokoro_af_sarah';
  static const kokoroAfSky = 'kokoro_af_sky';
  static const kokoroAmAdam = 'kokoro_am_adam';
  static const kokoroAmMichael = 'kokoro_am_michael';
  static const kokoroBfEmma = 'kokoro_bf_emma';
  static const kokoroBfIsabella = 'kokoro_bf_isabella';
  static const kokoroBmGeorge = 'kokoro_bm_george';
  static const kokoroBmLewis = 'kokoro_bm_lewis';

  static const kokoroVoices = [
    kokoroAfDefault,
    kokoroAfBella,
    kokoroAfNicole,
    kokoroAfSarah,
    kokoroAfSky,
    kokoroAmAdam,
    kokoroAmMichael,
    kokoroBfEmma,
    kokoroBfIsabella,
    kokoroBmGeorge,
    kokoroBmLewis,
  ];

  /// Speaker ID mapping for Kokoro (0-10).
  static const kokoroSpeakerIds = <String, int>{
    kokoroAfDefault: 0,
    kokoroAfBella: 1,
    kokoroAfNicole: 2,
    kokoroAfSarah: 3,
    kokoroAfSky: 4,
    kokoroAmAdam: 5,
    kokoroAmMichael: 6,
    kokoroBfEmma: 7,
    kokoroBfIsabella: 8,
    kokoroBmGeorge: 9,
    kokoroBmLewis: 10,
  };

  // Piper voices
  static const piperEnUsLessacMedium = 'piper:en_US-lessac-medium';
  static const piperEnUsAmyMedium = 'piper:en_US-amy-medium';
  static const piperEnUsDannyLow = 'piper:en_US-danny-low';
  static const piperEnUsLibrittsMedium = 'piper:en_US-libritts_r-medium';
  static const piperEnGbJennyMedium = 'piper:en_GB-jenny_dioco-medium';
  static const piperEnGbAlanMedium = 'piper:en_GB-alan-medium';

  static const piperVoices = [
    piperEnUsLessacMedium,
    piperEnUsAmyMedium,
    piperEnUsDannyLow,
    piperEnUsLibrittsMedium,
    piperEnGbJennyMedium,
    piperEnGbAlanMedium,
  ];

  /// Check if voice ID is a Supertonic voice.
  static bool isSupertonic(String voiceId) => supertonicVoices.contains(voiceId);

  /// Check if voice ID is a Kokoro voice.
  static bool isKokoro(String voiceId) => kokoroVoices.contains(voiceId);

  /// Check if voice ID is a Piper voice.
  static bool isPiper(String voiceId) => voiceId.startsWith('piper:');

  /// Check if voice ID is an AI voice (not device TTS).
  static bool isAi(String voiceId) => voiceId != device;

  /// Get engine type for a voice ID.
  static EngineType engineFor(String voiceId) {
    if (isSupertonic(voiceId)) return EngineType.supertonic;
    if (isKokoro(voiceId)) return EngineType.kokoro;
    if (isPiper(voiceId)) return EngineType.piper;
    return EngineType.device;
  }

  /// Get Kokoro speaker ID for a voice.
  static int kokoroSpeakerId(String voiceId) => kokoroSpeakerIds[voiceId] ?? 0;

  /// Get Piper model key from voice ID.
  static String? piperModelKey(String voiceId) {
    if (voiceId.startsWith('piper:')) {
      return voiceId.substring(6);
    }
    return null;
  }
}
