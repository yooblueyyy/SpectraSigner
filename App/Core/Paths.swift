import Foundation

/// Where Spectra Signer keeps everything on disk.
///
/// User-visible files (apps, certificates) live under Documents so they show up in the Files app;
/// the JSON databases live in Application Support.
enum Paths {
	private static let fm = FileManager.default

	static var documents: URL { fm.urls(for: .documentDirectory, in: .userDomainMask)[0] }
	static var root: URL { documents.appendingPathComponent("Spectra", isDirectory: true) }
	static var unsigned: URL { root.appendingPathComponent("Unsigned", isDirectory: true) }
	static var signed: URL { root.appendingPathComponent("Signed", isDirectory: true) }
	static var certificates: URL { root.appendingPathComponent("Certificates", isDirectory: true) }

	static var database: URL {
		fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("Spectra", isDirectory: true)
	}

	static var temp: URL { fm.temporaryDirectory.appendingPathComponent("Spectra", isDirectory: true) }

	static func prepare() {
		for dir in [unsigned, signed, certificates, database, temp] {
			try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
		}
	}

	/// A fresh, empty directory inside the temp folder.
	static func makeTemp(_ prefix: String) throws -> URL {
		let url = temp.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
		try fm.createDirectory(at: url, withIntermediateDirectories: true)
		return url
	}

	static func clearTemp() {
		try? fm.removeItem(at: temp)
		try? fm.removeItem(at: documents.appendingPathComponent("Inbox", isDirectory: true))
		try? fm.createDirectory(at: temp, withIntermediateDirectories: true)
	}

	/// Total size of a file or directory tree in bytes.
	static func size(of url: URL) -> Int64 {
		var isDir: ObjCBool = false
		guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
		guard isDir.boolValue else {
			return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
		}
		var total: Int64 = 0
		let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
		if let e = fm.enumerator(at: url, includingPropertiesForKeys: keys) {
			for case let file as URL in e {
				let values = try? file.resourceValues(forKeys: Set(keys))
				if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
			}
		}
		return total
	}
}

/// Tiny JSON file persistence for the stores.
enum Persistence {
	private static func url(_ name: String) -> URL { Paths.database.appendingPathComponent("\(name).json") }

	static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
		guard let data = try? Data(contentsOf: url(name)) else { return nil }
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		return try? decoder.decode(T.self, from: data)
	}

	static func save<T: Encodable>(_ value: T, to name: String) {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		guard let data = try? encoder.encode(value) else { return }
		try? FileManager.default.createDirectory(at: Paths.database, withIntermediateDirectories: true)
		try? data.write(to: url(name), options: .atomic)
	}
}
