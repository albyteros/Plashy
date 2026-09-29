import Cocoa
import KeyboardShortcuts

extension AppState {
	func setUpEvents() {
		menu.onUpdate = { [self] in
			updateMenu()
		}

		powerSourceWatcher?.didChangePublisher
			.sink { [self] _ in
				guard Defaults[.deactivateOnBattery] else {
					return
				}

				setEnabledStatus()
			}
			.store(in: &cancellables)

		SSEvents.deviceDidWake
			.sink { [self] in
				loadUserURL()
			}
			.store(in: &cancellables)

		SSEvents.isScreenLocked
			.sink { [self] in
				isScreenLocked = $0
				setEnabledStatus()
			}
			.store(in: &cancellables)

		Defaults.publisher(.websites, options: [])
			.receive(on: DispatchQueue.main)
			.sink { [self] in
				resetTimer()
				updateWebsites()

				// We never destroy the webview, so we have to make sure it's not in browsing mode when there are no websites.
				if $0.newValue.isEmpty {
					Defaults[.isBrowsingMode] = false
				}
			}
			.store(in: &cancellables)

		Defaults.publisher(.isBrowsingMode)
			.receive(on: DispatchQueue.main)
			.sink { [self] change in
				isBrowsingMode = change.newValue
			}
			.store(in: &cancellables)

		Defaults.publisher(.hideMenuBarIcon)
			.sink { [self] _ in
				handleMenuBarIcon()
			}
			.store(in: &cancellables)

		Defaults.publisher(.displayWebsites, options: [])
			.receive(on: DispatchQueue.main)
			.sink { [self] _ in
				updateWebsites()
			}
			.store(in: &cancellables)

		Defaults.publisher(.disabledDisplays, options: [])
			.sink { [self] _ in
				updateInstances()
			}
			.store(in: &cancellables)

		NSScreen.publisher
			.sink { [self] in
				updateInstances()
			}
			.store(in: &cancellables)

		Defaults.publisher(.opacity)
			.sink { [self] change in
				for instance in instances {
					instance.window.alphaValue = isBrowsingMode ? 1 : change.newValue
				}
			}
			.store(in: &cancellables)

		Defaults.publisher(.reloadInterval)
			.sink { [self] _ in
				resetTimer()
			}
			.store(in: &cancellables)

		Defaults.publisher(.deactivateOnBattery)
			.sink { [self] _ in
				setEnabledStatus()
			}
			.store(in: &cancellables)

		Defaults.publisher(.showOnAllSpaces)
			.sink { [self] change in
				for instance in instances {
					instance.window.collectionBehavior.toggleExistence(.canJoinAllSpaces, shouldExist: change.newValue)
				}
			}
			.store(in: &cancellables)

		Defaults.publisher(.bringBrowsingModeToFront, options: [])
			.sink { [self] _ in
				for instance in instances {
					instance.window.isInteractive = instance.window.isInteractive
				}
			}
			.store(in: &cancellables)

		Defaults.publisher(.muteAudio, options: [])
			.receive(on: DispatchQueue.main)
			.sink { [self] _ in
				recreateWebViewsAndReload()
			}
			.store(in: &cancellables)

		KeyboardShortcuts.onKeyUp(for: .toggleBrowsingMode) {
			Defaults[.isBrowsingMode].toggle()
		}

		KeyboardShortcuts.onKeyUp(for: .toggleEnabled) { [self] in
			isManuallyDisabled.toggle()
		}

		KeyboardShortcuts.onKeyUp(for: .reload) { [self] in
			reloadWebsite()
		}

		// These apply to the display with the mouse pointer.
		KeyboardShortcuts.onKeyUp(for: .nextWebsite) { [self] in
			WebsitesController.shared.makeNextCurrent(for: targetDisplay)
		}

		KeyboardShortcuts.onKeyUp(for: .previousWebsite) { [self] in
			WebsitesController.shared.makePreviousCurrent(for: targetDisplay)
		}

		KeyboardShortcuts.onKeyUp(for: .randomWebsite) { [self] in
			WebsitesController.shared.makeRandomCurrent(for: targetDisplay)
		}
	}
}
