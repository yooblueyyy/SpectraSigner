import SwiftUI

struct SourcesView: View {
	@EnvironmentObject private var sources: SourceStore
	@EnvironmentObject private var router: AppRouter

	@State private var showAdd = false
	@State private var search = ""

	private var searchResults: [SourceEntry] {
		sources.allApps.filter {
			$0.app.name.localizedCaseInsensitiveContains(search)
				|| ($0.app.developerName ?? "").localizedCaseInsensitiveContains(search)
				|| $0.app.bundleIdentifier.localizedCaseInsensitiveContains(search)
		}
	}

	var body: some View {
		NavigationStack {
			List {
				if !search.isEmpty {
					Section("\(searchResults.count) Apps") {
						ForEach(searchResults) { pair in
							NavigationLink {
								RepoAppDetailView(app: pair.app, source: pair.source)
							} label: {
								RepoAppRow(app: pair.app)
							}
						}
					}
				} else {
					if !sources.sources.isEmpty {
						Section {
							NavigationLink {
								AppListView(title: "All Apps", entries: sources.allApps)
							} label: {
								Label {
									VStack(alignment: .leading) {
										Text("All Apps").font(.body.weight(.semibold))
										Text("\(sources.allApps.count) apps from \(sources.sources.count) sources")
											.font(.caption)
											.foregroundStyle(.secondary)
									}
								} icon: {
									Image(systemName: "square.grid.2x2.fill")
										.foregroundStyle(Color.accentColor)
								}
							}
						}
					}

					Section("Sources") {
						ForEach(sources.sources) { source in
							NavigationLink {
								SourceDetailView(source: source)
							} label: {
								SourceRow(source: source)
							}
							.contextMenu {
								Button { UIPasteboard.general.string = source.url.absoluteString } label: {
									Label("Copy URL", systemImage: "doc.on.doc")
								}
								Button(role: .destructive) { sources.remove(source) } label: {
									Label("Remove", systemImage: "trash")
								}
							}
						}
						.onDelete { offsets in
							offsets.map { sources.sources[$0] }.forEach(sources.remove)
						}
						.onMove { sources.move(from: $0, to: $1) }
					}
				}
			}
			.overlay {
				if sources.sources.isEmpty {
					EmptyStateView(
						title: "No Sources",
						systemImage: "globe",
						message: "Add an AltStore-compatible source to browse and download apps."
					)
				}
			}
			.searchable(text: $search, prompt: "Search all sources")
			.refreshable { await sources.refreshAll() }
			.navigationTitle("Sources")
			.toolbar {
				ToolbarItem(placement: .primaryAction) {
					Button { showAdd = true } label: { Image(systemName: "plus") }
				}
				if !sources.sources.isEmpty {
					ToolbarItem(placement: .navigationBarLeading) { EditButton() }
				}
			}
			.sheet(isPresented: $showAdd) {
				AddSourceView(initialURL: router.pendingSourceURL ?? "")
			}
			.onChange(of: router.pendingSourceURL) { pending in
				if pending != nil { showAdd = true }
			}
			.onChange(of: showAdd) { shown in
				if !shown { router.pendingSourceURL = nil }
			}
			.task {
				if sources.repositories.isEmpty { await sources.refreshAll() }
			}
		}
	}
}

private struct SourceRow: View {
	let source: SavedSource
	@EnvironmentObject private var sources: SourceStore

	var body: some View {
		HStack(spacing: 12) {
			AppIconView(url: source.iconURL, size: 40)
			VStack(alignment: .leading, spacing: 2) {
				Text(source.name).font(.body.weight(.medium)).lineLimit(1)
				if let error = sources.errors[source.url] {
					Text(error).font(.caption).foregroundStyle(.red).lineLimit(1)
				} else if let repo = sources.repositories[source.url] {
					Text("\(repo.apps.count) apps").font(.caption).foregroundStyle(.secondary)
				} else {
					Text(source.url.host ?? source.url.absoluteString).font(.caption).foregroundStyle(.secondary)
				}
			}
			Spacer()
			if sources.loading.contains(source.url) {
				ProgressView()
			}
		}
	}
}

struct SourceDetailView: View {
	let source: SavedSource
	@EnvironmentObject private var sources: SourceStore

	var body: some View {
		let repo = sources.repositories[source.url]
		List {
			if let repo {
				Section {
					VStack(alignment: .leading, spacing: 10) {
						HStack(spacing: 14) {
							AppIconView(url: repo.iconURL, size: 60)
							VStack(alignment: .leading, spacing: 2) {
								Text(repo.name).font(.title3.weight(.bold))
								if let subtitle = repo.subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
							}
						}
						if let description = repo.description {
							Text(description).font(.footnote).foregroundStyle(.secondary)
						}
						if let website = repo.website {
							Link(destination: website) {
								Label(website.host ?? "Website", systemImage: "safari")
									.font(.footnote)
							}
						}
					}
					.padding(.vertical, 4)
				}

				if !repo.news.isEmpty {
					Section("News") {
						ScrollView(.horizontal, showsIndicators: false) {
							HStack(spacing: 12) {
								ForEach(repo.news) { NewsCard(news: $0) }
							}
							.padding(.vertical, 4)
						}
						.listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
					}
				}

				Section("\(repo.apps.count) Apps") {
					ForEach(repo.apps) { app in
						NavigationLink {
							RepoAppDetailView(app: app, source: source)
						} label: {
							RepoAppRow(app: app)
						}
					}
				}
			} else if let error = sources.errors[source.url] {
				EmptyStateView(title: "Couldn't Load", systemImage: "wifi.exclamationmark", message: error)
			} else {
				ProgressView().frame(maxWidth: .infinity)
			}
		}
		.navigationTitle(source.name)
		.navigationBarTitleDisplayMode(.inline)
		.refreshable { await sources.refresh(source) }
		.task {
			if repo == nil { await sources.refresh(source) }
		}
	}
}

struct AppListView: View {
	let title: String
	let entries: [SourceEntry]

	var body: some View {
		List(entries) { entry in
			NavigationLink {
				RepoAppDetailView(app: entry.app, source: entry.source)
			} label: {
				RepoAppRow(app: entry.app)
			}
		}
		.navigationTitle(title)
	}
}

private struct NewsCard: View {
	let news: RepoNews

	var body: some View {
		let tint = Color(hex: news.tintColor) ?? .accentColor
		let card = VStack(alignment: .leading, spacing: 6) {
			Text(news.title).font(.headline).foregroundStyle(.white).lineLimit(2)
			if let caption = news.caption {
				Text(caption).font(.caption).foregroundStyle(.white.opacity(0.85)).lineLimit(3)
			}
			Spacer(minLength: 0)
		}
		.padding(14)
		.frame(width: 240, height: 120, alignment: .topLeading)
		.background(tint.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

		if let url = news.url {
			Link(destination: url) { card }
		} else {
			card
		}
	}
}
