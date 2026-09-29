import SwiftUI
import LinkPresentation

@MainActor
final class WebsitesController {
	static let shared = WebsitesController()

	private var cancellables = Set<AnyCancellable>()
	private var _current: Website? { all.first(where: \.isCurrent) }
	private var nextCurrent: Website? { all.elementAfterOrFirst(_current) }
	private var previousCurrent: Website? { all.elementBeforeOrLast(_current) }

	var randomWebsiteIterator = Defaults[.websites].infiniteUniformRandomSequence().makeIterator()

	@MainActor let thumbnailCache = SimpleImageCache<String>(diskCacheName: "websiteThumbnailCache")

	/**
	The current website.
	*/
	var current: Website? {
		get { _current ?? all.first }
		set {
			guard let newValue else {
				all = all.modifying {
					$0.isCurrent = false
				}

				return
			}

			makeCurrent(newValue)
		}
	}

	/**
	All websites.
	*/
	var all: [Website] {
		get { Defaults[.websites] }
		set {
			Defaults[.websites] = newValue
		}
	}

	let allBinding = Defaults.bindingCollection(for: .websites)

	private init() {
		setUpEvents()
		thumbnailCache.prewarmCacheFromDisk(for: all.map(\.thumbnailCacheKey))
	}

	private func setUpEvents() {
		Defaults.publisher(.websites)
			.sink { [weak self] change in
				guard let self else {
					return
				}

				// Ensures there's always a current website.
				if
					change.newValue.allSatisfy(!\.isCurrent),
					let website = change.newValue.first
				{
					website.makeCurrent()
				}

				// We only reset the iterator if a website was added/removed.
				if change.newValue.map(\.id) != change.oldValue.map(\.id) {
					randomWebsiteIterator = all.infiniteUniformRandomSequence().makeIterator()

					// Remove display assignments to websites that no longer exist.
					let ids = Set(change.newValue.map(\.id.uuidString))
					let displayWebsites = Defaults[.displayWebsites].filter { ids.contains($0.value) }
					if displayWebsites != Defaults[.displayWebsites] {
						Defaults[.displayWebsites] = displayWebsites
					}
				}
			}
			.store(in: &cancellables)
	}

	/**
	Make a website the current one.
	*/
	private func makeCurrent(_ website: Website) {
		all = all.modifying {
			$0.isCurrent = $0.id == website.id
		}
	}

	/**
	The website shown on the given display.

	Displays without an explicit website show the current website, which is the website of the main display.
	*/
	func current(for display: Display) -> Website? {
		if
			let id = Defaults[.displayWebsites][display.id.uuidString].flatMap(UUID.init(uuidString:)),
			let website = all[id: id]
		{
			return website
		}

		return current
	}

	/**
	Show the given website on the given display.

	If the display is the main display, it becomes the current website, which is also shown on displays without an explicit website.
	*/
	func setCurrent(_ website: Website, for display: Display) {
		guard display != Display.main else {
			Defaults[.displayWebsites][display.id.uuidString] = nil
			makeCurrent(website)
			return
		}

		Defaults[.displayWebsites][display.id.uuidString] = website.id.uuidString
	}

	/**
	Show the given website on all displays.
	*/
	func showOnAllDisplays(_ website: Website) {
		Defaults[.displayWebsites] = [:]
		makeCurrent(website)
	}

	/**
	The displays currently showing the given website.
	*/
	func displays(showing website: Website) -> [Display] {
		AppState.shared.activeDisplays.filter { current(for: $0)?.id == website.id }
	}

	/**
	Add a website.
	*/
	@discardableResult
	func add(_ website: Website) -> Binding<Website> {
		// The order here is important.
		all.append(website)
		current = website

		return allBinding[id: website.id]!
	}

	/**
	Add a website from a URL.

	Optionally, specify a title. If no title is given or if the title is empty, a title will be automatically fetched from the website.
	*/
	@discardableResult
	func add(_ websiteURL: URL, title: String? = nil) -> Binding<Website> {
		let websiteBinding = add(
			Website(
				id: UUID(),
				isCurrent: true,
				url: websiteURL,
				usePrintStyles: false
			)
		)

		if let title = title?.nilIfEmptyOrWhitespace {
			websiteBinding.wrappedValue.title = title
		} else {
			fetchTitleIfNeeded(for: websiteBinding)
		}

		return websiteBinding
	}

	/**
	Remove a website.
	*/
	func remove(_ website: Website) {
		all = all.removingAll(website)
	}

	/**
	Makes the next website the current one.

	If a display is given, it only changes the website for that display.
	*/
	func makeNextCurrent(for display: Display? = nil) {
		guard let display else {
			if let nextCurrent {
				makeCurrent(nextCurrent)
			}

			return
		}

		guard let website = all.elementAfterOrFirst(current(for: display)) else {
			return
		}

		setCurrent(website, for: display)
	}

	/**
	Makes the previous website the current one.

	If a display is given, it only changes the website for that display.
	*/
	func makePreviousCurrent(for display: Display? = nil) {
		guard let display else {
			if let previousCurrent {
				makeCurrent(previousCurrent)
			}

			return
		}

		guard let website = all.elementBeforeOrLast(current(for: display)) else {
			return
		}

		setCurrent(website, for: display)
	}

	/**
	Makes a random website in the list the current one.

	If a display is given, it only changes the website for that display.
	*/
	func makeRandomCurrent(for display: Display? = nil) {
		guard let website = randomWebsiteIterator.next() else {
			return
		}

		guard let display else {
			makeCurrent(website)
			return
		}

		setCurrent(website, for: display)
	}

	/**
	Fetch the title for a website in the background if the existing title is empty.
	*/
	func fetchTitleIfNeeded(for website: Binding<Website>) {
		guard website.wrappedValue.title.isEmpty else {
			return
		}

		Task {
			let metadataProvider = LPMetadataProvider()
			metadataProvider.shouldFetchSubresources = false

			guard
				let metadata = try? await metadataProvider.startFetchingMetadata(for: website.wrappedValue.url),
				let title = metadata.title
			else {
				return
			}

			website.wrappedValue.title = title
		}
	}
}
