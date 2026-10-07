import AppKit
import Carbon

@MainActor
final class GlobalHotkeyManager {
	static let shared = GlobalHotkeyManager()

	let hotKeySignature = OSType(0x5257_4E44) // "RWND"
	private let saveReplayHotKeyId: UInt32 = 1
	private let recordToggleHotKeyId: UInt32 = 2
	private var saveReplayHotKeyRef: EventHotKeyRef?
	private var recordToggleHotKeyRef: EventHotKeyRef?
	private var eventHandler: EventHandlerRef?
	private var saveReplayHotkey: Hotkey = .default
	private var recordToggleHotkey: Hotkey = .startRecordingDefault
	private var onSaveReplay: (() -> Void)?
	private var onRecordToggle: (() -> Void)?

	func configureActions(
		onSaveReplay: (() -> Void)?,
		onRecordToggle: (() -> Void)?
	) {
		self.onSaveReplay = onSaveReplay
		self.onRecordToggle = onRecordToggle
	}

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
				guard let userData, let event else { return noErr }
				// The EventRef is only valid for the duration of this callback, so
				// read the hot key ID now and hand only plain values to the task.
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
				guard status == noErr else { return noErr }
				let signature = hotKeyID.signature
				let id = hotKeyID.id
				let manager = Unmanaged<GlobalHotkeyManager>
					.fromOpaque(userData)
					.takeUnretainedValue()
				Task { @MainActor in
					manager.handleHotKey(signature: signature, id: id)
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

	func handleHotKey(signature: OSType, id: UInt32) {
		guard signature == hotKeySignature else { return }

		switch id {
		case saveReplayHotKeyId:
			onSaveReplay?()
		case recordToggleHotKeyId:
			onRecordToggle?()
		default:
			return
		}
	}
}
