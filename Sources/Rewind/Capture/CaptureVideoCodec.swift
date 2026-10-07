import AVFoundation
import Foundation

struct CaptureVideoCodec: Hashable, Identifiable {
	let id: String
	let label: String
	let description: String
	let avCodec: AVVideoCodecType

	static let h264 = CaptureVideoCodec(
		id: "h264",
		label: "H.264",
		description: "Plays everywhere, including Discord's inline preview. Larger files.",
		avCodec: .h264
	)

	static let hevc = CaptureVideoCodec(
		id: "hevc",
		label: "HEVC (H.265)",
		description: "Smaller files, but many apps (Discord included) can't preview it.",
		avCodec: .hevc
	)

	/// Intel's Quick Sync encoder rejects a second concurrent HEVC session, so
	/// Intel Macs only offer H.264.
	static var options: [CaptureVideoCodec] {
		#if arch(x86_64)
			return [.h264]
		#else
			return [.h264, .hevc]
		#endif
	}

	static let `default` = h264

	static func resolve(id: String) -> CaptureVideoCodec {
		options.first(where: { $0.id == id }) ?? .default
	}

	var isDefault: Bool { id == CaptureVideoCodec.default.id }
}
