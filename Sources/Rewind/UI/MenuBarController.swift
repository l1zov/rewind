import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
  private let statusItem: NSStatusItem
  private let appState: AppState
  private var cancellables = Set<AnyCancellable>()

  // these need dynamic updates
  private var recordingMenuItem: NSMenuItem?
  private var saveMenuItem: NSMenuItem?
  private var durationMenuItem: NSMenuItem?
  private var resolutionMenuItem: NSMenuItem?
  private var qualityMenuItem: NSMenuItem?
  private var showInFinderMenuItem: NSMenuItem?
  private var permissionMenuItem: NSMenuItem?
  private var permissionSeparatorItem: NSMenuItem?
  private var isMenuOpen = false
  private var needsMenuRefresh = false

  init(appState: AppState) {
    self.appState = appState
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    super.init()

    configureStatusButton()
    configureMenu()
    refreshMenuState()
    observeAppState()
  }

  private func configureStatusButton() {
    guard let button = statusItem.button else { return }

    let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
    let image = NSImage(systemSymbolName: "backward.end.fill", accessibilityDescription: "Rewind")
    button.image = image?.withSymbolConfiguration(config)
    button.imagePosition = .imageOnly
  }

  private func configureMenu() {
    let menu = NSMenu()
    menu.delegate = self
    menu.autoenablesItems = false

    let headerItem = NSMenuItem()
    headerItem.view = createHeaderView()
    menu.addItem(headerItem)

    menu.addItem(.separator())

    let recordItem = NSMenuItem(
      title: appState.isCapturing ? "Stop Recording" : "Start Recording",
      action: #selector(toggleRecording),
      keyEquivalent: appState.startRecordingHotkey.menuKeyEquivalent
    )
    recordItem.keyEquivalentModifierMask = appState.startRecordingHotkey.modifierFlags
    recordItem.target = self
    recordingMenuItem = recordItem
    menu.addItem(recordItem)

    let saveItem = NSMenuItem(
      title: "Save Last \(Int(appState.replayDuration))s",
      action: #selector(saveReplay),
      keyEquivalent: "s"
    )
    saveItem.keyEquivalentModifierMask = [.command, .shift]
    saveItem.target = self
    saveItem.isEnabled = appState.isCapturing
    saveMenuItem = saveItem
    menu.addItem(saveItem)

    menu.addItem(.separator())

    let durationItem = NSMenuItem(title: "Replay Duration", action: nil, keyEquivalent: "")
    durationItem.submenu = createDurationSubmenu()
    durationMenuItem = durationItem
    menu.addItem(durationItem)

    let resolutionItem = NSMenuItem(title: "Resolution", action: nil, keyEquivalent: "")
    resolutionItem.submenu = createResolutionSubmenu()
    resolutionMenuItem = resolutionItem
    menu.addItem(resolutionItem)

    let qualityItem = NSMenuItem(title: "Quality", action: nil, keyEquivalent: "")
    qualityItem.submenu = createQualitySubmenu()
    qualityMenuItem = qualityItem
    menu.addItem(qualityItem)

    let showInFinderItem = NSMenuItem(
      title: "Show in Finder",
      action: #selector(showLastClipInFinder),
      keyEquivalent: ""
    )
    showInFinderItem.target = self
    showInFinderItem.isEnabled = appState.lastClip != nil
    showInFinderMenuItem = showInFinderItem
    menu.addItem(showInFinderItem)

    let permSeparator = NSMenuItem.separator()
    permSeparator.isHidden = true
    permissionSeparatorItem = permSeparator
    menu.addItem(permSeparator)

    let permItem = NSMenuItem(
      title: "⚠ Screen Recording Required",
      action: #selector(openPermissions),
      keyEquivalent: ""
    )
    permItem.target = self
    permItem.isHidden = true
    permissionMenuItem = permItem
    menu.addItem(permItem)

    menu.addItem(.separator())

    let settingsItem = NSMenuItem(
      title: "Settings…",
      action: #selector(openSettings),
      keyEquivalent: ","
    )
    settingsItem.keyEquivalentModifierMask = [.command]
    settingsItem.target = self
    menu.addItem(settingsItem)

    let quitItem = NSMenuItem(
      title: "Quit Rewind",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    menu.addItem(quitItem)

    statusItem.menu = menu
  }

  private func createHeaderView() -> NSView {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 36))

    let iconView = NSImageView(frame: NSRect(x: 14, y: 8, width: 20, height: 20))
    let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
      .applying(.init(paletteColors: [.controlAccentColor]))
    iconView.image = NSImage(systemSymbolName: "backward.end.fill", accessibilityDescription: nil)?
      .withSymbolConfiguration(config)
    iconView.contentTintColor = .controlAccentColor
    view.addSubview(iconView)

    let titleLabel = NSTextField(labelWithString: "Rewind")
    titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    titleLabel.textColor = .labelColor
    titleLabel.frame = NSRect(x: 40, y: 10, width: 100, height: 16)
    view.addSubview(titleLabel)

    return view
  }

  private func createDurationSubmenu() -> NSMenu {
    let submenu = NSMenu()
    let selectedDuration = Int(appState.replayDuration.rounded())
    let durations = AppSettings.replayDurationQuickOptions

    if durations.contains(selectedDuration) == false {
      let customItem = NSMenuItem(
        title: "\(selectedDuration) seconds",
        action: #selector(setDuration(_:)),
        keyEquivalent: ""
      )
      customItem.target = self
      customItem.tag = selectedDuration
      customItem.state = .on
      submenu.addItem(customItem)
      submenu.addItem(.separator())
    }

    for duration in durations {
      let item = NSMenuItem(
        title: "\(duration) seconds",
        action: #selector(setDuration(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.tag = duration
      item.state = Int(appState.replayDuration) == duration ? .on : .off
      submenu.addItem(item)
    }

    return submenu
  }

  private func createResolutionSubmenu() -> NSMenu {
    let submenu = NSMenu()

    if appState.availableResolutions.isEmpty {
      let loadingItem = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
      loadingItem.isEnabled = false
      submenu.addItem(loadingItem)
    } else {
      for resolution in appState.availableResolutions {
        let item = NSMenuItem(
          title: resolution.label,
          action: #selector(setResolution(_:)),
          keyEquivalent: ""
        )
        item.target = self
        item.representedObject = resolution
        item.state = appState.selectedResolution?.id == resolution.id ? .on : .off
        submenu.addItem(item)
      }
    }

    return submenu
  }

  private func createQualitySubmenu() -> NSMenu {
    let submenu = NSMenu()

    for preset in QualityPreset.presets {
      let item = NSMenuItem(
        title: preset.label,
        action: #selector(setQuality(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.representedObject = preset
      item.state = appState.selectedQuality.id == preset.id ? .on : .off
      item.toolTip = preset.description
      submenu.addItem(item)
    }

    return submenu
  }

  private func observeAppState() {
    appState.$isCapturing
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.handleMenuStateChange()
      }
      .store(in: &cancellables)

    appState.$replayDuration
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.handleMenuStateChange()
      }
      .store(in: &cancellables)

    appState.$lastClip
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.handleMenuStateChange()
      }
      .store(in: &cancellables)

    appState.$permissionState
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.handleMenuStateChange()
      }
      .store(in: &cancellables)

    appState.$availableResolutions
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.handleMenuStateChange()
      }
      .store(in: &cancellables)

    appState.$selectedResolution
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.handleMenuStateChange()
      }
      .store(in: &cancellables)

    appState.$selectedQuality
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.handleMenuStateChange()
      }
      .store(in: &cancellables)

    appState.$hotkey
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.handleMenuStateChange()
      }
      .store(in: &cancellables)

    appState.$startRecordingHotkey
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.handleMenuStateChange()
      }
      .store(in: &cancellables)
  }

  private func handleMenuStateChange() {
    if isMenuOpen {
      needsMenuRefresh = true
      return
    }
    refreshMenuState()
  }

  private func refreshMenuState() {
    updateRecordingState(appState.isCapturing)
    updateDuration(appState.replayDuration)
    updateLastClip(appState.lastClip)
    updatePermissionState(appState.permissionState)
    updateResolutionSubmenu()
    updateQualitySubmenu()
    updateHotkey(appState.hotkey)
    updateStartRecordingHotkey(appState.startRecordingHotkey)
  }

  private func updateRecordingState(_ isCapturing: Bool) {
    recordingMenuItem?.title = isCapturing ? "Stop Recording" : "Start Recording"
    saveMenuItem?.isEnabled = isCapturing
    resolutionMenuItem?.isEnabled = !isCapturing
    qualityMenuItem?.isEnabled = !isCapturing

    if let button = statusItem.button {
      let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
      if isCapturing {
        let colorConfig = config.applying(.init(paletteColors: [.systemRed]))
        button.image = NSImage(systemSymbolName: "backward.end.fill", accessibilityDescription: "Rewind - Recording")?
          .withSymbolConfiguration(colorConfig)
      } else {
        button.image = NSImage(systemSymbolName: "backward.end.fill", accessibilityDescription: "Rewind")?
          .withSymbolConfiguration(config)
      }
    }
  }

  private func updateDuration(_ duration: TimeInterval) {
    saveMenuItem?.title = "Save Last \(Int(duration))s"

    if let submenu = durationMenuItem?.submenu {
      for item in submenu.items {
        item.state = item.tag == Int(duration) ? .on : .off
      }
    }
  }

  private func updateLastClip(_ clip: Clip?) {
    showInFinderMenuItem?.isEnabled = clip != nil
  }

  private func updatePermissionState(_ state: PermissionState) {
    let needsPermission = !state.screenRecording
    permissionMenuItem?.isHidden = !needsPermission
    permissionSeparatorItem?.isHidden = !needsPermission
  }

  private func updateResolutionSubmenu() {
    resolutionMenuItem?.submenu = createResolutionSubmenu()
    resolutionMenuItem?.isEnabled = !appState.isCapturing
  }

  private func updateQualitySubmenu() {
    qualityMenuItem?.submenu = createQualitySubmenu()
    qualityMenuItem?.isEnabled = !appState.isCapturing
  }

  private func updateHotkey(_ hotkey: Hotkey) {
    guard let saveMenuItem else { return }
    saveMenuItem.keyEquivalent = hotkey.menuKeyEquivalent
    saveMenuItem.keyEquivalentModifierMask = hotkey.modifierFlags
  }

  private func updateStartRecordingHotkey(_ hotkey: Hotkey) {
    guard let recordingMenuItem else { return }
    recordingMenuItem.keyEquivalent = hotkey.menuKeyEquivalent
    recordingMenuItem.keyEquivalentModifierMask = hotkey.modifierFlags
  }

  // - Actions ---

  @objc private func toggleRecording() {
    appState.toggleCapture()
  }

  @objc private func saveReplay() {
    appState.saveReplay()
  }

  @objc private func setDuration(_ sender: NSMenuItem) {
    appState.replayDuration = TimeInterval(sender.tag)
  }

  @objc private func setResolution(_ sender: NSMenuItem) {
    guard let resolution = sender.representedObject as? CaptureResolution else { return }
    appState.selectedResolution = resolution
  }

  @objc private func setQuality(_ sender: NSMenuItem) {
    guard let quality = sender.representedObject as? QualityPreset else { return }
    appState.selectedQuality = quality
  }

  @objc private func showLastClipInFinder() {
    guard let clip = appState.lastClip else { return }
    NSWorkspace.shared.activateFileViewerSelecting([clip.url])
  }

  @objc private func openPermissions() {
    PermissionManager.openSystemSettings()
  }

  @objc private func openSettings() {
    SettingsWindowController.shared.show()
  }

  // - NSMenuDelegate ---

  nonisolated func menuWillOpen(_ menu: NSMenu) {
    Task { @MainActor in
      isMenuOpen = true
    }
  }

  nonisolated func menuDidClose(_ menu: NSMenu) {
    Task { @MainActor in
      isMenuOpen = false
      if needsMenuRefresh {
        needsMenuRefresh = false
        refreshMenuState()
      }
    }
  }
}
