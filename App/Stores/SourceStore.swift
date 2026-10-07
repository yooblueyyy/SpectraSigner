import Foundation

struct SavedSource: Codable, Identifiable, Hashable {
	var url: URL
	var name: String
	var iconURL: URL?
	var added: Date

	var id: URL { url }
}

/// An app listed by a source.
struct SourceEntry: Identifiable {
	let source: SavedSource
	let app: RepoApp
	var id: String { source.url.absoluteString + "#" + app.id }
}

struct SuggestedSource: Identifiable {
	let name: String
	let url: String
	var id: String { url }
}

@MainActor
final class SourceStore: ObservableObject {
	@Published private(set) var sources: [SavedSource] = []
	@Published private(set) var repositories: [URL: Repository] = [:]
	@Published private(set) var loading: Set<URL> = []
	@Published private(set) var errors: [URL: String] = [:]

	private static let file = "sources"

	/// Shown on the Add Source screen.
	static let suggestions: [SuggestedSource] = [
		SuggestedSource(name: "AltStore", url: "https://apps.altstore.io"),
		SuggestedSource(name: "UTM", url: "https://alt.getutm.app"),
		SuggestedSource(name: "Aidoku", url: "https://raw.githubusercontent.com/Aidoku/Aidoku/altstore/apps.json"),
	]

	init() {
		sources = Persistence.load([SavedSource].self, from: Self.file) ?? []
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
		save()
	}

	func move(from offsets: IndexSet, to destination: Int) {
		sources.move(fromOffsets: offsets, toOffset: destination)
		save()
	}

	func refreshAll() async {
		await withTaskGroup(of: Void.self) { group in
			for source in sources {
				group.addTask { await self.refresh(source) }
			}
		}
	}

	func refresh(_ source: SavedSource) async {
		do {
			let repo = try await fetch(source.url)
			repositories[source.url] = repo
			errors[source.url] = nil
			if let index = sources.firstIndex(of: source), sources[index].name != repo.name || sources[index].iconURL != repo.iconURL {
				sources[index].name = repo.name
				sources[index].iconURL = repo.iconURL
				save()
			}
		} catch {
			errors[source.url] = error.localizedDescription
		}
	}

	/// Every app across all loaded sources, paired with the source it came from.
	var allApps: [SourceEntry] {
		sources.flatMap { source in
			(repositories[source.url]?.apps ?? []).map { SourceEntry(source: source, app: $0) }
		}
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
		do {
			return try JSONDecoder().decode(Repository.self, from: data)
		} catch {
			throw Failure.notASource("It isn't AltStore-style JSON.")
		}
	}

	private func save() { Persistence.save(sources, to: Self.file) }
}
