import SwiftUI

struct SourcesView: View {
	@EnvironmentObject private var sources: SourceStore
	@EnvironmentObject private var router: AppRouter

	@State private var showAdd = false
	@State private var search = ""
	@State private var category = "All"

	private var categories: [String] { ["All"] + sources.groupedSources.map(\.category) }

	private var filteredGroups: [(category: String, sources: [SavedSource])] {
		sources.groupedSources.compactMap { group in
			guard category == "All" || group.category == category else { return nil }
			let list = search.isEmpty ? group.sources : group.sources.filter {
				$0.name.localizedCaseInsensitiveContains(search) || $0.url.absoluteString.localizedCaseInsensitiveContains(search)
			}
			return list.isEmpty ? nil : (category: group.category, sources: list)
		}
	}

	var body: some View {
		NavigationStack {
			List {
				Section {
					VStack(spacing: 14) {
						HStack(spacing: 10) {
							StatTile(value: "\(sources.sources.count)", label: "Sources", systemImage: "globe")
							StatTile(value: "\(sources.totalApps)", label: "Apps", systemImage: "square.grid.2x2.fill", tint: Spectra.colors[4])
						}
						ChipBar(options: categories, selection: $category) { $0 }
					}
					.listRowBackground(Color.clear)
					.listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
				}

				if !sources.sources.isEmpty && category == "All" && search.isEmpty {
					Section {
						NavigationLink {
							AppListView(title: "All Apps", entries: sources.allApps)
						} label: {
							HStack(spacing: 14) {
								ZStack {
									RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Spectra.gradient)
									Image(systemName: "square.grid.2x2.fill").foregroundStyle(.white)
								}
								.frame(width: 44, height: 44)
								VStack(alignment: .leading, spacing: 2) {
									Text("All Apps").font(.body.weight(.semibold))
									Text("Browse every app from every source").font(.caption).foregroundStyle(.secondary)
								}
							}
						}
						.cardRow()
					}
				}

				ForEach(filteredGroups, id: \.category) { group in
					Section {
						ForEach(group.sources) { source in
							NavigationLink {
								SourceDetailView(source: source)
							} label: {
								SourceRow(source: source)
							}
							.cardRow()
							.swipeActions {
								Button("Remove", role: .destructive) { sources.remove(source) }
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
					} header: {
						Text("\(group.category) · \(group.sources.count)")
							.font(.subheadline.weight(.semibold))
							.textCase(nil)
					}
				}
			}
			.listStyle(.insetGrouped)
			.spectraBackground()
			.overlay {
				if sources.sources.isEmpty {
					VStack(spacing: 16) {
						EmptyStateView(title: "No Sources", systemImage: "globe", message: "Add an AltStore-compatible source, or bring back the \(SourceStore.builtin.count) built-in ones.")
						Button("Restore Built-in Sources") {
							Task { await sources.restoreBuiltins() }
						}
						.buttonStyle(SpectraButtonStyle())
						.padding(.horizontal, 40)
					}
				}
			}
			.searchable(text: $search, prompt: "Search sources")
			.refreshable { await sources.refreshAll() }
			.navigationTitle("Sources")
			.toolbar {
				ToolbarItem(placement: .primaryAction) {
					Button { showAdd = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
				}
				ToolbarItem(placement: .navigationBarLeading) {
					if sources.isRefreshing { ProgressView() }
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
		}
	}
}

private struct SourceRow: View {
	let source: SavedSource
	@EnvironmentObject private var sources: SourceStore

	var body: some View {
		HStack(spacing: 12) {
			AppIconView(url: source.iconURL ?? sources.repositories[source.url]?.apps.first?.iconURL, size: 44)
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 6) {
					Text(source.name).font(.body.weight(.medium)).lineLimit(1)
					if source.isBuiltin == true {
						Image(systemName: "checkmark.seal.fill")
							.font(.caption)
							.foregroundStyle(Color.accentColor)
					}
				}
				if let error = sources.errors[source.url], sources.repositories[source.url] == nil {
					Text(error).font(.caption).foregroundStyle(.red).lineLimit(1)
				} else if let repo = sources.repositories[source.url] {
					Text(repo.apps.count == 1 ? "1 app" : "\(repo.apps.count) apps").font(.caption).foregroundStyle(.secondary)
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
					VStack(alignment: .leading, spacing: 12) {
						HStack(spacing: 14) {
							AppIconView(url: repo.iconURL ?? repo.apps.first?.iconURL, size: 64)
							VStack(alignment: .leading, spacing: 3) {
								Text(repo.name).font(.title3.weight(.bold))
								Text(repo.subtitle ?? source.displayCategory).font(.subheadline).foregroundStyle(.secondary)
							}
						}
						if let description = repo.description {
							Text(description).font(.footnote).foregroundStyle(.secondary)
						}
						HStack(spacing: 10) {
							if let website = repo.website {
								Link(destination: website) {
									Label("Website", systemImage: "safari").font(.footnote.weight(.semibold))
								}
							}
							Button {
								UIPasteboard.general.string = source.url.absoluteString
							} label: {
								Label("Copy URL", systemImage: "doc.on.doc").font(.footnote.weight(.semibold))
							}
						}
						.buttonStyle(.bordered)
						.buttonBorderShape(.capsule)
					}
					.padding(.vertical, 6)
					.cardRow()
				}

				if !repo.news.isEmpty {
					Section("News") {
						ScrollView(.horizontal, showsIndicators: false) {
							HStack(spacing: 12) {
								ForEach(repo.news) { NewsCard(news: $0) }
							}
							.padding(.vertical, 4)
						}
						.listRowBackground(Color.clear)
						.listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
					}
				}

				Section("\(repo.apps.count) Apps") {
					ForEach(repo.apps) { app in
						NavigationLink {
							RepoAppDetailView(app: app, source: source)
						} label: {
							RepoAppRow(app: app)
						}
						.cardRow()
					}
				}
			} else if let error = sources.errors[source.url] {
				EmptyStateView(title: "Couldn't Load", systemImage: "wifi.exclamationmark", message: error)
					.listRowBackground(Color.clear)
			} else {
				ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
			}
		}
		.spectraBackground()
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

	@State private var search = ""

	private var visible: [SourceEntry] {
		search.isEmpty ? entries : entries.filter { $0.app.name.localizedCaseInsensitiveContains(search) }
	}

	var body: some View {
		List(visible) { entry in
			NavigationLink {
				RepoAppDetailView(app: entry.app, source: entry.source)
			} label: {
				RepoAppRow(app: entry.app)
			}
			.cardRow()
		}
		.listStyle(.plain)
		.spectraBackground()
		.searchable(text: $search, prompt: "Search \(entries.count) apps")
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
		.frame(width: 250, height: 128, alignment: .topLeading)
		.background(tint.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

		if let url = news.url {
			Link(destination: url) { card }
		} else {
			card
		}
	}
}
