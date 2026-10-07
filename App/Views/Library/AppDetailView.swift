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

		return ScrollView {
			VStack(spacing: 20) {
				// Hero
				VStack(spacing: 12) {
					ZStack {
						AppIconView(url: app.iconURL, size: 150)
							.blur(radius: 40)
							.opacity(0.6)
						AppIconView(url: app.iconURL, size: 112)
							.shadow(color: .black.opacity(0.2), radius: 14, y: 6)
					}
					Text(app.name).font(.title2.weight(.bold)).multilineTextAlignment(.center)
					Text(app.bundleID).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
					Pill(text: app.kind == .signed ? "Signed" : "Unsigned", color: app.kind == .signed ? .green : .orange)
				}
				.padding(.top, 12)

				// Actions
				VStack(spacing: 10) {
					if app.kind == .signed {
						Button { installer.install(app) } label: {
							Label("Install", systemImage: "arrow.down.app.fill")
						}
						.buttonStyle(SpectraButtonStyle())
						HStack(spacing: 10) {
							ShareLink(item: app.ipaURL, preview: SharePreview(app.shareFileName)) {
								Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
							}
							if let origin {
								Button { signing = origin } label: {
									Label("Sign Again", systemImage: "signature").frame(maxWidth: .infinity)
								}
							}
						}
						.buttonStyle(.bordered)
						.buttonBorderShape(.capsule)
						.controlSize(.large)
					} else {
						Button { signing = app } label: {
							Label("Sign", systemImage: "signature")
						}
						.buttonStyle(SpectraButtonStyle())
					}
				}
				.padding(.horizontal, 16)

				// Info
				VStack(spacing: 0) {
					infoRow("Version", app.version)
					if let minOS = app.minimumOS {
						divider
						infoRow("Minimum iOS", minOS)
					}
					divider
					infoRow("Size", app.size.formattedBytes)
					divider
					infoRow(app.kind == .signed ? "Signed" : "Imported", app.date.formatted(date: .abbreviated, time: .shortened))
					if app.kind == .signed {
						divider
						infoRow("Certificate", app.certificateName ?? "Unknown")
						if let expiry = app.certificateExpiry {
							divider
							HStack {
								Text("Expiry").foregroundStyle(.secondary)
								Spacer()
								Text(expiry.expiryDescription).foregroundStyle(expiry.expiryColor)
							}
							.font(.subheadline)
						}
					}
				}
				.glassCard()
				.padding(.horizontal, 16)

				Button("Delete App", role: .destructive) { confirmDelete = true }
					.font(.subheadline.weight(.semibold))
					.padding(.bottom, 24)
			}
		}
		.background(AuroraBackground())
		.navigationBarTitleDisplayMode(.inline)
		.sheet(item: $signing) { SignView(app: $0) }
		.confirmationDialog("Delete \(app.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
			Button("Delete", role: .destructive) {
				library.delete(app)
				dismiss()
			}
		}
	}

	private var divider: some View { Divider().padding(.vertical, 9) }

	private func infoRow(_ title: String, _ value: String) -> some View {
		HStack {
			Text(title).foregroundStyle(.secondary)
			Spacer()
			Text(value).multilineTextAlignment(.trailing).lineLimit(2)
		}
		.font(.subheadline)
	}
}
