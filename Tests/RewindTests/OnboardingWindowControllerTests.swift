@testable import Rewind
import XCTest

@MainActor
final class OnboardingWindowControllerTests: XCTestCase {
	func testShouldShowDefaultsToTrueWhenUnset() {
		let suiteName = "OnboardingWindowControllerTests.\(UUID().uuidString)"
		let userDefaults = UserDefaults(suiteName: suiteName)!
		defer { userDefaults.removePersistentDomain(forName: suiteName) }

		let controller = OnboardingWindowController(userDefaults: userDefaults)
		XCTAssertTrue(controller.shouldShow)
	}

	func testShouldShowReturnsFalseWhenShownKeySet() {
		let suiteName = "OnboardingWindowControllerTests.\(UUID().uuidString)"
		let userDefaults = UserDefaults(suiteName: suiteName)!
		defer { userDefaults.removePersistentDomain(forName: suiteName) }

		userDefaults.set(true, forKey: "ui.onboarding.shown.v2")
		let controller = OnboardingWindowController(userDefaults: userDefaults)
		XCTAssertFalse(controller.shouldShow)
	}

	func testTourPagesConfiguredCorrectly() {
		let pages = OnboardingWindowController.tourPages
		XCTAssertEqual(pages.count, 4)
		XCTAssertEqual(pages[0].imageName, "tour-welcome")
		XCTAssertEqual(pages[1].imageName, "tour-menubar")
		XCTAssertEqual(pages[2].imageName, "tour-highlights")
		XCTAssertEqual(pages[3].imageName, "tour-settings")

		for page in pages {
			let resURL = page.imageBundle?.url(forResource: page.imageName, withExtension: "png")
			XCTAssertNotNil(resURL, "Could not find image for \(page.imageName) in imageBundle")
		}
	}

	func testShowPresentsWindow() {
		let suiteName = "OnboardingWindowControllerTests.\(UUID().uuidString)"
		let userDefaults = UserDefaults(suiteName: suiteName)!
		defer { userDefaults.removePersistentDomain(forName: suiteName) }

		let controller = OnboardingWindowController(userDefaults: userDefaults)
		controller.show()
		let tourWindow = NSApp.windows.first { $0.className.contains("HostWindow") }
		XCTAssertNotNil(tourWindow)
		XCTAssertGreaterThan(tourWindow?.frame.width ?? 0, 500)
		XCTAssertGreaterThan(tourWindow?.frame.height ?? 0, 500)
		tourWindow?.close()
	}

	func testClosingWindowEarlyDoesNotMarkOnboardingAsCompleted() {
		let suiteName = "OnboardingWindowControllerTests.\(UUID().uuidString)"
		let userDefaults = UserDefaults(suiteName: suiteName)!
		defer { userDefaults.removePersistentDomain(forName: suiteName) }

		let controller = OnboardingWindowController(userDefaults: userDefaults)
		controller.show()
		let tourWindow = NSApp.windows.first { $0.className.contains("HostWindow") }
		tourWindow?.close()

		XCTAssertTrue(controller.shouldShow)
	}
}
