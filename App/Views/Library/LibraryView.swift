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
	@EnvironmentObject private var certificates: CertificateStore
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

	private var isEmpty: Bool { library.apps.isEmpty && downloads.items.isEmpty && library.imports.isEmpty }

	var body: some View {
		NavigationStack {
			List {
				Section {
					VStack(spacing: 14) {
						HStack(spacing: 10) {
							StatTile(value: "\(library.unsigned.count)", label: "Unsigned", systemImage: "shippingbox.fill", tint: Spectra.colors[1])
							StatTile(value: "\(library.signed.count)", label: "Signed", systemImage: "checkmark.seal.fill", tint: Spectra.colors[3])
							certificateTile
						}
						if !library.apps.isEmpty {
							ChipBar(options: Filter.allCases, selection: $filter) { $0.rawValue }
						}
					}
					.listRowBackground(Color.clear)
					.listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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
							.cardRow()
							.swipeActions {
								Button("Cancel", role: .destructive) { downloads.cancel(item) }
							}
						}
						ForEach(library.imports) { job in
							ImportRow(job: job).cardRow()
						}
					}
				}

				if isEmpty {
					Section {
						VStack(spacing: 16) {
							ZStack {
								Circle().fill(Spectra.angular).frame(width: 84, height: 84).blur(radius: 18).opacity(0.6)
								Image(systemName: "square.and.arrow.down.on.square.fill")
									.font(.system(size: 34, weight: .semibold))
									.foregroundStyle(.white)
									.frame(width: 76, height: 76)
									.background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
							}
							Text("Your library is empty").font(.title3.weight(.bold))
							Text("Import an .ipa, or grab an app from Discover. Apps you sign show up here ready to install.")
								.font(.subheadline)
								.foregroundStyle(.secondary)
								.multilineTextAlignment(.center)
							Button("Import an IPA") { showImporter = true }
								.buttonStyle(SpectraButtonStyle())
							Button("Browse Discover") { router.tab = .discover }
								.font(.subheadline.weight(.semibold))
						}
						.frame(maxWidth: .infinity)
						.glassCard(padding: 24)
						.listRowBackground(Color.clear)
						.listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
					}
				} else {
					Section {
						ForEach(visible) { app in
							NavigationLink(value: app) {
								LibraryRow(app: app)
							}
							.cardRow()
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
			}
			.listStyle(.insetGrouped)
			.spectraBackground()
			.searchable(text: $search, prompt: "Search your apps")
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
						Image(systemName: "plus.circle.fill").font(.title3)
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

	private var certificateTile: some View {
		Group {
			if let cert = certificates.selected {
				let days = Int(cert.expiration.timeIntervalSinceNow / 86_400)
				StatTile(
					value: days < 0 ? "Expired" : "\(days)d",
					label: "Certificate",
					systemImage: "key.fill",
					tint: cert.expiration.expiryColor
				)
			} else {
				Button { router.tab = .settings } label: {
					StatTile(value: "Add", label: "Certificate", systemImage: "key.fill", tint: Spectra.colors[0])
				}
				.buttonStyle(.plain)
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
			AppIconView(url: app.iconURL, size: 56)
			VStack(alignment: .leading, spacing: 4) {
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
						Pill(text: "Unsigned", color: .orange)
						Text(app.size.formattedBytes)
							.font(.caption2)
							.foregroundStyle(.secondary)
					}
				}
			}
		}
	}
}

struct ProgressRow: View {
	var title: String
	var detail: String
	var progress: Double?

	var body: some View {
		HStack(spacing: 14) {
			SpectraRing(progress: progress, size: 40, lineWidth: 4) {
				if let progress {
					Text("\(Int(progress * 100))").font(.caption2.weight(.bold).monospacedDigit())
				}
			}
			VStack(alignment: .leading, spacing: 3) {
				Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
				Text(detail).font(.caption).foregroundStyle(.secondary)
			}
			Spacer()
		}
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
