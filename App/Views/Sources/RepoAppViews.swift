import SwiftUI

struct RepoAppRow: View {
	let app: RepoApp

	var body: some View {
		HStack(spacing: 14) {
			AppIconView(url: app.iconURL, size: 52)
			VStack(alignment: .leading, spacing: 3) {
				Text(app.name).font(.body.weight(.semibold)).lineLimit(1)
				Text(app.subtitle ?? app.developerName ?? app.bundleIdentifier)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
				if let version = app.version, !version.isEmpty {
					Text("v\(version)").font(.caption2).foregroundStyle(.secondary)
				}
			}
			Spacer(minLength: 8)
			GetButton(app: app)
		}
		.padding(.vertical, 2)
	}
}

/// "Get" button that turns into a progress ring while downloading.
struct GetButton: View {
	let app: RepoApp
	var version: RepoVersion?

	@EnvironmentObject private var downloads: DownloadManager

	private var url: URL? { version?.downloadURL ?? app.downloadURL }

	var body: some View {
		if let url {
			if let item = downloads.item(for: url) {
				Button { downloads.cancel(item) } label: {
					ZStack {
						Circle().stroke(Color.accentColor.opacity(0.2), lineWidth: 3)
						Circle()
							.trim(from: 0, to: max(0.02, item.progress))
							.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
							.rotationEffect(.degrees(-90))
						RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 8, height: 8)
					}
					.frame(width: 28, height: 28)
				}
				.buttonStyle(.plain)
			} else {
				Button {
					downloads.download(url, name: app.name)
				} label: {
					Text("GET")
						.font(.subheadline.weight(.bold))
						.padding(.horizontal, 16)
						.padding(.vertical, 6)
						.background(Color(.tertiarySystemFill), in: Capsule())
				}
				.buttonStyle(.plain)
				.foregroundStyle(Color.accentColor)
			}
		}
	}
}

struct RepoAppDetailView: View {
	let app: RepoApp
	let source: SavedSource

	@State private var expanded = false

	var body: some View {
		List {
			Section {
				HStack(alignment: .top, spacing: 16) {
					AppIconView(url: app.iconURL, size: 96)
					VStack(alignment: .leading, spacing: 4) {
						Text(app.name).font(.title2.weight(.bold))
						if let developer = app.developerName {
							Text(developer).font(.subheadline).foregroundStyle(.secondary)
						}
						Spacer(minLength: 8)
						GetButton(app: app)
					}
				}
				.padding(.vertical, 6)
			}

			Section {
				LabeledContent("Version", value: app.version ?? "—")
				if let size = app.size { LabeledContent("Size", value: Int64(size).formattedBytes) }
				LabeledContent("Bundle ID", value: app.bundleIdentifier)
				if let minOS = app.latest?.minOSVersion { LabeledContent("Requires", value: "iOS \(minOS)") }
				LabeledContent("Source", value: source.name)
			}

			if !app.screenshots.isEmpty {
				Section("Screenshots") {
					ScrollView(.horizontal, showsIndicators: false) {
						HStack(spacing: 10) {
							ForEach(app.screenshots, id: \.self) { url in
								AsyncImage(url: url) { phase in
									if let image = phase.image {
										image.resizable().scaledToFit()
									} else {
										Color(.secondarySystemFill)
									}
								}
								.frame(height: 360)
								.frame(minWidth: 166)
								.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
							}
						}
					}
					.listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
				}
			}

			if let description = app.localizedDescription {
				Section("Description") {
					Text(description)
						.font(.subheadline)
						.lineLimit(expanded ? nil : 6)
					if !expanded && description.count > 300 {
						Button("More") { expanded = true }
					}
				}
			}

			if let notes = app.latest?.localizedDescription, !notes.isEmpty {
				Section("What's New") {
					Text(notes).font(.subheadline)
				}
			}

			if app.versions.count > 1 {
				Section("Version History") {
					ForEach(app.versions, id: \.self) { version in
						HStack {
							VStack(alignment: .leading, spacing: 2) {
								Text(version.version).font(.body.weight(.medium))
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
			}
		}
		.navigationTitle(app.name)
		.navigationBarTitleDisplayMode(.inline)
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

				let suggestions = SourceStore.suggestions.filter { suggestion in
					!sources.sources.contains { $0.url.absoluteString == suggestion.url }
				}
				if !suggestions.isEmpty {
					Section("Suggested") {
						ForEach(suggestions) { suggestion in
							Button {
								text = suggestion.url
								add()
							} label: {
								VStack(alignment: .leading, spacing: 2) {
									Text(suggestion.name).foregroundStyle(.primary)
									Text(suggestion.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
								}
							}
						}
					}
				}
			}
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
