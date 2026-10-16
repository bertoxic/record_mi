class AppSettings {
  final bool autoRecord;
  final bool autoSpeakerphone;
  final bool floatingOverlayEnabled;
  final bool hasCompletedOnboarding;
  final bool recordVoipCalls;
  final bool voipAutoSpeakerphone;
  final String audioFormat; // "m4a", "wav", "3gp"
  final int audioSource; // -1 = default/auto, 6 = VOICE_RECOGNITION, 7 = VOICE_COMMUNICATION, 4 = VOICE_CALL, 1 = MIC
  final int trashRetentionDays; // default 30
  final String language; // "en", "es", "fr", "de", "zh", "ar", "hi"
  final String themeMode; // "dark", "light", "system"

  const AppSettings({
    this.autoRecord = true,
    this.autoSpeakerphone = false,
    this.floatingOverlayEnabled = true,
    this.hasCompletedOnboarding = false,
    this.recordVoipCalls = true, // Enabled for WhatsApp / VoIP recording
    this.voipAutoSpeakerphone = true, // When VoIP recording is enabled, speakerphone captures remote audio
    this.audioFormat = 'm4a',
    this.audioSource = -1,
    this.trashRetentionDays = 30,
    this.language = 'en',
    this.themeMode = 'dark',
  });

  AppSettings copyWith({
    bool? autoRecord,
    bool? autoSpeakerphone,
    bool? floatingOverlayEnabled,
    bool? hasCompletedOnboarding,
    bool? recordVoipCalls,
    bool? voipAutoSpeakerphone,
    String? audioFormat,
    int? audioSource,
    int? trashRetentionDays,
    String? language,
    String? themeMode,
  }) {
    return AppSettings(
      autoRecord: autoRecord ?? this.autoRecord,
      autoSpeakerphone: autoSpeakerphone ?? this.autoSpeakerphone,
      floatingOverlayEnabled: floatingOverlayEnabled ?? this.floatingOverlayEnabled,
      hasCompletedOnboarding: hasCompletedOnboarding ?? this.hasCompletedOnboarding,
      recordVoipCalls: recordVoipCalls ?? this.recordVoipCalls,
      voipAutoSpeakerphone: voipAutoSpeakerphone ?? this.voipAutoSpeakerphone,
      audioFormat: audioFormat ?? this.audioFormat,
      audioSource: audioSource ?? this.audioSource,
      trashRetentionDays: trashRetentionDays ?? this.trashRetentionDays,
      language: language ?? this.language,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  Map<String, dynamic> toJson() => {
    'autoRecord': autoRecord,
    'autoSpeakerphone': autoSpeakerphone,
    'floatingOverlayEnabled': floatingOverlayEnabled,
    'hasCompletedOnboarding': hasCompletedOnboarding,
    'recordVoipCalls': recordVoipCalls,
    'voipAutoSpeakerphone': voipAutoSpeakerphone,
    'audioFormat': audioFormat,
    'audioSource': audioSource,
    'trashRetentionDays': trashRetentionDays,
    'language': language,
    'themeMode': themeMode,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    autoRecord: json['autoRecord'] as bool? ?? true,
    autoSpeakerphone: json['autoSpeakerphone'] as bool? ?? false,
    floatingOverlayEnabled: json['floatingOverlayEnabled'] as bool? ?? true,
    hasCompletedOnboarding: json['hasCompletedOnboarding'] as bool? ?? false,
    recordVoipCalls: json['recordVoipCalls'] as bool? ?? true,
    voipAutoSpeakerphone: json['voipAutoSpeakerphone'] as bool? ?? true,
    audioFormat: json['audioFormat'] as String? ?? 'm4a',
    audioSource: (json['audioSource'] as num?)?.toInt() ?? -1,
    trashRetentionDays: (json['trashRetentionDays'] as num?)?.toInt() ?? 30,
    language: json['language'] as String? ?? 'en',
    themeMode: json['themeMode'] as String? ?? 'dark',
  );
}
