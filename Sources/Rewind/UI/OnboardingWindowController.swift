import AppKit
import SwiftUI
import TourKit

@MainActor
final class OnboardingWindowController: NSObject {
	private let shownKey = "ui.onboarding.shown.v2"
	private let userDefaults: UserDefaults
	private let tourController = TourKitWindowController()
	private var onDismiss: (() -> Void)?
	private var isTourPresented = false
	private var windowCloseObserver: NSObjectProtocol?

	var shouldShow: Bool {
		userDefaults.bool(forKey: shownKey) == false
	}

	init(userDefaults: UserDefaults = .standard) {
		self.userDefaults = userDefaults
		super.init()
	}

	func showIfNeeded(onDismiss: (() -> Void)? = nil) {
		guard shouldShow else { return }
		show(onDismiss: onDismiss)
	}

	func show(onDismiss: (() -> Void)? = nil) {
		self.onDismiss = onDismiss
		ensureTourImagesLoaded()

		NSApplication.shared.setActivationPolicy(.regular)
		isTourPresented = true

		let window = tourController.present(
			pages: Self.tourPages,
			continueButtonTitle: "Continue",
			finishButtonTitle: "Get Started",
			onFinish: { [weak self] in
				self?.handleTourDismissed(completed: true)
			},
			onClose: { [weak self] in
				self?.handleTourDismissed(completed: false)
			}
		)
		window.center()
		window.makeKeyAndOrderFront(nil)
		window.orderFrontRegardless()
		NSApplication.shared.activate(ignoringOtherApps: true)

		if let windowCloseObserver {
			NotificationCenter.default.removeObserver(windowCloseObserver)
		}
		windowCloseObserver = NotificationCenter.default.addObserver(
			forName: NSWindow.willCloseNotification,
			object: window,
			queue: .main
		) { [weak self] _ in
			Task { @MainActor in
				self?.handleTourDismissed(completed: false)
			}
		}
	}

	private func handleTourDismissed(completed: Bool) {
		guard isTourPresented else { return }
		isTourPresented = false

		if let windowCloseObserver {
			NotificationCenter.default.removeObserver(windowCloseObserver)
			self.windowCloseObserver = nil
		}

		if completed {
			userDefaults.set(true, forKey: shownKey)
		}

		let hasVisibleTitledWindows = NSApplication.shared.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
		if !hasVisibleTitledWindows {
			NSApplication.shared.setActivationPolicy(.accessory)
		}

		let callback = onDismiss
		onDismiss = nil
		callback?()
	}

	private func ensureTourImagesLoaded() {
		let names = ["tour-welcome", "tour-menubar", "tour-highlights", "tour-settings"]
		let rootURL = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		let devTourURL = rootURL.appendingPathComponent("Resources/Tour")

		for name in names {
			guard NSImage(named: NSImage.Name(name)) == nil else { continue }
			var imageURL = Bundle.main.url(forResource: name, withExtension: "png")
			if imageURL == nil {
				let candidate = devTourURL.appendingPathComponent("\(name).png")
				if FileManager.default.fileExists(atPath: candidate.path) {
					imageURL = candidate
				}
			}
			if let imageURL, let image = NSImage(contentsOf: imageURL) {
				image.setName(NSImage.Name(name))
			}
		}
	}

	static var tourBundle: Bundle {
		if Bundle.main.url(forResource: "tour-welcome", withExtension: "png") != nil {
			return .main
		}
		let rootURL = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		let devTourURL = rootURL.appendingPathComponent("Resources/Tour")
		if let bundle = Bundle(url: devTourURL), bundle.url(forResource: "tour-welcome", withExtension: "png") != nil {
			return bundle
		}
		return .main
	}

	static var tourPages: [TourPage] {
		let bundle = tourBundle
		return [
			TourPage(
				imageName: "tour-welcome",
				imageBundle: bundle,
				title: "Welcome to Rewind",
				description: "Capture your best moments in the background and save instant replays anytime with zero performance impact."
			),
			TourPage(
				imageName: "tour-menubar",
				imageBundle: bundle,
				title: "Always in Your Menu Bar",
				description: "Rewind sits quietly in your menu bar. Click the icon to start recording, save clips, and access quick controls."
			),
			TourPage(
				imageName: "tour-highlights",
				imageBundle: bundle,
				title: "Review & Trim Your Clips",
				description: "Browse highlights, organize favorites, and trim clips right inside the Home window before sharing."
			),
			TourPage(
				imageName: "tour-settings",
				imageBundle: bundle,
				title: "Tailored to Your Setup",
				description: "Fine-tune clip duration, frame rate, synchronized mic and desktop audio, and hotkeys in Settings."
			),
		]
	}
}
