import SwiftUI
import KeyboardShortcuts

enum Constants {
	@MainActor
	static var websitesWindow: NSWindow? {
		NSApp.windows.first { $0.identifier?.rawValue == "websites" }
	}

	@MainActor
	static func openWebsitesWindow() {
		SSApp.forceActivate()
		EnvironmentValues().openWindow(id: "websites")
	}
}

extension Defaults.Keys {
	static let websites = Key<[Website]>("websites", default: [])
	static let isBrowsingMode = Key<Bool>("isBrowsingMode", default: false)

	// Settings
	static let hideMenuBarIcon = Key<Bool>("hideMenuBarIcon", default: false)
	static let opacity = Key<Double>("opacity", default: 1)
	static let reloadInterval = Key<Double?>("reloadInterval")
	/**
	Maps a display (`Display.id.uuidString`) to the ID of the website it shows (`Website.id.uuidString`).

	Displays without an entry show the current website (`Website.isCurrent`), which is the website of the main display.
	*/
	static let displayWebsites = Key<[String: String]>("displayWebsites", default: [:])

	/**
	Displays (`Display.id.uuidString`) that Plash should not show on.
	*/
	static let disabledDisplays = Key<[String]>("disabledDisplays", default: [])

	/**
	The single display Plash used to show on before multi-display support. Only kept for migration.
	*/
	static let legacyDisplay = Key<Display?>("display")
	static let deactivateOnBattery = Key<Bool>("deactivateOnBattery", default: false)
	static let showOnAllSpaces = Key<Bool>("showOnAllSpaces", default: false)
	static let bringBrowsingModeToFront = Key<Bool>("bringBrowsingModeToFront", default: false)
	static let openExternalLinksInBrowser = Key<Bool>("openExternalLinksInBrowser", default: false)
	static let muteAudio = Key<Bool>("muteAudio", default: true)

	static let extendPlashBelowMenuBar = Key<Bool>("extendPlashBelowMenuBar", default: false)
}

extension KeyboardShortcuts.Name {
	static let toggleBrowsingMode = Self("toggleBrowsingMode")
	static let toggleEnabled = Self("toggleEnabled")
	static let reload = Self("reload")
	static let nextWebsite = Self("nextWebsite")
	static let previousWebsite = Self("previousWebsite")
	static let randomWebsite = Self("randomWebsite")
}

extension Notification.Name {
	static let showAddWebsiteDialog = Self("showAddWebsiteDialog")
	static let showEditWebsiteDialog = Self("showEditWebsiteDialog")
}
