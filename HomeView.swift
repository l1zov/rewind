@preconcurrency import AVFoundation
import AVKit
import SwiftUI

struct HomeView: View {
	@ObservedObject var appState: AppState
	@State private var selectedClip: Clip?
	@State private var selectedCategory: String? = "all"

	let columns = [GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 16)]

	var filteredClips: [Clip] {
		switch selectedCategory {
		case "favorites":
			return appState.clipLibrary.clips.filter { $0.isFavorite }
		default:
			return appState.clipLibrary.clips
		}
	}

	var body: some View {
		VStack(spacing: 0) {
			RecordingControlBar(appState: appState)
			Divider()

			NavigationSplitView {
				List(selection: $selectedCategory) {
					NavigationLink(value: "all") {
						Label("All Clips", systemImage: "square.grid.2x2")
					}
					NavigationLink(value: "favorites") {
						Label("Favorites", systemImage: "heart")
					}
				}
				.navigationTitle("Library")
				.frame(minWidth: 150)
			} content: {
				ScrollView {
					if filteredClips.isEmpty {
						Text(selectedCategory == "favorites" ? "No favorites yet." : "No clips yet.")
							.foregroundStyle(.secondary)
							.padding()
					} else {
						LazyVGrid(columns: columns, spacing: 16) {
							ForEach(filteredClips) { clip in
								Button {
									selectedClip = clip
									appState.trackClipAction(action: "open")
								} label: {
									ClipCard(clip: clip, onFavorite: {
										appState.trackClipAction(
											action: "favorite",
											result: clip.isFavorite ? "disabled" : "enabled"
										)
										appState.clipLibrary.toggleFavorite(clip: clip)
									}, onDelete: {
										if selectedClip?.id == clip.id {
											selectedClip = nil
										}
										Task { await appState.clipLibrary.deleteClip(clip) }
										appState.clipWasDeleted(clip)
										appState.trackClipAction(action: "delete", result: "requested")
									})
									.overlay(
										RoundedRectangle(cornerRadius: 8)
											.stroke(selectedClip?.id == clip.id ? Color.accentColor : Color.clear, lineWidth: 3)
									)
								}
								.buttonStyle(.plain)
							}
						}
						.padding()
					}
				}
				.navigationTitle(selectedCategory == "favorites" ? "Favorites" : "All Clips")
				.frame(minWidth: 300)
			} detail: {
				if let clip = selectedClip {
					TrimEditorView(clip: clip, appState: appState)
						.id(clip.id)
				} else {
					Text("Select a clip to view and edit.")
						.foregroundStyle(.secondary)
				}
			}
		}
		.onChange(of: appState.clipToOpen?.id) {
			openRequestedClip()
		}
		.onAppear {
			openRequestedClip()
		}
	}

	private func openRequestedClip() {
		guard let clip = appState.clipToOpen else { return }
		selectedCategory = "all"
		selectedClip = clip
		appState.clipToOpen = nil
	}
}

private struct RecordingControlBar: View {
	@ObservedObject var appState: AppState

	var body: some View {
		HStack(spacing: 12) {
			Picker("Mode", selection: $appState.selectedRecordingMode) {
				ForEach(RecordingMode.options) { mode in
					Text(mode.label).tag(mode)
				}
			}
			.pickerStyle(.segmented)
			.frame(width: 250)
			.disabled(appState.isCapturing || appState.isCaptureTransitioning)

			Button(primaryButtonTitle) {
				appState.toggleCapture()
			}
			.buttonStyle(.borderedProminent)
			.disabled(primaryButtonDisabled)

			if appState.selectedRecordingMode == .instantReplay {
				Button(appState.isSavingReplay ? "Saving Replay…" : "Save Last \(Int(appState.replayDuration).formattedDuration)") {
					appState.saveReplay()
				}
				.disabled(!appState.isCapturing || appState.isCaptureTransitioning || appState.isSavingReplay)
			}

			Spacer()

			if appState.isStoppingCapture || appState.isRestartingCapture {
				ProgressView()
					.controlSize(.small)
			} else if appState.isCapturing {
				Label(
					appState.selectedRecordingMode == .recording ? "Recording" : "Replay Buffer Active",
					systemImage: "record.circle.fill"
				)
				.foregroundStyle(.red)
				.font(.callout.weight(.medium))
			}
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 10)
		.background(.bar)
	}

	private var primaryButtonTitle: String {
		if appState.isStartingCapture { return "Starting…" }
		if appState.isRestartingCapture { return "Applying Settings…" }
		if appState.isStoppingCapture {
			return appState.selectedRecordingMode == .recording ? "Saving…" : "Stopping…"
		}
		if appState.selectedRecordingMode == .recording {
			return appState.isCapturing ? "Stop & Save" : "Start Recording"
		}
		return appState.isCapturing ? "Stop Replay Buffer" : "Start Replay Buffer"
	}

	private var primaryButtonDisabled: Bool {
		appState.isCaptureTransitioning
	}
}

struct ClipCard: View {
	let clip: Clip
	let onFavorite: () -> Void
	let onDelete: () -> Void
	@State private var thumbnail: NSImage?
	@State private var showDeleteConfirmation = false

	var body: some View {
		VStack {
			ZStack(alignment: .bottomTrailing) {
				if let thumbnail = thumbnail {
					Image(nsImage: thumbnail)
						.resizable()
						.aspectRatio(contentMode: .fill)
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.clipped()
				} else {
					Color.black.opacity(0.1)
					Image(systemName: "video")
						.font(.largeTitle)
						.foregroundStyle(.secondary)
				}

				HStack(spacing: 6) {
					Button(action: onFavorite) {
						Image(systemName: clip.isFavorite ? "heart.fill" : "heart")
							.foregroundStyle(clip.isFavorite ? .red : .white)
							.padding(6)
							.background(Color.black.opacity(0.5))
							.clipShape(Circle())
					}
					.buttonStyle(.plain)

					Button {
						showDeleteConfirmation = true
					} label: {
						Image(systemName: "trash")
							.foregroundStyle(.white)
							.padding(6)
							.background(Color.black.opacity(0.5))
							.clipShape(Circle())
					}
					.buttonStyle(.plain)
				}
				.padding(8)
			}
			.aspectRatio(16 / 9, contentMode: .fit)
			.cornerRadius(8)

			Text(clip.createdAt, style: .date)
				.font(.caption)
		}
		.confirmationDialog("Delete this clip?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
			Button("Delete", role: .destructive, action: onDelete)
			Button("Cancel", role: .cancel) {}
		} message: {
			Text("This permanently deletes the clip file from disk.")
		}
		.task(id: clip.id) {
			if thumbnail == nil {
				thumbnail = await ClipThumbnailCache.shared.thumbnail(for: clip)
			}
		}
	}
}

struct TrimEditorView: View {
	let clip: Clip
	@ObservedObject var appState: AppState
	@State private var playerView = AVPlayerView()
	@State private var isUploading = false
	@State private var uploadSuccess = false
	@State private var uploadFailed = false
	@State private var isTrimming = false
	/// Key kept from when Litterbox was the only host with an expiry choice.
	@AppStorage("litterboxExpiration") private var uploadExpiration = "72h"
	@State private var uploadTask: Task<Void, Never>?
	@State private var uploadProgress: Double = 0.0
	@State private var uploadErrorMessage: String?
	@State private var showProgressPopover = false

	var body: some View {
		VStack {
			NativeVideoPlayerWrapper(playerView: playerView)
		}
		.toolbar {
			ToolbarItem {
				Button("Trim") {
					if playerView.canBeginTrimming {
						playerView.beginTrimming { result in
							if result == .okButton {
								Task { @MainActor in
									saveTrimmedClip()
								}
							}
						}
					}
				}
				.disabled(isTrimming)
			}
			ToolbarItem {
				HStack {
					Menu {
						Button("Copy to clipboard") {
							copyClipToPasteboard(clip.url)
						}

						ForEach(appState.enabledUploadProviders) { provider in
							if provider.supportsExpiration {
								Menu("Upload to \(provider.displayName)") {
									Picker("Expiration", selection: $uploadExpiration) {
										ForEach(provider.expirationOptions) { option in
											Text(option.label).tag(option.id)
										}
									}
									Button("Upload") {
										uploadClip(clip.url, provider: provider)
									}
								}
							} else {
								Button("Upload to \(provider.displayName)") {
									uploadClip(clip.url, provider: provider)
								}
							}
						}
					} label: {
						Label("Share", systemImage: "square.and.arrow.up")
					}
					.disabled(isUploading)
					.popover(isPresented: $showProgressPopover, arrowEdge: .bottom) {
						VStack(spacing: 16) {
							if uploadSuccess {
								Image(systemName: "checkmark.circle.fill")
									.resizable()
									.frame(width: 32, height: 32)
									.foregroundStyle(.green)
								Text("Upload Successful!")
									.font(.headline)
								Text("Link copied to clipboard.")
									.font(.subheadline)
									.foregroundStyle(.secondary)
							} else if uploadFailed {
								Image(systemName: "exclamationmark.triangle.fill")
									.resizable()
									.frame(width: 32, height: 32)
									.foregroundStyle(.orange)
								Text("Oops! Upload failed.")
									.font(.headline)
								Text(uploadErrorMessage ?? "The clip couldn't be uploaded.")
									.font(.subheadline)
									.foregroundStyle(.secondary)
									.multilineTextAlignment(.center)
							} else {
								Text("Uploading...")
									.font(.headline)
								ProgressView(value: uploadProgress)
									.progressViewStyle(.linear)
								HStack {
									Text("\(Int(uploadProgress * 100))%")
										.font(.caption)
										.foregroundStyle(.secondary)
									Spacer()
									Button("Cancel") {
										uploadTask?.cancel()
									}
								}
							}
						}
						.padding()
						.frame(width: 250)
					}
				}
			}
		}
		.onAppear {
			playerView.player = AVPlayer(url: clip.url)
			playerView.showsSharingServiceButton = true
			playerView.showsFullScreenToggleButton = true
		}
	}

	private func saveTrimmedClip() {
		guard let currentItem = playerView.player?.currentItem else { return }
		let asset = currentItem.asset

		var start = currentItem.reversePlaybackEndTime
		var end = currentItem.forwardPlaybackEndTime

		isTrimming = true
		Task {
			if !start.isValid { start = .zero }
			if !end.isValid {
				end = (try? await asset.load(.duration)) ?? .zero
			}

			let timeRange = CMTimeRange(start: start, end: end)

			guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
				isTrimming = false
				return
			}

			let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(clip.url.pathExtension)

			exportSession.outputURL = tempURL
			exportSession.outputFileType = clip.url.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
			exportSession.timeRange = timeRange

			await exportSession.export()
			if exportSession.status == .completed {
				do {
					try? FileManager.default.removeItem(at: clip.url)
					try FileManager.default.moveItem(at: tempURL, to: clip.url)
					// The clip was rewritten in place, so its cached first frame
					// is no longer the frame it starts on.
					ClipThumbnailCache.shared.invalidate(clipID: clip.id)
					appState.trackClipAction(action: "trim")
				} catch {
					print("Error saving trimmed clip: \(error)")
					appState.trackClipAction(action: "trim", result: "failed")
				}
			} else {
				appState.trackClipAction(action: "trim", result: "failed")
			}
			isTrimming = false
		}
	}

	private func copyClipToPasteboard(_ url: URL) {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.writeObjects([url as NSURL])
		appState.trackClipAction(action: "copy")
	}

	private func showUploadFailure(_ error: Error, provider: ClipUploadProvider) {
		isUploading = false
		uploadSuccess = false
		uploadErrorMessage = (error as? LocalizedError)?.errorDescription
		uploadFailed = true
		appState.trackClipAction(action: "upload", result: "failed", provider: provider.id)
		Task {
			try? await Task.sleep(nanoseconds: 5_000_000_000)
			uploadFailed = false
			uploadErrorMessage = nil
			showProgressPopover = false
		}
	}

	private func uploadClip(_ url: URL, provider: ClipUploadProvider) {
		isUploading = true
		uploadSuccess = false
		uploadFailed = false
		uploadErrorMessage = nil
		showProgressPopover = true
		uploadProgress = 0.0
		appState.trackClipAction(action: "upload", result: "started", provider: provider.id)

		uploadTask = Task { @MainActor in
			do {
				let credentials: StreamableCredentials?
				switch provider.authentication {
				case .none:
					credentials = nil
				case .streamableBasic:
					guard let storedCredentials = try await StreamableCredentialStore.shared.load() else {
						throw ClipUploadError.credentialsRequired
					}
					credentials = storedCredentials
				}
				let link = try await ClipUploader.shared.upload(
					clipAt: url,
					provider: provider,
					credentials: credentials,
					expirationID: provider.supportsExpiration ? uploadExpiration : nil
				) { fraction in
					Task { @MainActor in uploadProgress = fraction }
				}

				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(link.absoluteString, forType: .string)
				uploadSuccess = true
				appState.trackClipAction(action: "upload", provider: provider.id)
				try? await Task.sleep(nanoseconds: 2_500_000_000)
				uploadSuccess = false
				isUploading = false
				showProgressPopover = false
			} catch is CancellationError {
				isUploading = false
				showProgressPopover = false
				appState.trackClipAction(action: "upload", result: "cancelled", provider: provider.id)
			} catch {
				AppLog.error(.library, "Upload to \(provider.id) failed:", error)
				showUploadFailure(error, provider: provider)
			}
		}
	}
}

struct NativeVideoPlayerWrapper: NSViewRepresentable {
	let playerView: AVPlayerView

	func makeNSView(context _: Context) -> AVPlayerView {
		playerView
	}

	func updateNSView(_: AVPlayerView, context _: Context) {}
}
