import Cocoa

extension AppState {
	func setUpURLCommands() {
		SSEvents.appOpenURL
			.sink { [self] in
				handleURLCommands($0)
			}
			.store(in: &cancellables)
	}

	private func handleURLCommands(_ urlComponents: URLComponents) {
		guard urlComponents.scheme == "plash" else {
			return
		}

		let command = urlComponents.path
		let parameters = urlComponents.queryDictionary

		func showMessage(_ message: String) {
			SSApp.forceActivate()
			NSAlert.showModal(title: message)
		}

		// The optional `display` parameter is either the display's position (starting at 1) or its name.
		var display: Display?
		if let displayParameter = parameters["display"]?.trimmed.nilIfEmpty {
			guard let matchingDisplay = self.display(matching: displayParameter) else {
				showMessage("Could not find the display “\(displayParameter)”.")
				return
			}

			display = matchingDisplay
		}

		switch command {
		case "add":
			guard
				let urlString = parameters["url"]?.trimmed,
				let url = URL(string: urlString, encodingInvalidCharacters: false),
				url.isValid
			else {
				showMessage("Invalid URL for the “add” command.")
				return
			}

			WebsitesController.shared.add(url, title: parameters["title"]?.trimmed.nilIfEmpty)
		case "reload":
			if let display {
				instance(for: display)?.loadWebsite()
			} else {
				reloadWebsite()
			}
		case "next":
			WebsitesController.shared.makeNextCurrent(for: display)
		case "previous":
			WebsitesController.shared.makePreviousCurrent(for: display)
		case "random":
			WebsitesController.shared.makeRandomCurrent(for: display)
		case "toggle-browsing-mode":
			toggleBrowsingMode()
		default:
			showMessage("The command “\(command)” is not supported.")
		}
	}

	/**
	Find a connected display by its position (starting at 1) or its name.
	*/
	func display(matching query: String) -> Display? {
		let displays = Display.all

		if let index = Int(query) {
			return displays.indices.contains(index - 1) ? displays[index - 1] : nil
		}

		return displays.first { $0.localizedName.localizedCaseInsensitiveCompare(query) == .orderedSame }
	}
}
