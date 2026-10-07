import Foundation

/// An app in the library: either an imported (unsigned) bundle, or a signed .ipa ready to install.
struct LibraryApp: Codable, Identifiable, Hashable {
	enum Kind: String, Codable {
		case unsigned
		case signed
	}

	var id: UUID
	var kind: Kind
	var name: String
	var bundleID: String
	var version: String
	var minimumOS: String?
	var date: Date
	var size: Int64
	/// Signed apps: the certificate used.
	var certificateName: String?
	var certificateExpiry: Date?
	/// Signed apps: the unsigned app they were made from.
	var originID: UUID?

	var folder: URL {
		(kind == .unsigned ? Paths.unsigned : Paths.signed).appendingPathComponent(id.uuidString, isDirectory: true)
	}

	var iconURL: URL { folder.appendingPathComponent("icon.png") }

	/// Unsigned apps keep the extracted bundle; signed apps keep the packaged .ipa.
	var payloadURL: URL { folder.appendingPathComponent("Payload", isDirectory: true) }
	var ipaURL: URL { folder.appendingPathComponent("app.ipa") }

	/// A friendly file name for sharing, e.g. "Spectra Signer 1.0.ipa".
	var shareFileName: String {
		let safe = name.replacingOccurrences(of: "/", with: "-")
		return "\(safe) \(version).ipa"
	}
}
