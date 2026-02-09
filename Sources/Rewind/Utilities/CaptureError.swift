import Foundation

enum CaptureError: Error {
  case noDisplay
  case noAudioDevice
  case writerUnavailable
  case noFramesCaptured
  case exportFailed
  case saveInProgress
  case invalidDuration
}
