import Cocoa

extension AppState {
	private func addInfoMenuItem() {
		let maxLength = 30

		guard instances.count > 1 else {
			guard
				let website = instances.first?.website,
				!website.menuTitle.isEmpty
			else {
				return
			}

			let menuItem = menu.addDisabled(website.menuTitle.truncating(to: maxLength))
			menuItem.toolTip = website.tooltip

			return
		}

		for instance in instances {
			guard let website = instance.website else {
				continue
			}

			let menuItem = menu.addDisabled("\(instance.display.localizedName.truncating(to: 20)): \(website.menuTitle.truncating(to: maxLength))")
			menuItem.toolTip = website.tooltip
		}
	}

	private func createSwitchMenu() -> SSMenu {
		let menu = SSMenu()

		guard instances.count > 1 else {
			let display = instances.first?.display

			for website in WebsitesController.shared.all {
				let menuItem = menu.addCallbackItem(
					website.menuTitle.truncating(to: 40),
					isChecked: display.map { WebsitesController.shared.current(for: $0)?.id == website.id } ?? website.isCurrent
				) {
					if let display {
						WebsitesController.shared.setCurrent(website, for: display)
					} else {
						website.makeCurrent()
					}
				}

				menuItem.toolTip = website.tooltip
			}

			return menu
		}

		for instance in instances {
			let display = instance.display
			menu.addItem(.sectionHeader(title: display.localizedName))

			for website in WebsitesController.shared.all {
				let menuItem = menu.addCallbackItem(
					website.menuTitle.truncating(to: 40),
					isChecked: instance.website?.id == website.id
				) {
					WebsitesController.shared.setCurrent(website, for: display)
				}

				menuItem.toolTip = website.tooltip
			}

			menu.addSeparator()
		}

		menu.addItem("All Displays")
			.withSubmenu { submenu in
				for website in WebsitesController.shared.all {
					let menuItem = submenu.addCallbackItem(website.menuTitle.truncating(to: 40)) {
						WebsitesController.shared.showOnAllDisplays(website)
					}

					menuItem.toolTip = website.tooltip
				}

				return submenu
			}

		return menu
	}

	private func createMoreMenu() -> SSMenu {
		let menu = SSMenu()

		menu.addAboutItem()

		menu.addSeparator()

		menu.addCallbackItem("Send Feedback…") {
			SSApp.openSendFeedbackPage()
		}

		menu.addSeparator()

		menu.addLinkItem("Examples", destination: "https://github.com/sindresorhus/Plash/discussions/136")

		menu.addLinkItem("Tips", destination: "https://github.com/sindresorhus/Plash#tips")

		menu.addLinkItem("FAQ", destination: "https://github.com/sindresorhus/Plash#faq")

		menu.addLinkItem("Scripting", destination: "https://github.com/sindresorhus/Plash#scripting")

		menu.addLinkItem("Website", destination: "https://sindresorhus.com/plash")

		menu.addSeparator()

		menu.addLinkItem("Rate App", destination: "macappstore://apps.apple.com/app/id1494023538?action=write-review")

		menu.addMoreAppsItem()

		return menu
	}

	private func addWebsiteItems() {
		let webViewErrors = webViewErrors
		if !webViewErrors.isEmpty {
			for (display, error) in webViewErrors {
				let prefix = instances.count > 1 ? "\(display.localizedName): " : ""
				menu.addDisabled("\(prefix)Error: \(error.localizedDescription)".wordWrapped(atLength: 36).toNSAttributedString)
			}

			menu.addSeparator()
		}

		addInfoMenuItem()

		menu.addSeparator()

		if !WebsitesController.shared.all.isEmpty {
			menu.addCallbackItem(
				"Reload",
				isEnabled: WebsitesController.shared.current != nil
			) { [weak self] in
				self?.loadUserURL()
			}
			.setShortcut(for: .reload)

			menu.addCallbackItem(
				"Browsing Mode",
				isEnabled: WebsitesController.shared.current != nil,
				isChecked: Defaults[.isBrowsingMode]
			) {
				Defaults[.isBrowsingMode].toggle()

				SSApp.runOnce(identifier: "activatedBrowsingMode") {
					DispatchQueue.main.async {
						NSAlert.showModal(
							title: "Browsing Mode lets you temporarily interact with the website. For example, to log into an account or scroll to a specific position on the website.",
							message: "If you don't currently see the website, you might need to hide some windows to reveal the desktop."
						)
					}
				}
			}
			.setShortcut(for: .toggleBrowsingMode)

			menu.addCallbackItem(
				"Edit…",
				isEnabled: WebsitesController.shared.current != nil
			) { [self] in
				let website = targetDisplay.flatMap { WebsitesController.shared.current(for: $0) } ?? WebsitesController.shared.current

				Constants.openWebsitesWindow()

				// TODO: Find a better way to do this.
				NotificationCenter.default.post(name: .showEditWebsiteDialog, object: website?.id)
			}
		}

		menu.addSeparator()

		if WebsitesController.shared.all.count > 1 {
			// With multiple displays, these apply to the display with the mouse pointer, which is where the menu was opened.
			menu.addCallbackItem("Next") { [self] in
				WebsitesController.shared.makeNextCurrent(for: targetDisplay)
			}
			.setShortcut(for: .nextWebsite)

			menu.addCallbackItem("Previous") { [self] in
				WebsitesController.shared.makePreviousCurrent(for: targetDisplay)
			}
			.setShortcut(for: .previousWebsite)

			menu.addCallbackItem("Random") { [self] in
				WebsitesController.shared.makeRandomCurrent(for: targetDisplay)
			}
			.setShortcut(for: .randomWebsite)

			menu.addItem("Switch")
				.withSubmenu(createSwitchMenu())

			menu.addSeparator()
		}

		menu.addCallbackItem("Add Website…") {
			Constants.openWebsitesWindow()

			// TODO: Find a better way to do this.
			NotificationCenter.default.post(name: .showAddWebsiteDialog, object: nil)
		}

		menu.addCallbackItem("Websites…") {
			Constants.openWebsitesWindow()
		}
	}

	func updateMenu() {
		menu.removeAllItems()

		if (isEnabled || isManuallyDisabled) || (!Defaults[.deactivateOnBattery] && powerSourceWatcher?.powerSource.isUsingBattery == false) {
			menu.addCallbackItem(
				isManuallyDisabled ? "Enable" : "Disable"
			) { [self] in
				isManuallyDisabled.toggle()
			}
		}

		menu.addSeparator()

		if isEnabled {
			addWebsiteItems()
		} else if !isManuallyDisabled {
			menu.addDisabled("Deactivated While on Battery")
		}

		menu.addSeparator()

		menu.addSettingsItem()

		menu.addItem("More")
			.withSubmenu(createMoreMenu())

		menu.addSeparator()

		menu.addQuitItem()
	}
}
