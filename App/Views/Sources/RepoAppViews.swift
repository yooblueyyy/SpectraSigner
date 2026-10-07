import SwiftUI

struct RepoAppRow: View {
	let app: RepoApp

	var body: some View {
		HStack(spacing: 14) {
			AppIconView(url: app.iconURL, size: 54)
			VStack(alignment: .leading, spacing: 3) {
				Text(app.name).font(.body.weight(.semibold)).lineLimit(1)
				Text(app.subtitle ?? app.developerName ?? app.bundleIdentifier)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(2)
				if let version = app.version, !version.isEmpty {
					Text("v\(version)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
				}
			}
			Spacer(minLength: 8)
			GetButton(app: app)
		}
		.padding(.vertical, 2)
	}
}

/// "GET" pill that turns into a spectrum progress ring while downloading.
struct GetButton: View {
	let app: RepoApp
	var version: RepoVersion?
	var large = false

	@EnvironmentObject private var downloads: DownloadManager

	private var url: URL? { version?.downloadURL ?? app.downloadURL }

	var body: some View {
		if let url {
			if let item = downloads.item(for: url) {
				Button { downloads.cancel(item) } label: {
					SpectraRing(progress: item.progress, size: large ? 34 : 28, lineWidth: 3) {
						RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 8, height: 8)
					}
				}
				.buttonStyle(.plain)
				.accessibilityLabel("Cancel download")
			} else {
				Button("GET") {
					UIImpactFeedbackGenerator(style: .light).impactOccurred()
					downloads.download(url, name: app.name)
				}
				.buttonStyle(PillButtonStyle(filled: large))
			}
		}
	}
}

struct RepoAppDetailView: View {
	let app: RepoApp
	let source: SavedSource

	@State private var expanded = false

	private var tint: Color { Color(hex: app.tintColor) ?? .accentColor }

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 24) {
				header

				infoStrip

				if !app.screenshots.isEmpty {
					VStack(alignment: .leading, spacing: 10) {
						Text("Preview").font(.title3.weight(.bold)).padding(.horizontal, 20)
						ScrollView(.horizontal, showsIndicators: false) {
							HStack(spacing: 12) {
								ForEach(app.screenshots, id: \.self) { url in
									AsyncImage(url: url) { phase in
										if let image = phase.image {
											image.resizable().scaledToFit()
										} else {
											Color(.secondarySystemFill)
										}
									}
									.frame(height: 380)
									.frame(minWidth: 176)
									.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
									.overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
								}
							}
							.padding(.horizontal, 20)
						}
					}
				}

				if let notes = app.latest?.localizedDescription, !notes.isEmpty {
					VStack(alignment: .leading, spacing: 8) {
						HStack {
							Text("What's New").font(.headline)
							Spacer()
							if let date = app.latest?.parsedDate {
								Text(date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
							}
						}
						Text(notes).font(.subheadline).foregroundStyle(.secondary)
					}
					.glassCard()
					.padding(.horizontal, 16)
				}

				if let description = app.localizedDescription {
					VStack(alignment: .leading, spacing: 8) {
						Text("About").font(.headline)
						Text(description)
							.font(.subheadline)
							.lineLimit(expanded ? nil : 6)
						if !expanded && description.count > 280 {
							Button("Read More") { withAnimation { expanded = true } }
								.font(.subheadline.weight(.semibold))
						}
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.glassCard()
					.padding(.horizontal, 16)
				}

				if app.versions.count > 1 {
					VStack(alignment: .leading, spacing: 0) {
						Text("Version History").font(.headline).padding(.bottom, 8)
						ForEach(Array(app.versions.prefix(15).enumerated()), id: \.offset) { index, version in
							if index > 0 { Divider().padding(.vertical, 8) }
							HStack {
								VStack(alignment: .leading, spacing: 2) {
									Text(version.version).font(.subheadline.weight(.semibold))
									if let date = version.parsedDate {
										Text(date.formatted(date: .abbreviated, time: .omitted))
											.font(.caption)
											.foregroundStyle(.secondary)
									}
								}
								Spacer()
								GetButton(app: app, version: version)
							}
						}
					}
					.glassCard()
					.padding(.horizontal, 16)
				}

				VStack(alignment: .leading, spacing: 0) {
					infoRow("Bundle ID", app.bundleIdentifier)
					Divider().padding(.vertical, 8)
					infoRow("Source", source.name)
					if let category = app.category {
						Divider().padding(.vertical, 8)
						infoRow("Category", category.capitalized)
					}
				}
				.glassCard()
				.padding(.horizontal, 16)
				.padding(.bottom, 24)
			}
		}
		.background(AuroraBackground())
		.navigationBarTitleDisplayMode(.inline)
	}

	private var header: some View {
		ZStack(alignment: .bottomLeading) {
			LinearGradient(colors: [tint.opacity(0.9), tint.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
				.frame(height: 230)
				.overlay(
					AppIconView(url: app.iconURL, size: 300)
						.blur(radius: 60)
						.opacity(0.4)
						.offset(y: -60)
				)
				.clipped()

			HStack(alignment: .bottom, spacing: 16) {
				AppIconView(url: app.iconURL, size: 104)
					.shadow(color: tint.opacity(0.45), radius: 16, y: 8)
				VStack(alignment: .leading, spacing: 6) {
					Text(app.name)
						.font(.title2.weight(.bold))
						.lineLimit(2)
					Text(app.developerName ?? source.name)
						.font(.subheadline)
						.foregroundStyle(.secondary)
					GetButton(app: app, large: true)
						.padding(.top, 2)
				}
				Spacer(minLength: 0)
			}
			.padding(.horizontal, 20)
			.offset(y: 30)
		}
		.padding(.bottom, 30)
	}

	private var infoStrip: some View {
		HStack(spacing: 0) {
			infoCell(title: "Version", value: app.version.flatMap { $0.isEmpty ? nil : $0 } ?? "—")
			Divider().frame(height: 30)
			infoCell(title: "Size", value: app.size.map { Int64($0).formattedBytes } ?? "—")
			Divider().frame(height: 30)
			infoCell(title: "Requires", value: app.latest?.minOSVersion.map { "iOS \($0)" } ?? "—")
		}
		.glassCard(padding: 12)
		.padding(.horizontal, 16)
	}

	private func infoCell(title: String, value: String) -> some View {
		VStack(spacing: 3) {
			Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
			Text(value).font(.subheadline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
		}
		.frame(maxWidth: .infinity)
	}

	private func infoRow(_ title: String, _ value: String) -> some View {
		HStack {
			Text(title).foregroundStyle(.secondary)
			Spacer()
			Text(value).multilineTextAlignment(.trailing).lineLimit(2).textSelection(.enabled)
		}
		.font(.subheadline)
	}
}

struct AddSourceView: View {
	@EnvironmentObject private var sources: SourceStore
	@Environment(\.dismiss) private var dismiss

	@State private var text: String
	@State private var adding = false
	@State private var error: String?

	init(initialURL: String = "") {
		_text = State(initialValue: initialURL)
	}

	var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField("https://example.com/source.json", text: $text)
						.keyboardType(.URL)
						.textInputAutocapitalization(.never)
						.autocorrectionDisabled()
				} header: {
					Text("Source URL")
				} footer: {
					if let error {
						Text(error).foregroundStyle(.red)
					} else {
						Text("Any AltStore-compatible source works.")
					}
				}

				Section {
					Button {
						if let pasted = UIPasteboard.general.string { text = pasted }
					} label: {
						Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
					}
				}

				if sources.missingBuiltinCount > 0 {
					Section {
						Button {
							Task {
								await sources.restoreBuiltins()
								dismiss()
							}
						} label: {
							Label("Restore \(sources.missingBuiltinCount) Built-in Sources", systemImage: "arrow.counterclockwise")
						}
					}
				}
			}
			.spectraBackground()
			.disabled(adding)
			.navigationTitle("Add Source")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { dismiss() }
				}
				ToolbarItem(placement: .confirmationAction) {
					if adding {
						ProgressView()
					} else {
						Button("Add") { add() }
							.fontWeight(.semibold)
							.disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
					}
				}
			}
		}
	}

	private func add() {
		adding = true
		error = nil
		Task {
			do {
				try await sources.add(text)
				dismiss()
			} catch {
				self.error = error.localizedDescription
			}
			adding = false
		}
	}
}
