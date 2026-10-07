import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
	enum Filter: String, CaseIterable, Identifiable {
		case all = "All", unsigned = "Unsigned", signed = "Signed"
		var id: String { rawValue }
	}

	@EnvironmentObject private var library: LibraryStore
	@EnvironmentObject private var downloads: DownloadManager
	@EnvironmentObject private var installer: InstallManager
	@EnvironmentObject private var router: AppRouter

	@State private var filter: Filter = .all
	@State private var search = ""
	@State private var showImporter = false
	@State private var showURLPrompt = false
	@State private var urlText = ""
	@State private var signing: LibraryApp?
	@State private var deleting: LibraryApp?

	private var visible: [LibraryApp] {
		library.apps.filter { app in
			let kindMatch = filter == .all || (filter == .signed) == (app.kind == .signed)
			let searchMatch = search.isEmpty
				|| app.name.localizedCaseInsensitiveContains(search)
				|| app.bundleID.localizedCaseInsensitiveContains(search)
			return kindMatch && searchMatch
		}
	}

	var body: some View {
		NavigationStack {
			List {
				Section {
					Picker("Filter", selection: $filter) {
						ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
					}
					.pickerStyle(.segmented)
					.listRowBackground(Color.clear)
					.listRowInsets(EdgeInsets())
				}

				if !downloads.items.isEmpty || !library.imports.isEmpty {
					Section("In Progress") {
						ForEach(downloads.items) { item in
							ProgressRow(
								title: item.name,
								detail: item.expected > 0
									? "\(item.received.formattedBytes) of \(item.expected.formattedBytes)"
									: "Downloading…",
								progress: item.progress
							)
							.swipeActions {
								Button("Cancel", role: .destructive) { downloads.cancel(item) }
							}
						}
						ForEach(library.imports) { job in
							ImportRow(job: job)
						}
					}
				}

				Section {
					ForEach(visible) { app in
						NavigationLink(value: app) {
							LibraryRow(app: app)
						}
						.swipeActions(edge: .trailing) {
							Button("Delete", role: .destructive) { deleting = app }
						}
						.swipeActions(edge: .leading) {
							if app.kind == .signed {
								Button("Install") { installer.install(app) }.tint(.accentColor)
							} else {
								Button("Sign") { signing = app }.tint(.accentColor)
							}
						}
						.contextMenu { menu(for: app) }
					}
				}
			}
			.overlay {
				if library.apps.isEmpty && downloads.items.isEmpty && library.imports.isEmpty {
					EmptyStateView(
						title: "No Apps",
						systemImage: "square.stack.3d.up.slash",
						message: "Import an .ipa with the + button, or get one from a source."
					)
				}
			}
			.searchable(text: $search, prompt: "Search apps")
			.navigationTitle("Library")
			.navigationDestination(for: LibraryApp.self) { app in
				AppDetailView(appID: app.id)
			}
			.toolbar {
				ToolbarItem(placement: .primaryAction) {
					Menu {
						Button { showImporter = true } label: {
							Label("Import from Files", systemImage: "folder")
						}
						Button { showURLPrompt = true } label: {
							Label("Import from URL", systemImage: "link")
						}
					} label: {
						Image(systemName: "plus")
					}
				}
			}
			.fileImporter(isPresented: $showImporter, allowedContentTypes: [.ipa, .tipa], allowsMultipleSelection: true) { result in
				switch result {
				case .success(let urls):
					for url in urls {
						Task {
							do { try await library.importIPA(at: url) } catch { router.show(error) }
						}
					}
				case .failure(let error):
					router.show(error)
				}
			}
			.alert("Import from URL", isPresented: $showURLPrompt) {
				TextField("https://example.com/app.ipa", text: $urlText)
					.keyboardType(.URL)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
				Button("Cancel", role: .cancel) { urlText = "" }
				Button("Download") {
					if let url = SourceStore.normalize(urlText) {
						downloads.download(url, name: url.deletingPathExtension().lastPathComponent)
					} else {
						router.alert = "That doesn't look like a valid URL."
					}
					urlText = ""
				}
			} message: {
				Text("Enter a direct link to an .ipa file.")
			}
			.sheet(item: $signing) { app in
				SignView(app: app)
			}
			.confirmationDialog(
				"Delete \(deleting?.name ?? "app")?",
				isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
				titleVisibility: .visible
			) {
				Button("Delete", role: .destructive) {
					if let deleting { library.delete(deleting) }
					deleting = nil
				}
			}
		}
	}

	@ViewBuilder
	private func menu(for app: LibraryApp) -> some View {
		if app.kind == .signed {
			Button { installer.install(app) } label: { Label("Install", systemImage: "arrow.down.app") }
			ShareLink(item: app.ipaURL, preview: SharePreview(app.shareFileName)) {
				Label("Share IPA", systemImage: "square.and.arrow.up")
			}
		} else {
			Button { signing = app } label: { Label("Sign", systemImage: "signature") }
		}
		Button { UIPasteboard.general.string = app.bundleID } label: {
			Label("Copy Bundle ID", systemImage: "doc.on.doc")
		}
		Button(role: .destructive) { deleting = app } label: { Label("Delete", systemImage: "trash") }
	}
}

struct LibraryRow: View {
	let app: LibraryApp

	var body: some View {
		HStack(spacing: 14) {
			AppIconView(url: app.iconURL, size: 52)
			VStack(alignment: .leading, spacing: 3) {
				Text(app.name)
					.font(.body.weight(.semibold))
					.lineLimit(1)
				Text("\(app.version) · \(app.bundleID)")
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
				HStack(spacing: 6) {
					if app.kind == .signed {
						Pill(text: "Signed", color: .green)
						if let expiry = app.certificateExpiry {
							Text(expiry.expiryDescription)
								.font(.caption2)
								.foregroundStyle(expiry.expiryColor)
						}
					} else {
						Pill(text: "Unsigned", color: .secondary)
						Text(app.size.formattedBytes)
							.font(.caption2)
							.foregroundStyle(.secondary)
					}
				}
			}
		}
		.padding(.vertical, 2)
	}
}

struct ProgressRow: View {
	var title: String
	var detail: String
	var progress: Double?

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack {
				Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
				Spacer()
				Text(detail).font(.caption).foregroundStyle(.secondary)
			}
			if let progress {
				ProgressView(value: progress)
			} else {
				ProgressView().frame(maxWidth: .infinity, alignment: .leading)
			}
		}
		.padding(.vertical, 4)
	}
}

/// Polls a Foundation `Progress` so extraction progress shows while importing.
private struct ImportRow: View {
	let job: LibraryStore.ImportJob
	@State private var fraction: Double = 0
	private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

	var body: some View {
		ProgressRow(title: job.name, detail: "Importing…", progress: fraction)
			.onReceive(timer) { _ in fraction = job.progress.fractionCompleted }
	}
}
