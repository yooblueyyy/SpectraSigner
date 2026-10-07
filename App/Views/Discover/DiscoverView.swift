import SwiftUI

struct DiscoverView: View {
	@EnvironmentObject private var sources: SourceStore

	@State private var search = ""

	private var entries: [SourceEntry] { sources.allApps }

	/// A stable-per-day pick of eye-catching apps (ones with screenshots or a tint colour).
	private var featured: [SourceEntry] {
		let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
		func score(_ e: SourceEntry) -> Int {
			e.app.id.unicodeScalars.reduce(day) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF }
		}
		var seenSources = Set<URL>()
		return entries
			.filter { !$0.app.screenshots.isEmpty || $0.app.tintColor != nil }
			.filter { $0.app.iconURL != nil }
			.sorted { score($0) < score($1) }
			.filter { seenSources.insert($0.source.url).inserted }
			.prefix(6)
			.map { $0 }
	}

	private var shelves: [(category: String, entries: [SourceEntry])] {
		let groups = Dictionary(grouping: entries, by: { $0.source.displayCategory })
		return SourceStore.categoryOrder.compactMap { category in
			guard let list = groups[category], !list.isEmpty else { return nil }
			return (category: category, entries: list)
		}
	}

	private var searchResults: [SourceEntry] {
		entries.filter {
			$0.app.name.localizedCaseInsensitiveContains(search)
				|| ($0.app.developerName ?? "").localizedCaseInsensitiveContains(search)
				|| ($0.app.subtitle ?? "").localizedCaseInsensitiveContains(search)
		}
	}

	var body: some View {
		NavigationStack {
			Group {
				if !search.isEmpty {
					List(searchResults) { entry in
						NavigationLink {
							RepoAppDetailView(app: entry.app, source: entry.source)
						} label: {
							RepoAppRow(app: entry.app)
						}
						.cardRow()
					}
					.listStyle(.plain)
					.spectraBackground()
					.overlay {
						if searchResults.isEmpty {
							EmptyStateView(title: "No Results", systemImage: "magnifyingglass", message: "Nothing matches “\(search)”.")
						}
					}
				} else {
					ScrollView {
						VStack(alignment: .leading, spacing: 30) {
							summary

							if entries.isEmpty {
								loadingCard
							} else {
								if !featured.isEmpty {
									FeaturedCarousel(entries: featured)
								}
								ForEach(shelves, id: \.category) { shelf in
									AppShelf(category: shelf.category, entries: shelf.entries)
								}
							}
						}
						.padding(.vertical, 12)
					}
					.background(AuroraBackground())
					.refreshable { await sources.refreshAll() }
				}
			}
			.navigationTitle("Discover")
			.searchable(text: $search, prompt: "Apps, games and more")
		}
	}

	private var summary: some View {
		HStack(spacing: 10) {
			StatTile(value: "\(sources.totalApps)", label: "Apps", systemImage: "square.grid.2x2.fill")
			StatTile(value: "\(sources.sources.count)", label: "Sources", systemImage: "globe", tint: Spectra.colors[4])
			StatTile(
				value: sources.isRefreshing ? "Updating" : "Live",
				label: sources.lastRefresh.map { "Updated \($0.formatted(.relative(presentation: .named)))" } ?? "Cached",
				systemImage: sources.isRefreshing ? "arrow.triangle.2.circlepath" : "bolt.fill",
				tint: Spectra.colors[3]
			)
		}
		.padding(.horizontal, 16)
	}

	private var loadingCard: some View {
		VStack(spacing: 14) {
			SpectraRing(progress: nil, size: 64, lineWidth: 6) { EmptyView() }
			Text("Loading sources…").font(.headline)
			Text("Fetching apps from \(sources.sources.count) sources.")
				.font(.subheadline)
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity)
		.glassCard(padding: 28)
		.padding(.horizontal, 16)
	}
}

// MARK: - Featured

private struct FeaturedCarousel: View {
	let entries: [SourceEntry]
	@State private var page = 0

	var body: some View {
		VStack(spacing: 10) {
			TabView(selection: $page) {
				ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
					NavigationLink {
						RepoAppDetailView(app: entry.app, source: entry.source)
					} label: {
						FeaturedCard(entry: entry)
					}
					.buttonStyle(.plain)
					.padding(.horizontal, 16)
					.tag(index)
				}
			}
			.tabViewStyle(.page(indexDisplayMode: .never))
			.frame(height: 250)

			HStack(spacing: 6) {
				ForEach(entries.indices, id: \.self) { index in
					Capsule()
						.fill(index == page ? Color.accentColor : Color.secondary.opacity(0.3))
						.frame(width: index == page ? 18 : 6, height: 6)
				}
			}
			.animation(.spring(response: 0.3), value: page)
		}
	}
}

private struct FeaturedCard: View {
	let entry: SourceEntry

	private var tint: Color { Color(hex: entry.app.tintColor) ?? .accentColor }

	var body: some View {
		ZStack(alignment: .bottomLeading) {
			// Backdrop: tint gradient with an oversized, blurred copy of the icon.
			LinearGradient(colors: [tint, tint.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
			AppIconView(url: entry.app.iconURL, size: 260)
				.blur(radius: 40)
				.opacity(0.55)
				.offset(x: 150, y: -40)

			VStack(alignment: .leading, spacing: 10) {
				Text(entry.source.displayCategory.uppercased())
					.font(.caption.weight(.bold))
					.foregroundStyle(.white.opacity(0.8))
				Spacer()
				HStack(spacing: 14) {
					AppIconView(url: entry.app.iconURL, size: 64)
						.shadow(color: .black.opacity(0.25), radius: 10, y: 4)
					VStack(alignment: .leading, spacing: 3) {
						Text(entry.app.name)
							.font(.title3.weight(.bold))
							.foregroundStyle(.white)
							.lineLimit(1)
						Text(entry.app.subtitle ?? entry.app.developerName ?? entry.source.name)
							.font(.subheadline)
							.foregroundStyle(.white.opacity(0.85))
							.lineLimit(2)
					}
					Spacer(minLength: 0)
				}
			}
			.padding(20)
		}
		.frame(height: 240)
		.clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
		.shadow(color: tint.opacity(0.35), radius: 18, y: 8)
	}
}

// MARK: - Shelves

private struct AppShelf: View {
	let category: String
	let entries: [SourceEntry]

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			ShelfHeader(title: category, subtitle: "\(entries.count) apps") {
				AppListView(title: category, entries: entries)
			}

			// Three rows per column, App Store style.
			ScrollView(.horizontal, showsIndicators: false) {
				LazyHGrid(rows: Array(repeating: GridItem(.fixed(68), spacing: 10), count: min(3, entries.count)), spacing: 14) {
					ForEach(entries.prefix(24)) { entry in
						NavigationLink {
							RepoAppDetailView(app: entry.app, source: entry.source)
						} label: {
							CompactAppCell(app: entry.app)
						}
						.buttonStyle(.plain)
					}
				}
				.padding(.horizontal, 20)
			}
		}
	}
}

private struct CompactAppCell: View {
	let app: RepoApp

	var body: some View {
		HStack(spacing: 12) {
			AppIconView(url: app.iconURL, size: 56)
			VStack(alignment: .leading, spacing: 2) {
				Text(app.name).font(.subheadline.weight(.semibold)).lineLimit(1)
				Text(app.subtitle ?? app.developerName ?? app.bundleIdentifier)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(2)
			}
			Spacer(minLength: 6)
			GetButton(app: app)
		}
		.frame(width: 300, height: 68)
	}
}
