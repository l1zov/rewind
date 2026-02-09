import AppKit
import Carbon

@MainActor
final class GlobalHotkeyManager {
  static let shared = GlobalHotkeyManager()

  private let hotKeySignature = OSType(0x52574E44) // "RWND"
  private let saveReplayHotKeyId: UInt32 = 1
  private let recordToggleHotKeyId: UInt32 = 2
  private var saveReplayHotKeyRef: EventHotKeyRef?
  private var recordToggleHotKeyRef: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?
  private var saveReplayHotkey: Hotkey = .default
  private var recordToggleHotkey: Hotkey = .startRecordingDefault

  func register(
    saveReplayHotkey: Hotkey = .default,
    recordToggleHotkey: Hotkey = .startRecordingDefault
  ) {
    self.saveReplayHotkey = saveReplayHotkey
    self.recordToggleHotkey = recordToggleHotkey
    unregister()

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

    let installStatus = InstallEventHandler(
      GetEventDispatcherTarget(),
      { _, event, userData in
        guard let userData else { return noErr }
        let manager = Unmanaged<GlobalHotkeyManager>
          .fromOpaque(userData)
          .takeUnretainedValue()
        Task { @MainActor in
          manager.handleHotKey(event: event)
        }
        return noErr
      },
      1,
      &eventType,
      UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
      &eventHandler
    )
    guard installStatus == noErr else {
      AppLog.error(.app, "Install hotkey event handler error, status:", installStatus)
      eventHandler = nil
      return
    }

    registerHotKey(
      saveReplayHotkey,
      id: saveReplayHotKeyId,
      store: &saveReplayHotKeyRef,
      actionName: "save replay"
    )
    registerHotKey(
      recordToggleHotkey,
      id: recordToggleHotKeyId,
      store: &recordToggleHotKeyRef,
      actionName: "record toggle"
    )

    if saveReplayHotKeyRef == nil, recordToggleHotKeyRef == nil, let eventHandler {
      RemoveEventHandler(eventHandler)
      self.eventHandler = nil
    }
  }

  func unregister() {
    if let saveReplayHotKeyRef {
      UnregisterEventHotKey(saveReplayHotKeyRef)
      self.saveReplayHotKeyRef = nil
    }

    if let recordToggleHotKeyRef {
      UnregisterEventHotKey(recordToggleHotKeyRef)
      self.recordToggleHotKeyRef = nil
    }

    if let eventHandler {
      RemoveEventHandler(eventHandler)
      self.eventHandler = nil
    }
  }

  func updateHotkeys(saveReplay: Hotkey, recordToggle: Hotkey) {
    register(saveReplayHotkey: saveReplay, recordToggleHotkey: recordToggle)
  }

  private func registerHotKey(
    _ hotkey: Hotkey,
    id: UInt32,
    store ref: inout EventHotKeyRef?,
    actionName: String
  ) {
    let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: id)
    let registerStatus = RegisterEventHotKey(
      hotkey.keyCode,
      hotkey.modifiers,
      hotKeyID,
      GetEventDispatcherTarget(),
      0,
      &ref
    )
    guard registerStatus == noErr else {
      AppLog.error(
        .app,
        "Register global hotkey for",
        actionName,
        "status:",
        registerStatus,
        "keyCode:",
        hotkey.keyCode,
        "modifiers:",
        hotkey.modifiers
      )
      ref = nil
      return
    }
  }

  private func handleHotKey(event: EventRef?) {
    guard let event else { return }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
      event,
      EventParamName(kEventParamDirectObject),
      EventParamType(typeEventHotKeyID),
      nil,
      MemoryLayout<EventHotKeyID>.size,
      nil,
      &hotKeyID
    )

    guard status == noErr else { return }
    guard hotKeyID.signature == hotKeySignature else { return }

    switch hotKeyID.id {
    case saveReplayHotKeyId:
      AppState.shared.saveReplay()
    case recordToggleHotKeyId:
      AppState.shared.toggleCapture()
    default:
      return
    }
  }
}
