import Foundation

/// How the audio tracks of a saved clip are combined.
///
/// While recording, the microphone and desktop audio are written as separate
/// tracks. Most players, browsers and chat apps (Discord included) only play the
/// first audio track, so a saved clip folds all tracks into one and applies the
/// user's per-source volume.
struct ExportAudioMix: Equatable {
	enum Role: Equatable {
		case desktop
		case microphone
	}

	/// One entry per audio track in the recorded segments, in track order.
	var roles: [Role]
	var desktopVolume: Double
	var microphoneVolume: Double

	/// Unity gain; any extra tracks are still folded into one.
	static let unity = ExportAudioMix(roles: [], desktopVolume: 1, microphoneVolume: 1)

	/// The track layout `ReplayWriter` produces: desktop audio first (when
	/// enabled), then the microphone (when enabled).
	static func roles(desktop: Bool, microphone: Bool) -> [Role] {
		var roles: [Role] = []
		if desktop { roles.append(.desktop) }
		if microphone { roles.append(.microphone) }
		return roles
	}

	/// Roles are matched to tracks by position, which is only valid when every
	/// recorded track exists. If the counts disagree (a track that never got
	/// created, say) the volumes could land on the wrong source, so fall back to
	/// unity gain rather than guess.
	func reconciled(trackCount: Int) -> ExportAudioMix {
		roles.isEmpty || roles.count == trackCount ? self : .unity
	}

	func volume(forTrack index: Int) -> Float {
		guard roles.indices.contains(index) else { return 1 }
		let volume = roles[index] == .desktop ? desktopVolume : microphoneVolume
		return Float(min(max(volume, 0), 1))
	}

	/// Mixing is needed to fold several tracks into one, or to change the level of a
	/// single one. A lone track at full volume is left untouched (no audio re-encode).
	func needsMixdown(trackCount: Int) -> Bool {
		if trackCount > 1 { return true }
		return trackCount == 1 && volume(forTrack: 0) != 1
	}
}
