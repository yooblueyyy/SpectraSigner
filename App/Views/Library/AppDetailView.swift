import SwiftUI

struct AppDetailView: View {
	let appID: UUID

	@EnvironmentObject private var library: LibraryStore
	@EnvironmentObject private var installer: InstallManager
	@Environment(\.dismiss) private var dismiss

	@State private var signing: LibraryApp?
	@State private var confirmDelete = false

	var body: some View {
		if let app = library.app(appID) {
			content(app)
		} else {
			EmptyStateView(title: "App Removed", systemImage: "questionmark.app", message: "This app is no longer in your library.")
		}
	}

	private func content(_ app: LibraryApp) -> some View {
		let origin = library.app(app.originID)

		return List {
			Section {
				VStack(spacing: 12) {
					AppIconView(url: app.iconURL, size: 96)
					Text(app.name).font(.title2.weight(.bold)).multilineTextAlignment(.center)
					Text(app.bundleID).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
					Pill(text: app.kind == .signed ? "Signed" : "Unsigned", color: app.kind == .signed ? .green : .secondary)
				}
				.frame(maxWidth: .infinity)
				.padding(.vertical, 8)
				.listRowBackground(Color.clear)
			}

			Section {
				if app.kind == .signed {
					Button { installer.install(app) } label: {
						Label("Install", systemImage: "arrow.down.app.fill")
					}
					ShareLink(item: app.ipaURL, preview: SharePreview(app.shareFileName)) {
						Label("Share IPA", systemImage: "square.and.arrow.up")
					}
					if let origin {
						Button { signing = origin } label: {
							Label("Sign Again", systemImage: "signature")
						}
					}
				} else {
					Button { signing = app } label: {
						Label("Sign", systemImage: "signature")
					}
				}
			}

			Section("Information") {
				LabeledContent("Version", value: app.version)
				LabeledContent("Bundle ID", value: app.bundleID)
				if let minOS = app.minimumOS { LabeledContent("Minimum iOS", value: minOS) }
				LabeledContent("Size", value: app.size.formattedBytes)
				LabeledContent(app.kind == .signed ? "Signed" : "Imported", value: app.date.formatted(date: .abbreviated, time: .shortened))
			}

			if app.kind == .signed {
				Section("Certificate") {
					LabeledContent("Signed With", value: app.certificateName ?? "Unknown")
					if let expiry = app.certificateExpiry {
						LabeledContent("Expiry") {
							Text(expiry.expiryDescription).foregroundStyle(expiry.expiryColor)
						}
					}
				}
			}

			Section {
				Button("Delete App", role: .destructive) { confirmDelete = true }
			}
		}
		.navigationTitle(app.name)
		.navigationBarTitleDisplayMode(.inline)
		.sheet(item: $signing) { SignView(app: $0) }
		.confirmationDialog("Delete \(app.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
			Button("Delete", role: .destructive) {
				library.delete(app)
				dismiss()
			}
		}
	}
}
