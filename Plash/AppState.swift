import SwiftUI

@MainActor
final class AppState: ObservableObject {
	static let shared = AppState()

	var cancellables = Set<AnyCancellable>()

	let menu = SSMenu()
	let powerSourceWatcher = PowerSourceWatcher()

	private(set) lazy var statusItem = with(NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)) {
		$0.isVisible = true
		$0.behavior = [.removalAllowed, .terminationOnRemoval]
		$0.menu = menu
		$0.button!.image = .menuBarIcon
		$0.button!.setAccessibilityTitle(SSApp.name)
	}

	private(set) lazy var statusItemButton = statusItem.button!

	/**
	The desktop windows, one for each display Plash shows on.
	*/
	private(set) var instances = [DesktopInstance]()

	/**
	The displays Plash currently shows on.
	*/
	var activeDisplays: [Display] { instances.map(\.display) }

	/**
	The display the mouse pointer is on, which is the display that keyboard shortcuts and menu actions apply to.

	Falls back to the main display.
	*/
	var targetDisplay: Display? {
		let mouseLocation = NSEvent.mouseLocation

		if
			let screen = (NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }),
			let display = Display(screen: screen),
			activeDisplays.contains(display)
		{
			return display
		}

		return activeDisplays.first { $0 == Display.main } ?? activeDisplays.first
	}

	var isBrowsingMode = false {
		didSet {
			guard isEnabled else {
				return
			}

			for instance in instances {
				instance.window.isInteractive = isBrowsingMode
				instance.window.alphaValue = isBrowsingMode ? 1 : Defaults[.opacity]
			}

			resetTimer()
		}
	}

	var isEnabled = true {
		didSet {
			resetTimer()
			statusItemButton.appearsDisabled = !isEnabled

			for instance in instances {
				if isEnabled {
					// The website for the display might have changed while disabled.
					if !instance.update() {
						instance.loadWebsite()
					}

					instance.show()
				} else {
					instance.hide()
				}
			}
		}
	}

	var isScreenLocked = false

	var isManuallyDisabled = false {
		didSet {
			setEnabledStatus()
		}
	}

	var reloadTimer: Timer?

	/**
	The errors of the websites that failed to load, keyed by display.
	*/
	var webViewErrors: [(display: Display, error: Error)] {
		instances.compactMap { instance in
			instance.error.map { (instance.display, $0) }
		}
	}

	private init() {
		DispatchQueue.main.async { [self] in
			didLaunch()
		}
	}

	private func didLaunch() {
		_ = statusItemButton
		migrateLegacyDisplaySetting()
		updateInstances(shouldLoad: false) // The websites are loaded when the enabled state is set in `setUpEvents()`.
		setUpEvents()
		showWelcomeScreenIfNeeded()

		#if DEBUG
//		SSApp.showSettingsWindow()
//		Constants.openWebsitesWindow()
		#endif
	}

	func handleMenuBarIcon() {
		statusItem.isVisible = true

		delay(.seconds(5)) { [self] in
			guard Defaults[.hideMenuBarIcon] else {
				return
			}

			statusItem.isVisible = false
		}
	}

	func handleAppReopen() {
		handleMenuBarIcon()
	}

	func setEnabledStatus() {
		isEnabled = !isManuallyDisabled && !isScreenLocked && !(Defaults[.deactivateOnBattery] && powerSourceWatcher?.powerSource.isUsingBattery == true)
	}

	func resetTimer() {
		reloadTimer?.invalidate()
		reloadTimer = nil

		guard
			isEnabled,
			!isBrowsingMode,
			let reloadInterval = Defaults[.reloadInterval]
		else {
			return
		}

		reloadTimer = Timer.scheduledTimer(withTimeInterval: reloadInterval, repeats: true) { [self] _ in
			Task { @MainActor in
				loadUserURL()
			}
		}
	}

	/**
	Moves the old single display setting to the list of disabled displays.
	*/
	private func migrateLegacyDisplaySetting() {
		guard let legacyDisplay = Defaults[.legacyDisplay] else {
			return
		}

		Defaults[.disabledDisplays] = Display.all
			.filter { $0 != legacyDisplay }
			.map(\.id.uuidString)

		Defaults.reset(.legacyDisplay)
	}

	/**
	Creates and removes desktop windows to match the connected and enabled displays.

	- Parameter shouldLoad: Whether to load the website in newly created windows.
	*/
	func updateInstances(shouldLoad: Bool = true) {
		let disabledDisplays = Set(Defaults[.disabledDisplays])
		let displays = Display.all.filter { !disabledDisplays.contains($0.id.uuidString) }

		for instance in instances where !displays.contains(instance.display) {
			instance.close()
		}

		instances.removeAll { !displays.contains($0.display) }

		for display in displays where !activeDisplays.contains(display) {
			let instance = DesktopInstance(display: display)
			instances.append(instance)
			configure(instance, shouldLoad: shouldLoad)
		}

		updateStatusItemToolTip()
	}

	private func configure(_ instance: DesktopInstance, shouldLoad: Bool) {
		instance.window.collectionBehavior.toggleExistence(.canJoinAllSpaces, shouldExist: Defaults[.showOnAllSpaces])

		guard
			shouldLoad,
			isEnabled
		else {
			return
		}

		instance.window.isInteractive = isBrowsingMode
		instance.window.alphaValue = isBrowsingMode ? 1 : Defaults[.opacity]
		instance.loadWebsite()
		instance.show()
	}

	func updateStatusItemToolTip() {
		if !webViewErrors.isEmpty {
			statusItemButton.toolTip = webViewErrors
				.map { instances.count > 1 ? "\($0.display.localizedName): \($0.error.localizedDescription)" : "Error: \($0.error.localizedDescription)" }
				.joined(separator: "\n")

			// TODO: There's a macOS bug that makes it black instead of a color.
//			statusItemButton.contentTintColor = .systemRed

			return
		}

		statusItemButton.contentTintColor = nil

		guard instances.count > 1 else {
			statusItemButton.toolTip = instances.first?.website?.tooltip
			return
		}

		statusItemButton.toolTip = instances
			.compactMap { instance in
				instance.website.map { "\(instance.display.localizedName): \($0.menuTitle)" }
			}
			.joined(separator: "\n")
	}

	/**
	Recreates the web views whose website changed, and reloads them.
	*/
	func updateWebsites() {
		guard isEnabled else {
			return
		}

		for instance in instances {
			instance.update()
		}
	}

	func recreateWebViewsAndReload() {
		for instance in instances {
			if isEnabled {
				instance.update(force: true)
			} else {
				// It will be loaded when enabled.
				instance.recreateWebView()
			}
		}
	}

	func reloadWebsite() {
		loadUserURL()
	}

	/**
	Reloads the website on all displays.
	*/
	func loadUserURL() {
		for instance in instances {
			instance.loadWebsite()
		}
	}

	func toggleBrowsingMode() {
		Defaults[.isBrowsingMode].toggle()
	}

	func instance(for display: Display) -> DesktopInstance? {
		instances.first { $0.display == display }
	}
}
