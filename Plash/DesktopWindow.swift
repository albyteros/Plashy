import Cocoa

final class DesktopWindow: NSWindow {
	override var canBecomeMain: Bool { isInteractive }
	override var canBecomeKey: Bool { isInteractive }
	override var acceptsFirstResponder: Bool { isInteractive }

	private var cancellables = Set<AnyCancellable>()

	var targetDisplay: Display? {
		didSet {
			setFrame()
		}
	}

	var isInteractive = false {
		didSet {
			if isInteractive {
				level = Defaults[.bringBrowsingModeToFront] ? .floating : (.desktopIcon + 1) // The `+ 1` fixes a weird issue where the window is sometimes not interactive. (macOS 11.2.1)
				makeKeyAndOrderFront(self)
				ignoresMouseEvents = false
			} else {
				level = .desktop
				orderBack(self)

				// Even though the window is on `.desktop` level, the user would be able to interact if they hide desktop icons.
				ignoresMouseEvents = true
			}
		}
	}

	convenience init(display: Display?) {
		self.init(
			contentRect: .zero,
			styleMask: [
				.borderless
			],
			backing: .buffered,
			defer: false
		)

		self.targetDisplay = display

		self.isOpaque = false
		self.backgroundColor = .clear
		self.level = .desktop
		self.isRestorable = false
		self.canHide = false
		self.displaysWhenScreenProfileChanges = true
		self.collectionBehavior = [
			.stationary,
			.ignoresCycle,
			.fullScreenNone // This ensures that if Plash is launched while an app is fullscreen (fullscreen is a separate space), it will not show behind that app and instead show in the primary space.
		]

		disableSnapshotRestoration()
		setFrame()

		NSScreen.publisher
			.sink { [weak self] in
				self?.setFrame()
			}
			.store(in: &cancellables)

		Defaults.publisher(.extendPlashBelowMenuBar)
			.sink { [weak self] _ in
				self?.setFrame()
			}
			.store(in: &cancellables)
	}

	private func setFrame() {
		// Ensure the screen still exists.
		guard let screen = targetDisplay?.screen ?? .main else {
			return
		}

		var frame = screen.frameWithoutStatusBar
		frame.size.height += 1 // Probably not needed, but just to ensure it covers all the way up to the menu bar on older Macs (I can only test on M1 Mac)

		if Defaults[.extendPlashBelowMenuBar] {
			frame = screen.frame
		}

		setFrame(frame, display: true)
	}
}

/**
The desktop window and web view for a single display.
*/
@MainActor
final class DesktopInstance {
	private var cancellables = Set<AnyCancellable>()

	let display: Display
	let window: DesktopWindow
	private(set) var webViewController: WebViewController

	var webView: SSWebView { webViewController.webView }

	/**
	The website currently shown.
	*/
	private(set) var website: Website?

	var error: Error? {
		didSet {
			AppState.shared.updateStatusItemToolTip()

			guard let error else {
				return
			}

			// TODO: Also present the error when the user just added it from the input box as then it's also "interactive".
			if
				AppState.shared.isBrowsingMode,
				!error.localizedDescription.contains("No internet connection")
			{
				error.presentAsModal()
			}
		}
	}

	init(display: Display) {
		let website = WebsitesController.shared.current(for: display)
		self.display = display
		self.website = website
		self.webViewController = WebViewController(website: website)
		self.window = DesktopWindow(display: display)
		window.isReleasedWhenClosed = false // We manage the lifetime ourselves.
		window.contentView = webViewController.webView
		window.contentView?.isHidden = true
		setUpWebViewEvents()
	}

	private func setUpWebViewEvents() {
		cancellables.removeAll()

		webViewController.didLoadPublisher
			.convertToResult()
			.sink { [weak self] result in
				guard let self else {
					return
				}

				switch result {
				case .success:
					// Set the persisted zoom level.
					// This must be here as `webView.url` needs to have been set.
					let zoomLevel = webView.zoomLevelWrapper
					if zoomLevel != 1 {
						webView.zoomLevelWrapper = zoomLevel
					}

					AppState.shared.updateStatusItemToolTip()
				case .failure(let error):
					self.error = error
				}
			}
			.store(in: &cancellables)
	}

	/**
	Recreate the web view if the website for the display changed, and reload it.

	- Parameter force: Recreate and reload even if the website did not change.
	- Returns: Whether the website was reloaded.
	*/
	@discardableResult
	func update(force: Bool = false) -> Bool {
		let newWebsite = WebsitesController.shared.current(for: display)

		guard force || newWebsite != website else {
			return false
		}

		website = newWebsite
		recreateWebView()
		loadWebsite()

		return true
	}

	func recreateWebView() {
		// The web view controller publishes a completion when loading fails, so we need a new one to keep receiving events.
		webViewController = WebViewController(website: website)
		window.contentView = webViewController.webView
		setUpWebViewEvents()
	}

	func loadWebsite() {
		loadURL(website?.url)
	}

	func loadURL(_ url: URL?) {
		error = nil

		guard
			var url,
			url.isValid
		else {
			return
		}

		do {
			url = try replacePlaceholders(of: url) ?? url
		} catch {
			error.presentAsModal()
			return
		}

		webViewController.loadURL(url)

		// TODO: Add a callback to `loadURL` when it's done loading instead.
		// TODO: Fade in the web view.
		delay(.seconds(1)) { [weak self] in
			self?.window.contentView?.isHidden = false
		}
	}

	func show() {
		window.makeKeyAndOrderFront(self)
	}

	func hide() {
		// TODO: Properly unload the web view instead of just clearing and hiding it.
		window.orderOut(self)
		loadURL("about:blank")
	}

	func close() {
		window.orderOut(self)
		webViewController.loadURL("about:blank")
		window.close()
	}

	/**
	Replaces app-specific placeholder strings in the given URL with a corresponding value.
	*/
	func replacePlaceholders(of url: URL) throws -> URL? {
		// Here we swap out `[[screenWidth]]` and `[[screenHeight]]` for their actual values.
		// We proceed only if we have an `NSScreen` to work with.
		guard let screen = display.screen ?? .main else {
			return nil
		}

		return try url
			.replacingPlaceholder("[[screenWidth]]", with: String(format: "%.0f", screen.frameWithoutStatusBar.width))
			.replacingPlaceholder("[[screenHeight]]", with: String(format: "%.0f", screen.frameWithoutStatusBar.height))
	}
}
