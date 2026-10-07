import Foundation
import Security

/// A .p12 + .mobileprovision pair imported by the user.
struct SigningCertificate: Codable, Identifiable, Hashable {
	var id: UUID
	/// Common name of the signing certificate, e.g. "Apple Distribution: Jane Appleseed (ABCDE12345)".
	var name: String
	var profileName: String
	var teamName: String
	var teamID: String
	var appIDName: String
	var applicationIdentifier: String
	var created: Date
	var expiration: Date
	var isEnterprise: Bool
	var deviceCount: Int
	var entitlementKeys: [String]
	var nickname: String?

	var displayName: String { nickname?.isEmpty == false ? nickname! : teamName }

	var folder: URL { Paths.certificates.appendingPathComponent(id.uuidString, isDirectory: true) }
	var p12URL: URL { folder.appendingPathComponent("certificate.p12") }
	var profileURL: URL { folder.appendingPathComponent("profile.mobileprovision") }

	var isExpired: Bool { expiration < Date() }

	/// Whether the profile allows any bundle ID (a wildcard App ID like `TEAMID.*`).
	var isWildcard: Bool { applicationIdentifier.hasSuffix(".*") }
}

/// The plist embedded in a CMS-signed .mobileprovision.
struct ProvisioningProfile {
	let plist: [String: Any]

	enum Failure: LocalizedError {
		case unreadable
		var errorDescription: String? { "That provisioning profile couldn't be read." }
	}

	init(url: URL) throws {
		try self.init(data: Data(contentsOf: url))
	}

	init(data: Data) throws {
		guard
			let start = data.range(of: Data("<?xml".utf8)),
			let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
			let plist = try? PropertyListSerialization.propertyList(
				from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil
			) as? [String: Any]
		else { throw Failure.unreadable }
		self.plist = plist
	}

	var name: String { plist["Name"] as? String ?? "Unknown Profile" }
	var teamName: String { plist["TeamName"] as? String ?? "Unknown Team" }
	var teamID: String { (plist["TeamIdentifier"] as? [String])?.first ?? "" }
	var appIDName: String { plist["AppIDName"] as? String ?? "" }
	var creationDate: Date { plist["CreationDate"] as? Date ?? Date() }
	var expirationDate: Date { plist["ExpirationDate"] as? Date ?? Date() }
	var entitlements: [String: Any] { plist["Entitlements"] as? [String: Any] ?? [:] }
	var provisionsAllDevices: Bool { plist["ProvisionsAllDevices"] as? Bool ?? false }
	var devices: [String] { plist["ProvisionedDevices"] as? [String] ?? [] }
	var applicationIdentifier: String { entitlements["application-identifier"] as? String ?? "" }

	/// Common name of the first developer certificate embedded in the profile.
	var certificateName: String? {
		guard
			let der = (plist["DeveloperCertificates"] as? [Data])?.first,
			let cert = SecCertificateCreateWithData(nil, der as CFData)
		else { return nil }
		return SecCertificateCopySubjectSummary(cert) as String?
	}
}

/// Stores certificate passwords in the Keychain, falling back to the certificate folder
/// if the Keychain isn't available (some signing setups strip the keychain entitlement).
enum PasswordVault {
	private static let service = "dev.spectra.SpectraSigner.certificates"

	private static func query(_ account: String) -> [String: Any] {
		[
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
		]
	}

	private static func fallbackURL(_ cert: SigningCertificate) -> URL { cert.folder.appendingPathComponent(".password") }

	static func set(_ password: String, for cert: SigningCertificate) {
		let account = cert.id.uuidString
		SecItemDelete(query(account) as CFDictionary)
		var add = query(account)
		add[kSecValueData as String] = Data(password.utf8)
		add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
		if SecItemAdd(add as CFDictionary, nil) != errSecSuccess {
			try? Data(password.utf8).write(to: fallbackURL(cert), options: [.atomic, .completeFileProtection])
		}
	}

	static func get(for cert: SigningCertificate) -> String {
		var q = query(cert.id.uuidString)
		q[kSecReturnData as String] = true
		q[kSecMatchLimit as String] = kSecMatchLimitOne
		var result: AnyObject?
		if SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
			return String(decoding: data, as: UTF8.self)
		}
		if let data = try? Data(contentsOf: fallbackURL(cert)) {
			return String(decoding: data, as: UTF8.self)
		}
		return ""
	}

	static func delete(for cert: SigningCertificate) {
		SecItemDelete(query(cert.id.uuidString) as CFDictionary)
	}
}
