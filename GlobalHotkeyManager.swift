import AppKit
import Carbon

@MainActor
final class GlobalHotkeyManager {
	static let shared = GlobalHotkeyManager()

	private let hotKeySignature = OSType(0x5257_4E44) // "RWND"
	private let saveReplayHotKeyId: UInt32 = 1
	private let startRecordingHotKeyId: UInt32 = 2
	private let stopRecordingHotKeyId: UInt32 = 3
	private var saveReplayHotKeyRef: EventHotKeyRef?
	private var startRecordingHotKeyRef: EventHotKeyRef?
	private var stopRecordingHotKeyRef: EventHotKeyRef?
	private var eventHandler: EventHandlerRef?
	private var saveReplayHotkey: Hotkey = .default
	private var startRecordingHotkey: Hotkey = .startRecordingDefault
	private var stopRecordingHotkey: Hotkey = .stopRecordingDefault
	private var onSaveReplay: (() -> Void)?
	private var onStartRecording: (() -> Void)?
	private var onStopRecording: (() -> Void)?

	func configureActions(
		onSaveReplay: (() -> Void)?,
		onStartRecording: (() -> Void)?,
		onStopRecording: (() -> Void)?
	) {
		self.onSaveReplay = onSaveReplay
		self.onStartRecording = onStartRecording
		self.onStopRecording = onStopRecording
	}

	func register(
		saveReplayHotkey: Hotkey = .default,
		startRecordingHotkey: Hotkey = .startRecordingDefault,
		stopRecordingHotkey: Hotkey = .stopRecordingDefault
	) {
		self.saveReplayHotkey = saveReplayHotkey
		self.startRecordingHotkey = startRecordingHotkey
		self.stopRecordingHotkey = stopRecordingHotkey
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
			startRecordingHotkey,
			id: startRecordingHotKeyId,
			store: &startRecordingHotKeyRef,
			actionName: "start recording"
		)
		registerHotKey(
			stopRecordingHotkey,
			id: stopRecordingHotKeyId,
			store: &stopRecordingHotKeyRef,
			actionName: "stop recording"
		)

		if saveReplayHotKeyRef == nil,
		   startRecordingHotKeyRef == nil,
		   stopRecordingHotKeyRef == nil,
		   let eventHandler
		{
			RemoveEventHandler(eventHandler)
			self.eventHandler = nil
		}
	}

	func unregister() {
		if let saveReplayHotKeyRef {
			UnregisterEventHotKey(saveReplayHotKeyRef)
			self.saveReplayHotKeyRef = nil
		}

		if let startRecordingHotKeyRef {
			UnregisterEventHotKey(startRecordingHotKeyRef)
			self.startRecordingHotKeyRef = nil
		}

		if let stopRecordingHotKeyRef {
			UnregisterEventHotKey(stopRecordingHotKeyRef)
			self.stopRecordingHotKeyRef = nil
		}

		if let eventHandler {
			RemoveEventHandler(eventHandler)
			self.eventHandler = nil
		}
	}

	func updateHotkeys(saveReplay: Hotkey, startRecording: Hotkey, stopRecording: Hotkey) {
		register(
			saveReplayHotkey: saveReplay,
			startRecordingHotkey: startRecording,
			stopRecordingHotkey: stopRecording
		)
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
			onSaveReplay?()
		case startRecordingHotKeyId:
			onStartRecording?()
		case stopRecordingHotKeyId:
			onStopRecording?()
		default:
			return
		}
	}
}
