import Foundation

enum AnalyticsCaptureStartReason: String {
	case manual
	case alwaysRecord = "always_record"
	case appTrigger = "app_trigger"
	case wake
	case retry
}

enum AnalyticsCaptureEndReason: String {
	case manual
	case sleep
	case interrupted
	case restarted
	case appClosed = "app_closed"
}

struct AnalyticsSettingsSnapshot {
	let replayDurationBucket: String
	let resolution: String
	let quality: String
	let frameRate: Int
	let container: String
	let audioCodec: String
	let alwaysRecordEnabled: Bool
	let microphoneEnabled: Bool
	let desktopAudioEnabled: Bool
	let captureTargetPromptEnabled: Bool
	let discordRPCEnabled: Bool
	let gamePresenceEnabled: Bool
	let robloxExperienceEnabled: Bool
	let catboxEnabled: Bool
	let litterboxEnabled: Bool
	let launchAtLoginEnabled: Bool
	let betaUpdatesEnabled: Bool
	let customOutputDirectory: Bool
}

protocol AnalyticsTracking: Sendable {
	func setEnabled(_ enabled: Bool) async
	func appOpened(settings: AnalyticsSettingsSnapshot) async
	func settingsUpdated(_ settings: AnalyticsSettingsSnapshot) async
	func captureSessionStarted(reason: AnalyticsCaptureStartReason, settings: AnalyticsSettingsSnapshot) async
	func captureSessionEnded(reason: AnalyticsCaptureEndReason) async
	func captureStartFailed(reason: AnalyticsCaptureStartReason, category: String, retrying: Bool) async
	func captureInterrupted(category: String, retrying: Bool) async
	func replaySaveRequested(duration: TimeInterval, containerID: String) async
	func replaySaved(duration: TimeInterval, containerID: String, processingMilliseconds: Int) async
	func replaySaveFailed(category: String) async
	func clipAction(action: String, result: String, provider: String?) async
	func lowStorageWarningShown() async
}

struct NoopAnalytics: AnalyticsTracking {
	func setEnabled(_: Bool) async {}
	func appOpened(settings _: AnalyticsSettingsSnapshot) async {}
	func settingsUpdated(_: AnalyticsSettingsSnapshot) async {}
	func captureSessionStarted(reason _: AnalyticsCaptureStartReason, settings _: AnalyticsSettingsSnapshot) async {}
	func captureSessionEnded(reason _: AnalyticsCaptureEndReason) async {}
	func captureStartFailed(reason _: AnalyticsCaptureStartReason, category _: String, retrying _: Bool) async {}
	func captureInterrupted(category _: String, retrying _: Bool) async {}
	func replaySaveRequested(duration _: TimeInterval, containerID _: String) async {}
	func replaySaved(duration _: TimeInterval, containerID _: String, processingMilliseconds _: Int) async {}
	func replaySaveFailed(category _: String) async {}
	func clipAction(action _: String, result _: String, provider _: String?) async {}
	func lowStorageWarningShown() async {}
}

actor PostHogAnalytics: AnalyticsTracking {
	struct Configuration {
		let projectToken: String
		let host: URL

		static func load(
			bundle: Bundle = .main,
			environment: [String: String] = ProcessInfo.processInfo.environment
		) -> Configuration? {
			let token = value(
				environmentKey: "POSTHOG_PROJECT_TOKEN",
				bundleKey: "PostHogProjectToken",
				bundle: bundle,
				environment: environment
			)
			guard let token, !token.isEmpty else { return nil }

			let hostValue = value(
				environmentKey: "POSTHOG_HOST",
				bundleKey: "PostHogHost",
				bundle: bundle,
				environment: environment
			) ?? "https://eu.i.posthog.com"
			guard let host = URL(string: hostValue),
			      host.scheme == "https" || host.scheme == "http"
			else {
				AppLog.error(.app, "PostHog analytics disabled: invalid host")
				return nil
			}

			return Configuration(projectToken: token, host: host)
		}

		private static func value(
			environmentKey: String,
			bundleKey: String,
			bundle: Bundle,
			environment: [String: String]
		) -> String? {
			let rawValue = environment[environmentKey]
				?? bundle.object(forInfoDictionaryKey: bundleKey) as? String
			let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines)
			return value?.isEmpty == false ? value : nil
		}
	}

	private struct Batch: Encodable {
		let apiKey: String
		let batch: [Event]

		private enum CodingKeys: String, CodingKey {
			case apiKey = "api_key"
			case batch
		}
	}

	private struct Event: Encodable {
		let event: String
		let properties: Properties
		let timestamp: String
	}

	private struct Properties: Encodable {
		let distinctID: String
		let processPersonProfile = false
		let disableGeoIP = true
		let values: [String: Value]

		private enum CodingKeys: String, CodingKey {
			case distinctID = "distinct_id"
			case processPersonProfile = "$process_person_profile"
			case disableGeoIP = "$geoip_disable"
		}

		func encode(to encoder: Encoder) throws {
			var container = encoder.container(keyedBy: DynamicCodingKey.self)
			try container.encode(distinctID, forKey: DynamicCodingKey(CodingKeys.distinctID.rawValue))
			try container.encode(processPersonProfile, forKey: DynamicCodingKey(CodingKeys.processPersonProfile.rawValue))
			try container.encode(disableGeoIP, forKey: DynamicCodingKey(CodingKeys.disableGeoIP.rawValue))
			for (key, value) in values {
				try container.encode(value, forKey: DynamicCodingKey(key))
			}
		}
	}

	private enum Value: Encodable {
		case string(String)
		case integer(Int)
		case boolean(Bool)

		func encode(to encoder: Encoder) throws {
			var container = encoder.singleValueContainer()
			switch self {
			case let .string(value):
				try container.encode(value)
			case let .integer(value):
				try container.encode(value)
			case let .boolean(value):
				try container.encode(value)
			}
		}
	}

	private struct DynamicCodingKey: CodingKey {
		let stringValue: String
		let intValue: Int? = nil

		init(_ stringValue: String) {
			self.stringValue = stringValue
		}

		init?(stringValue: String) {
			self.init(stringValue)
		}

		init?(intValue _: Int) {
			return nil
		}
	}

	private static let anonymousIDKey = "analytics.posthog.anonymous-id.v1"
	private static let defaultUsageIntervalNanoseconds: UInt64 = 15 * 60 * 1_000_000_000

	private let configuration: Configuration?
	private let userDefaults: UncheckedSendable<UserDefaults>
	private let usageIntervalNanoseconds: UInt64
	private var enabled: Bool
	private var session: URLSession?
	private var captureSessionID: String?
	private var captureSessionStartedAt: Date?
	private var usageIntervalStartedAt: Date?
	private var usageTask: Task<Void, Never>?
	private var settingsUpdateTask: Task<Void, Never>?

	init(enabled: Bool) {
		let configuration = Configuration.load()
		self.enabled = enabled
		userDefaults = UncheckedSendable(.standard)
		self.configuration = configuration
		usageIntervalNanoseconds = Self.defaultUsageIntervalNanoseconds
		session = enabled && configuration != nil ? Self.makeSession() : nil
		if !enabled {
			userDefaults.value.removeObject(forKey: Self.anonymousIDKey)
		}
	}

	init(
		enabled: Bool,
		userDefaults: UncheckedSendable<UserDefaults>,
		configuration: Configuration?,
		session: URLSession?,
		usageIntervalNanoseconds: UInt64 = PostHogAnalytics.defaultUsageIntervalNanoseconds
	) {
		self.enabled = enabled
		self.userDefaults = userDefaults
		self.configuration = configuration
		self.session = enabled && configuration != nil ? session : nil
		self.usageIntervalNanoseconds = usageIntervalNanoseconds
		if !enabled {
			userDefaults.value.removeObject(forKey: Self.anonymousIDKey)
		}
	}

	func setEnabled(_ enabled: Bool) {
		guard self.enabled != enabled else { return }
		self.enabled = enabled

		if enabled, configuration != nil {
			session = Self.makeSession()
		} else {
			usageTask?.cancel()
			usageTask = nil
			settingsUpdateTask?.cancel()
			settingsUpdateTask = nil
			captureSessionID = nil
			captureSessionStartedAt = nil
			usageIntervalStartedAt = nil
			session?.invalidateAndCancel()
			session = nil
			userDefaults.value.removeObject(forKey: Self.anonymousIDKey)
		}
	}

	func appOpened(settings: AnalyticsSettingsSnapshot) async {
		await capture("app_opened", properties: settingsProperties(settings))
	}

	func settingsUpdated(_ settings: AnalyticsSettingsSnapshot) async {
		settingsUpdateTask?.cancel()
		settingsUpdateTask = Task { [weak self] in
			try? await Task.sleep(nanoseconds: 1_000_000_000)
			if Task.isCancelled { return }
			await self?.captureSettingsUpdated(settings)
		}
	}

	private func captureSettingsUpdated(_ settings: AnalyticsSettingsSnapshot) async {
		await capture("settings_updated", properties: settingsProperties(settings))
	}

	func captureSessionStarted(
		reason: AnalyticsCaptureStartReason,
		settings: AnalyticsSettingsSnapshot
	) async {
		if captureSessionID != nil {
			await captureSessionEnded(reason: .restarted)
		}

		let now = Date()
		let sessionID = UUID().uuidString.lowercased()
		captureSessionID = sessionID
		captureSessionStartedAt = now
		usageIntervalStartedAt = now

		var properties = settingsProperties(settings)
		properties["capture_session_id"] = .string(sessionID)
		properties["reason"] = .string(reason.rawValue)
		await capture("capture_session_started", properties: properties)
		startUsageLoop()
	}

	func captureSessionEnded(reason: AnalyticsCaptureEndReason) async {
		guard let sessionID = captureSessionID else { return }
		usageTask?.cancel()
		usageTask = nil
		await flushUsageInterval(now: Date())

		let duration = captureSessionStartedAt.map { max(0, Int(Date().timeIntervalSince($0).rounded())) } ?? 0
		await capture(
			"capture_session_ended",
			properties: [
				"capture_session_id": .string(sessionID),
				"duration_seconds": .integer(duration),
				"reason": .string(reason.rawValue),
			]
		)
		captureSessionID = nil
		captureSessionStartedAt = nil
		usageIntervalStartedAt = nil
	}

	func captureStartFailed(reason: AnalyticsCaptureStartReason, category: String, retrying: Bool) async {
		await capture(
			"capture_start_failed",
			properties: [
				"reason": .string(reason.rawValue),
				"category": .string(category),
				"retrying": .boolean(retrying),
			]
		)
	}

	func captureInterrupted(category: String, retrying: Bool) async {
		await capture(
			"capture_interrupted",
			properties: [
				"category": .string(category),
				"retrying": .boolean(retrying),
			]
		)
	}

	func replaySaveRequested(duration: TimeInterval, containerID: String) async {
		await capture(
			"replay_save_requested",
			properties: replayProperties(duration: duration, containerID: containerID)
		)
	}

	func replaySaved(duration: TimeInterval, containerID: String, processingMilliseconds: Int) async {
		var properties = replayProperties(duration: duration, containerID: containerID)
		properties["processing_ms"] = .integer(max(0, processingMilliseconds))
		await capture("replay_saved", properties: properties)
	}

	func replaySaveFailed(category: String) async {
		await capture("replay_save_failed", properties: ["category": .string(category)])
	}

	func clipAction(action: String, result: String, provider: String?) async {
		var properties: [String: Value] = [
			"action": .string(action),
			"result": .string(result),
		]
		if let provider {
			properties["provider"] = .string(provider)
		}
		await capture("clip_action", properties: properties)
	}

	func lowStorageWarningShown() async {
		await capture("low_storage_warning_shown")
	}

	private func startUsageLoop() {
		usageTask?.cancel()
		usageTask = Task { [weak self, usageIntervalNanoseconds] in
			while !Task.isCancelled {
				try? await Task.sleep(nanoseconds: usageIntervalNanoseconds)
				if Task.isCancelled { return }
				await self?.flushUsageInterval(now: Date())
			}
		}
	}

	private func flushUsageInterval(now: Date) async {
		guard let sessionID = captureSessionID, let startedAt = usageIntervalStartedAt else { return }
		let activeSeconds = max(0, Int(now.timeIntervalSince(startedAt).rounded()))
		guard activeSeconds > 0 else { return }
		usageIntervalStartedAt = now
		await capture(
			"capture_usage_interval",
			properties: [
				"capture_session_id": .string(sessionID),
				"active_seconds": .integer(activeSeconds),
			]
		)
	}

	private func capture(_ eventName: String, properties: [String: Value] = [:]) async {
		guard enabled, let configuration, let session else { return }

		var values = Self.commonProperties()
		values.merge(properties) { _, eventValue in eventValue }
		let event = Event(
			event: eventName,
			properties: Properties(distinctID: anonymousID(), values: values),
			timestamp: Self.timestamp()
		)

		do {
			let endpoint = configuration.host
				.appendingPathComponent("batch")
				.appendingPathComponent("")
			var request = URLRequest(url: endpoint)
			request.httpMethod = "POST"
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			request.httpBody = try JSONEncoder().encode(
				Batch(apiKey: configuration.projectToken, batch: [event])
			)

			let (_, response) = try await session.data(for: request)
			if let response = response as? HTTPURLResponse,
			   !(200 ..< 300).contains(response.statusCode)
			{
				AppLog.debug(.app, "PostHog event rejected with status", response.statusCode)
			}
		} catch is CancellationError {
			// Opting out cancels in-flight analytics requests.
		} catch {
			AppLog.debug(.app, "PostHog event delivery failed")
		}
	}

	private func anonymousID() -> String {
		if let existing = userDefaults.value.string(forKey: Self.anonymousIDKey) {
			return existing
		}
		let value = UUID().uuidString.lowercased()
		userDefaults.value.set(value, forKey: Self.anonymousIDKey)
		return value
	}

	private static func makeSession() -> URLSession {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.httpCookieStorage = nil
		configuration.httpShouldSetCookies = false
		configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
		configuration.urlCache = nil
		return URLSession(configuration: configuration)
	}

	private static func timestamp() -> String {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return formatter.string(from: Date())
	}

	private static func commonProperties(bundle: Bundle = .main) -> [String: Value] {
		let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
		let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development"
		let os = ProcessInfo.processInfo.operatingSystemVersion
		#if arch(arm64)
			let architecture = "arm64"
		#elseif arch(x86_64)
			let architecture = "x86_64"
		#else
			let architecture = "unknown"
		#endif

		return [
			"analytics_schema_version": .integer(2),
			"app_version": .string(version),
			"app_build": .string(build),
			"macos_version": .string("\(os.majorVersion).\(os.minorVersion)"),
			"architecture": .string(architecture),
		]
	}

	private func settingsProperties(_ settings: AnalyticsSettingsSnapshot) -> [String: Value] {
		[
			"replay_duration_bucket": .string(settings.replayDurationBucket),
			"resolution": .string(settings.resolution),
			"quality": .string(settings.quality),
			"frame_rate": .integer(settings.frameRate),
			"container": .string(settings.container),
			"audio_codec": .string(settings.audioCodec),
			"always_record_enabled": .boolean(settings.alwaysRecordEnabled),
			"microphone_enabled": .boolean(settings.microphoneEnabled),
			"desktop_audio_enabled": .boolean(settings.desktopAudioEnabled),
			"capture_target_prompt_enabled": .boolean(settings.captureTargetPromptEnabled),
			"discord_rpc_enabled": .boolean(settings.discordRPCEnabled),
			"game_presence_enabled": .boolean(settings.gamePresenceEnabled),
			"roblox_experience_enabled": .boolean(settings.robloxExperienceEnabled),
			"catbox_enabled": .boolean(settings.catboxEnabled),
			"litterbox_enabled": .boolean(settings.litterboxEnabled),
			"launch_at_login_enabled": .boolean(settings.launchAtLoginEnabled),
			"beta_updates_enabled": .boolean(settings.betaUpdatesEnabled),
			"custom_output_directory": .boolean(settings.customOutputDirectory),
		]
	}

	private func replayProperties(duration: TimeInterval, containerID: String) -> [String: Value] {
		[
			"duration_bucket": .string(Self.durationBucket(for: duration)),
			"container": .string(containerID),
		]
	}

	static func durationBucket(for duration: TimeInterval) -> String {
		switch duration {
		case ...30:
			return "10-30"
		case ...60:
			return "31-60"
		case ...120:
			return "61-120"
		default:
			return "121-300"
		}
	}
}
