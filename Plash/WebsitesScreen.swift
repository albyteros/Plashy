import SwiftUI

struct WebsitesScreen: View {
	@Environment(\.requestReview) private var requestReview
	@Default(.websites) private var websites
	@Default(.displayWebsites) private var displayWebsites
	@Default(.disabledDisplays) private var disabledDisplays
//	@State private var selection: Website.ID? // We need two states as selection must be independent from actually opening the editing because of keyboard navigation and accessibility.
	@State private var editedWebsite: Website.ID?
	@State private var isAddWebsiteDialogPresented = false
	@Namespace private var bottomScrollID

	var body: some View {
		Form {
			List($websites, editActions: .all) { website in
				RowView(
					website: website,
					selection: $editedWebsite
				)
			}
			.id([websites.hashValue, displayWebsites.hashValue, disabledDisplays.hashValue]) // Workaround for the row not updating when changing the current active website. It's placed here and not on the row to prevent another issue where adding a new website makes it scroll outside the view. (macOS 15.3)
//			.onKeyboardShortcut(.defaultAction) {
//				editedWebsite = selection
//			}
			.onChange(of: websites) { oldWebsites, websites in
				// Check that a website was added.
				guard websites.count > oldWebsites.count else {
					return
				}

				withAnimation {
//					scrollViewProxy.scrollTo(bottomScrollID, anchor: .top)
				}
			}
			.overlay {
				if websites.isEmpty {
					Text("No Websites")
						.emptyStateTextStyle()
				}
			}
			.accessibilityAction(named: "Add website") {
				isAddWebsiteDialogPresented = true
			}
		}
		.formStyle(.grouped)
		.frame(width: 480, height: 500)
//		.onChange(of: editedWebsite) {
//			selection = $0
//		}
		.sheet(item: $editedWebsite) {
			AddWebsiteScreen(
				isEditing: true,
				website: $websites[id: $0]
			)
		}
		.sheet(isPresented: $isAddWebsiteDialogPresented) {
			AddWebsiteScreen(
				isEditing: false,
				website: nil
			)
		}
		.onNotification(.showAddWebsiteDialog) { _ in
			isAddWebsiteDialogPresented = true
		}
		.onNotification(.showEditWebsiteDialog) {
			editedWebsite = $0.object as? Website.ID ?? WebsitesController.shared.current?.id
		}
		.toolbar {
			Button("Add Website", systemImage: "plus") {
				isAddWebsiteDialogPresented = true
			}
			.keyboardShortcut("+")
		}
		.onAppear {
			SSApp.requestReviewAfterBeingCalledThisManyTimes([3, 50, 500], requestReview)
		}
		.windowMinimizeBehavior(.disabled)
		.windowLevel(.floating)
	}
}

#Preview {
	WebsitesScreen()
}

private struct RowView: View {
	@Binding var website: Website
	@Binding var selection: Website.ID?

	private var isMultiDisplay: Bool { AppState.shared.instances.count > 1 }

	private var isShown: Bool {
		AppState.shared.instances.isEmpty ? website.isCurrent : !WebsitesController.shared.displays(showing: website).isEmpty
	}

	/**
	With a single display, shows the website on it. With multiple displays, shows it on the main display and the displays that have not been given their own website.
	*/
	private func setAsCurrent() {
		let displays = AppState.shared.activeDisplays

		if displays.count == 1, let display = displays.first {
			WebsitesController.shared.setCurrent(website, for: display)
		} else {
			website.makeCurrent()
		}
	}

	var body: some View {
		HStack {
			Label {
				// TODO: This should use something like `.lineBreakMode = .byCharWrapping` if SwiftUI ever supports that.
				if let title = website.title.nilIfEmpty {
					Text(title)
				}
				Text(website.subtitle)
			} icon: {
				IconView(website: website)
			}
			.lineLimit(1)
			Spacer()
			if isMultiDisplay {
				let displays = WebsitesController.shared.displays(showing: website)
				if !displays.isEmpty {
					Text(displays.map(\.localizedName).formatted(.list(type: .and)))
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(2)
						.multilineTextAlignment(.trailing)
						.frame(maxWidth: 120, alignment: .trailing)
				}
			}
			if isShown {
				Image(systemName: "checkmark.circle.fill")
					.renderingMode(.original)
					.font(.title2)
			}
		}
		.frame(height: 64) // Note: Setting a fixed height prevents a lot of SwiftUI rendering bugs.
		.padding(.horizontal, 8)
		.help(website.tooltip)
		.swipeActions(edge: .leading, allowsFullSwipe: true) {
			Button("Set as Current") {
				setAsCurrent()
			}
			.disabled(isMultiDisplay ? website.isCurrent : isShown)
		}
		.contentShape(.rect)
		.onDoubleClick {
			selection = website.id
		}
		.contextMenu { // Must come after `.onDoubleClick`.
			if isMultiDisplay {
				Menu("Show On") {
					Button("All Displays") {
						WebsitesController.shared.showOnAllDisplays(website)
					}
					Divider()
					ForEach(AppState.shared.activeDisplays) { display in
						Button(display.localizedName) {
							WebsitesController.shared.setCurrent(website, for: display)
						}
						.disabled(WebsitesController.shared.current(for: display)?.id == website.id)
					}
				}
			} else {
				Button("Set as Current") {
					setAsCurrent()
				}
				.disabled(isShown)
			}
			Divider()
			Button("Edit…") {
				selection = website.id
			}
			Divider()
			Button("Delete", role: .destructive) {
				website.remove()
			}
		}
		.accessibilityElement(children: .combine)
		.accessibilityAddTraits(.isButton)
		.if(isShown) {
			$0.accessibilityAddTraits(.isSelected)
		}
		.accessibilityAction(named: "Edit") { // Doesn't show up in accessibility actions. (macOS 14.0)
			selection = website.id
		}
		.accessibilityRepresentation {
			Button(website.menuTitle) {
				selection = website.id
			}
		}
	}
}

private struct IconView: View {
	@State private var icon: Image?

	let website: Website

	var body: some View {
		VStack {
			if let icon {
				icon
					.resizable()
					.scaledToFit()
			} else {
				Color.primary.opacity(0.1)
			}
		}
		.frame(width: 32, height: 32)
		.clipShape(.rect(cornerRadius: 4))
		.task(id: website.url) {
			guard let image = await fetchIcons() else {
				return
			}

			icon = Image(nsImage: image)
		}
	}

	private func fetchIcons() async -> NSImage? {
		let cache = WebsitesController.shared.thumbnailCache

		if let image = cache[website.thumbnailCacheKey] {
			return image
		}

		guard let image = try? await WebsiteIconFetcher.fetch(for: website.url) else {
			return nil
		}

		cache[website.thumbnailCacheKey] = image

		return image
	}
}
