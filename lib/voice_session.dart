enum VoiceSessionPhase { idle, starting, listening, processing }

class VoiceSessionGate {
  VoiceSessionPhase phase = VoiceSessionPhase.idle;
  bool _stopRequested = false;

  bool get stopRequested => _stopRequested;

  bool requestStart() {
    if (phase != VoiceSessionPhase.idle) return false;
    phase = VoiceSessionPhase.starting;
    _stopRequested = false;
    return true;
  }

  bool requestStop() {
    if (phase == VoiceSessionPhase.starting) {
      _stopRequested = true;
      return true;
    }
    if (phase != VoiceSessionPhase.listening) return false;
    phase = VoiceSessionPhase.processing;
    return true;
  }

  bool recordingStarted() {
    if (phase != VoiceSessionPhase.starting) return false;
    if (_stopRequested) {
      phase = VoiceSessionPhase.processing;
      _stopRequested = false;
      return true;
    }
    phase = VoiceSessionPhase.listening;
    return false;
  }

  void recordingStartFailed() {
    phase = VoiceSessionPhase.idle;
    _stopRequested = false;
  }

  void processingFinished() {
    phase = VoiceSessionPhase.idle;
    _stopRequested = false;
  }
}
