import AppKit

enum SoundFeedbackEvent {
  case action
  case connected
  case completed
  case dismissed
  case error
  case favorite

  fileprivate var soundName: NSSound.Name {
    switch self {
    case .action:
      return NSSound.Name("Pop")
    case .connected:
      return NSSound.Name("Hero")
    case .completed:
      return NSSound.Name("Glass")
    case .dismissed:
      return NSSound.Name("Tink")
    case .error:
      return NSSound.Name("Basso")
    case .favorite:
      return NSSound.Name("Purr")
    }
  }
}

@MainActor
enum SoundFeedbackService {
  static func play(_ event: SoundFeedbackEvent, settings: SettingsStore) {
    guard settings.soundFeedbackEnabled,
          settings.soundFeedbackVolume > 0,
          let sound = NSSound(named: event.soundName) else {
      return
    }

    sound.stop()
    sound.volume = Float(settings.soundFeedbackVolume)
    sound.play()
  }
}
