import Foundation

struct RecordingMode: Hashable, Identifiable {
	let id: String
	let label: String
	let description: String

	static let instantReplay = RecordingMode(
		id: "instant-replay",
		label: "Instant Replay",
		description: "Continuously capture so you can save what just happened"
	)

	static let recording = RecordingMode(
		id: "recording",
		label: "Recording",
		description: "Start and stop a recording manually"
	)

	static let options: [RecordingMode] = [.instantReplay, .recording]
	static let `default` = instantReplay

	var isDefault: Bool { id == RecordingMode.default.id }
}
