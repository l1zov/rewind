@testable import Rewind
import XCTest

final class ExportAudioMixTests: XCTestCase {
	func testRoleLayoutMatchesTheWritersTrackOrder() {
		XCTAssertEqual(ExportAudioMix.roles(desktop: true, microphone: true), [.desktop, .microphone])
		XCTAssertEqual(ExportAudioMix.roles(desktop: false, microphone: true), [.microphone])
		XCTAssertEqual(ExportAudioMix.roles(desktop: true, microphone: false), [.desktop])
		XCTAssertEqual(ExportAudioMix.roles(desktop: false, microphone: false), [])
	}

	func testVolumePerTrackFollowsItsRole() {
		let mix = ExportAudioMix(roles: [.desktop, .microphone], desktopVolume: 0.25, microphoneVolume: 0.5)
		XCTAssertEqual(mix.volume(forTrack: 0), 0.25)
		XCTAssertEqual(mix.volume(forTrack: 1), 0.5)
		XCTAssertEqual(mix.volume(forTrack: 2), 1, "Unknown tracks stay at unity")
	}

	func testVolumeIsClamped() {
		let mix = ExportAudioMix(roles: [.desktop, .microphone], desktopVolume: 3, microphoneVolume: -1)
		XCTAssertEqual(mix.volume(forTrack: 0), 1)
		XCTAssertEqual(mix.volume(forTrack: 1), 0)
	}

	func testMixdownIsNeededForMultipleTracksOrAChangedLevel() {
		XCTAssertTrue(ExportAudioMix.unity.needsMixdown(trackCount: 2))
		XCTAssertFalse(ExportAudioMix.unity.needsMixdown(trackCount: 1))
		XCTAssertFalse(ExportAudioMix.unity.needsMixdown(trackCount: 0))

		let quieter = ExportAudioMix(roles: [.desktop], desktopVolume: 0.5, microphoneVolume: 1)
		XCTAssertTrue(quieter.needsMixdown(trackCount: 1))
		let micOnly = ExportAudioMix(roles: [.microphone], desktopVolume: 0.1, microphoneVolume: 1)
		XCTAssertFalse(micOnly.needsMixdown(trackCount: 1), "Desktop level is irrelevant when only the mic is recorded")
	}

	func testReconciledFallsBackToUnityWhenTrackCountDoesNotMatchRoles() {
		let mix = ExportAudioMix(roles: [.desktop, .microphone], desktopVolume: 0.2, microphoneVolume: 0.4)
		XCTAssertEqual(mix.reconciled(trackCount: 2), mix)
		// e.g. the desktop track never got created, so the only track is the mic:
		// matching by position would apply the desktop volume to it.
		XCTAssertEqual(mix.reconciled(trackCount: 1), .unity)
		XCTAssertEqual(mix.reconciled(trackCount: 3), .unity)
	}

	func testReconciledKeepsUnityMixAsIs() {
		XCTAssertEqual(ExportAudioMix.unity.reconciled(trackCount: 2), .unity)
	}
}
