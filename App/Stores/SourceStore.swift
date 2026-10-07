import CryptoKit
import Foundation

struct SavedSource: Codable, Identifiable, Hashable {
	var url: URL
	var name: String
	var iconURL: URL?
	var added: Date
	var category: String?
	var isBuiltin: Bool?

	var id: URL { url }
	var displayCategory: String { category ?? SourceStore.userCategory }
}

/// An app listed by a source.
struct SourceEntry: Identifiable {
	let source: SavedSource
	let app: RepoApp
	var id: String { source.url.absoluteString + "#" + app.id }
}

/// A source shipped with the app (Resources/BuiltinSources.json).
struct BuiltinSource: Decodable {
	let name: String
	let url: URL
	let category: String
}

@MainActor
final class SourceStore: ObservableObject {
	@Published private(set) var sources: [SavedSource] = []
	@Published private(set) var repositories: [URL: Repository] = [:]
	@Published private(set) var loading: Set<URL> = []
	@Published private(set) var errors: [URL: String] = [:]
	@Published private(set) var isRefreshing = false
	@Published private(set) var lastRefresh: Date?

	private static let file = "sources"
	private static let builtinInstalledKey = "builtinSourcesInstalled.v1"
	static let userCategory = "Added by You"

	/// Display order for source categories.
	static let categoryOrder = [
		"Official", "Emulators", "Games", "Media", "Reading", "Developer",
		"Customization", "Social", "Utilities", "Health", "AI", "Finance", userCategory,
	]

	static let builtin: [BuiltinSource] = {
		guard
			let url = Bundle.main.url(forResource: "BuiltinSources", withExtension: "json"),
			let data = try? Data(contentsOf: url),
			let list = try? JSONDecoder().decode([BuiltinSource].self, from: data)
		else { return [] }
		return list
	}()

	init() {
		sources = Persistence.load([SavedSource].self, from: Self.file) ?? []
		if !UserDefaults.standard.bool(forKey: Self.builtinInstalledKey) {
			installBuiltins()
			UserDefaults.standard.set(true, forKey: Self.builtinInstalledKey)
		}
		loadCache()
	}

	enum Failure: LocalizedError {
		case invalidURL, duplicate, notASource(String)

		var errorDescription: String? {
			switch self {
			case .invalidURL: return "That doesn't look like a valid URL."
			case .duplicate: return "You've already added this source."
			case .notASource(let reason): return "This URL isn't a valid source. \(reason)"
			}
		}
	}

	// MARK: - Built-in sources

	var missingBuiltinCount: Int {
		let present = Set(sources.map(\.url))
		return Self.builtin.filter { !present.contains($0.url) }.count
	}

	/// Adds any built-in sources that aren't in the list (e.g. after the user removed them).
	func installBuiltins() {
		let present = Set(sources.map(\.url))
		for item in Self.builtin where !present.contains(item.url) {
			sources.append(SavedSource(url: item.url, name: item.name, iconURL: nil, added: Date(), category: item.category, isBuiltin: true))
		}
		save()
	}

	func restoreBuiltins() async {
		installBuiltins()
		await refreshAll()
	}

	// MARK: - Editing

	static func normalize(_ text: String) -> URL? {
		var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !raw.isEmpty else { return nil }
		if !raw.lowercased().hasPrefix("http") { raw = "https://" + raw }
		guard let url = URL(string: raw), url.host != nil else { return nil }
		return url
	}

	@discardableResult
	func add(_ text: String) async throws -> SavedSource {
		guard let url = Self.normalize(text) else { throw Failure.invalidURL }
		guard !sources.contains(where: { $0.url == url }) else { throw Failure.duplicate }
		let repo = try await fetch(url)
		let source = SavedSource(url: url, name: repo.name, iconURL: repo.iconURL, added: Date())
		sources.append(source)
		repositories[url] = repo
		save()
		return source
	}

	func remove(_ source: SavedSource) {
		sources.removeAll { $0.url == source.url }
		repositories[source.url] = nil
		errors[source.url] = nil
		try? FileManager.default.removeItem(at: cacheURL(for: source.url))
		save()
	}

	func removeAll() {
		for source in sources { try? FileManager.default.removeItem(at: cacheURL(for: source.url)) }
		sources = []
		repositories = [:]
		errors = [:]
		save()
	}

	// MARK: - Loading

	/// Refreshes every source, eight at a time.
	func refreshAll() async {
		guard !isRefreshing else { return }
		isRefreshing = true
		defer {
			isRefreshing = false
			lastRefresh = Date()
		}
		let list = sources
		await withTaskGroup(of: Void.self) { group in
			var iterator = list.makeIterator()
			for _ in 0..<8 {
				guard let source = iterator.next() else { break }
				group.addTask { await self.refresh(source) }
			}
			while await group.next() != nil {
				if let source = iterator.next() {
					group.addTask { await self.refresh(source) }
				}
			}
		}
	}

	/// Refreshes when the data is missing or more than an hour old.
	func refreshIfStale() async {
		if let lastRefresh, Date().timeIntervalSince(lastRefresh) < 3600 { return }
		await refreshAll()
	}

	func refresh(_ source: SavedSource) async {
		do {
			let repo = try await fetch(source.url)
			repositories[source.url] = repo
			errors[source.url] = nil
			if let index = sources.firstIndex(where: { $0.url == source.url }),
			   sources[index].name != repo.name || sources[index].iconURL != repo.iconURL {
				sources[index].name = repo.name
				sources[index].iconURL = repo.iconURL
				save()
			}
		} catch {
			errors[source.url] = error.localizedDescription
		}
	}

	/// Every app across all loaded sources, in source order.
	var allApps: [SourceEntry] {
		sources.flatMap { source in
			(repositories[source.url]?.apps ?? []).map { SourceEntry(source: source, app: $0) }
		}
	}

	var totalApps: Int { repositories.values.reduce(0) { $0 + $1.apps.count } }

	/// Sources grouped by category, in display order.
	var groupedSources: [(category: String, sources: [SavedSource])] {
		let groups = Dictionary(grouping: sources, by: \.displayCategory)
		return groups.keys
			.sorted { (Self.categoryOrder.firstIndex(of: $0) ?? 99) < (Self.categoryOrder.firstIndex(of: $1) ?? 99) }
			.map { (category: $0, sources: groups[$0] ?? []) }
	}

	private func fetch(_ url: URL) async throws -> Repository {
		loading.insert(url)
		defer { loading.remove(url) }
		var request = URLRequest(url: url)
		request.cachePolicy = .reloadIgnoringLocalCacheData
		request.timeoutInterval = 30
		let (data, response) = try await URLSession.shared.data(for: request)
		if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
			throw Failure.notASource("The server responded with \(http.statusCode).")
		}
		let repo: Repository
		do {
			repo = try await Task.detached(priority: .utility) {
				try JSONDecoder().decode(Repository.self, from: data)
			}.value
		} catch {
			throw Failure.notASource("It isn't AltStore-style JSON.")
		}
		try? FileManager.default.createDirectory(at: Self.cacheFolder, withIntermediateDirectories: true)
		try? data.write(to: cacheURL(for: url), options: .atomic)
		return repo
	}

	// MARK: - Cache

	private nonisolated static var cacheFolder: URL { Paths.database.appendingPathComponent("SourceCache", isDirectory: true) }

	private nonisolated func cacheURL(for url: URL) -> URL {
		let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
		return Self.cacheFolder.appendingPathComponent("\(digest).json")
	}

	/// Shows the last downloaded copy of every source immediately, before the network refresh.
	private func loadCache() {
		let urls = sources.map(\.url)
		Task.detached(priority: .userInitiated) { [weak self] in
			guard let self else { return }
			var cached: [URL: Repository] = [:]
			for url in urls {
				if let data = try? Data(contentsOf: self.cacheURL(for: url)),
				   let repo = try? JSONDecoder().decode(Repository.self, from: data) {
					cached[url] = repo
				}
			}
			await MainActor.run {
				for (url, repo) in cached where self.repositories[url] == nil {
					self.repositories[url] = repo
				}
			}
		}
	}

	private func save() { Persistence.save(sources, to: Self.file) }
}
