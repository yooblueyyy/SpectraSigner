import Foundation

// AltStore-compatible source format. Real-world sources are inconsistent, so everything
// decodes leniently: bad apps are skipped instead of failing the whole source.

struct Repository: Decodable {
	var name: String
	var identifier: String?
	var subtitle: String?
	var description: String?
	var iconURL: URL?
	var headerURL: URL?
	var website: URL?
	var tintColor: String?
	var apps: [RepoApp]
	var news: [RepoNews]

	private enum CodingKeys: String, CodingKey {
		case name, identifier, subtitle, description, iconURL, headerURL, website, tintColor, apps, news
	}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		name = c.lenientString(.name) ?? "Unnamed Source"
		identifier = c.lenientString(.identifier)
		subtitle = c.lenientString(.subtitle)
		description = c.lenientString(.description)
		iconURL = c.lenientURL(.iconURL)
		headerURL = c.lenientURL(.headerURL)
		website = c.lenientURL(.website)
		tintColor = c.lenientString(.tintColor)
		apps = (try? c.decode(LossyArray<RepoApp>.self, forKey: .apps).elements) ?? []
		news = (try? c.decode(LossyArray<RepoNews>.self, forKey: .news).elements) ?? []
	}
}

struct RepoApp: Decodable, Identifiable, Hashable {
	var name: String
	var bundleIdentifier: String
	var developerName: String?
	var subtitle: String?
	var localizedDescription: String?
	var iconURL: URL?
	var tintColor: String?
	var category: String?
	var screenshots: [URL]
	var versions: [RepoVersion]

	// Legacy single-version fields
	private var legacyVersion: String?
	private var legacyDate: String?
	private var legacyDownloadURL: URL?
	private var legacySize: Int?
	private var legacyNotes: String?

	var id: String { "\(bundleIdentifier)|\(downloadURL?.absoluteString ?? name)" }

	var latest: RepoVersion? {
		if let first = versions.first { return first }
		guard let url = legacyDownloadURL else { return nil }
		return RepoVersion(version: legacyVersion ?? "", date: legacyDate, localizedDescription: legacyNotes, downloadURL: url, size: legacySize, minOSVersion: nil)
	}

	var version: String? { latest?.version }
	var downloadURL: URL? { latest?.downloadURL }
	var size: Int? { latest?.size }

	static func == (lhs: RepoApp, rhs: RepoApp) -> Bool { lhs.id == rhs.id }
	func hash(into hasher: inout Hasher) { hasher.combine(id) }

	private enum CodingKeys: String, CodingKey {
		case name, bundleIdentifier, developerName, subtitle, localizedDescription, iconURL, tintColor, category
		case screenshots, screenshotURLs, versions
		case version, versionDate, downloadURL, size, versionDescription
	}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		guard let name = c.lenientString(.name) else {
			throw DecodingError.keyNotFound(CodingKeys.name, .init(codingPath: c.codingPath, debugDescription: "App has no name"))
		}
		self.name = name
		bundleIdentifier = c.lenientString(.bundleIdentifier) ?? name
		developerName = c.lenientString(.developerName)
		subtitle = c.lenientString(.subtitle)
		localizedDescription = c.lenientString(.localizedDescription)
		iconURL = c.lenientURL(.iconURL)
		tintColor = c.lenientString(.tintColor)
		category = c.lenientString(.category)
		versions = (try? c.decode(LossyArray<RepoVersion>.self, forKey: .versions).elements) ?? []

		legacyVersion = c.lenientString(.version)
		legacyDate = c.lenientString(.versionDate)
		legacyDownloadURL = c.lenientURL(.downloadURL)
		legacySize = c.lenientInt(.size)
		legacyNotes = c.lenientString(.versionDescription)

		var shots: [URL] = []
		if let list = try? c.decode(LossyArray<Screenshot>.self, forKey: .screenshots) {
			shots = list.elements.compactMap(\.url)
		} else if let byDevice = try? c.decode([String: LossyArray<Screenshot>].self, forKey: .screenshots) {
			shots = (byDevice["iphone"] ?? byDevice.values.first)?.elements.compactMap(\.url) ?? []
		}
		if shots.isEmpty, let legacy = try? c.decode(LossyArray<Screenshot>.self, forKey: .screenshotURLs) {
			shots = legacy.elements.compactMap(\.url)
		}
		screenshots = shots
	}
}

struct RepoVersion: Decodable, Hashable {
	var version: String
	var date: String?
	var localizedDescription: String?
	var downloadURL: URL
	var size: Int?
	var minOSVersion: String?

	init(version: String, date: String?, localizedDescription: String?, downloadURL: URL, size: Int?, minOSVersion: String?) {
		self.version = version
		self.date = date
		self.localizedDescription = localizedDescription
		self.downloadURL = downloadURL
		self.size = size
		self.minOSVersion = minOSVersion
	}

	private enum CodingKeys: String, CodingKey {
		case version, date, localizedDescription, downloadURL, size, minOSVersion
	}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		guard let url = c.lenientURL(.downloadURL) else {
			throw DecodingError.keyNotFound(CodingKeys.downloadURL, .init(codingPath: c.codingPath, debugDescription: "Version has no download URL"))
		}
		downloadURL = url
		version = c.lenientString(.version) ?? ""
		date = c.lenientString(.date)
		localizedDescription = c.lenientString(.localizedDescription)
		size = c.lenientInt(.size)
		minOSVersion = c.lenientString(.minOSVersion)
	}

	/// Parses the many date styles sources use.
	var parsedDate: Date? { RepoDate.parse(date) }
}

struct RepoNews: Decodable, Identifiable, Hashable {
	var id: String
	var title: String
	var caption: String?
	var date: String?
	var tintColor: String?
	var imageURL: URL?
	var url: URL?

	private enum CodingKeys: String, CodingKey {
		case identifier, title, caption, date, tintColor, imageURL, url
	}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		guard let title = c.lenientString(.title) else {
			throw DecodingError.keyNotFound(CodingKeys.title, .init(codingPath: c.codingPath, debugDescription: "News has no title"))
		}
		self.title = title
		id = c.lenientString(.identifier) ?? UUID().uuidString
		caption = c.lenientString(.caption)
		date = c.lenientString(.date)
		tintColor = c.lenientString(.tintColor)
		imageURL = c.lenientURL(.imageURL)
		url = c.lenientURL(.url)
	}
}

/// Screenshots are either plain URL strings or `{ "imageURL": ... }` objects.
private struct Screenshot: Decodable {
	var url: URL?

	private enum CodingKeys: String, CodingKey { case imageURL }

	init(from decoder: Decoder) throws {
		if let string = try? decoder.singleValueContainer().decode(String.self) {
			url = URL(string: string)
		} else {
			url = try decoder.container(keyedBy: CodingKeys.self).lenientURL(.imageURL)
		}
	}
}

enum RepoDate {
	private static let iso: ISO8601DateFormatter = {
		let f = ISO8601DateFormatter()
		f.formatOptions = [.withInternetDateTime]
		return f
	}()

	private static let isoFractional: ISO8601DateFormatter = {
		let f = ISO8601DateFormatter()
		f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return f
	}()

	private static let dayOnly: DateFormatter = {
		let f = DateFormatter()
		f.locale = Locale(identifier: "en_US_POSIX")
		f.dateFormat = "yyyy-MM-dd"
		return f
	}()

	static func parse(_ string: String?) -> Date? {
		guard let string, !string.isEmpty else { return nil }
		return iso.date(from: string) ?? isoFractional.date(from: string) ?? dayOnly.date(from: String(string.prefix(10)))
	}
}

// MARK: - Lenient decoding helpers

struct LossyArray<Element: Decodable>: Decodable {
	var elements: [Element]

	private struct Skip: Decodable {
		init(from decoder: Decoder) throws {}
	}

	init(from decoder: Decoder) throws {
		var c = try decoder.unkeyedContainer()
		var out: [Element] = []
		while !c.isAtEnd {
			if let element = try? c.decode(Element.self) {
				out.append(element)
			} else if (try? c.decode(Skip.self)) == nil {
				break
			}
		}
		elements = out
	}
}

extension KeyedDecodingContainer {
	func lenientString(_ key: Key) -> String? {
		if let s = try? decodeIfPresent(String.self, forKey: key) { return s.isEmpty ? nil : s }
		if let d = try? decodeIfPresent(Double.self, forKey: key) {
			return d.rounded() == d ? String(Int(d)) : String(d)
		}
		return nil
	}

	func lenientURL(_ key: Key) -> URL? {
		guard let raw = lenientString(key)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
		if let url = URL(string: raw) { return url }
		return raw.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap { URL(string: $0) }
	}

	func lenientInt(_ key: Key) -> Int? {
		if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
		if let d = try? decodeIfPresent(Double.self, forKey: key) { return Int(d) }
		if let s = try? decodeIfPresent(String.self, forKey: key) { return Int(s) }
		return nil
	}
}
