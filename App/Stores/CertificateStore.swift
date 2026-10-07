import Foundation
import Security
import ZSignC

@MainActor
final class CertificateStore: ObservableObject {
	@Published private(set) var certificates: [SigningCertificate] = []
	@Published var selectedID: UUID? {
		didSet { UserDefaults.standard.set(selectedID?.uuidString, forKey: Self.selectedKey) }
	}

	private static let selectedKey = "selectedCertificate"
	private static let file = "certificates"

	init() {
		certificates = Persistence.load([SigningCertificate].self, from: Self.file) ?? []
		certificates.removeAll { !FileManager.default.fileExists(atPath: $0.p12URL.path) }
		selectedID = UserDefaults.standard.string(forKey: Self.selectedKey).flatMap(UUID.init(uuidString:))
	}

	/// The certificate new signing jobs use by default.
	var selected: SigningCertificate? {
		certificates.first { $0.id == selectedID } ?? certificates.first
	}

	enum Failure: LocalizedError {
		case missingFiles
		var errorDescription: String? { "Pick both a .p12 certificate and a .mobileprovision profile." }
	}

	@discardableResult
	func add(p12: URL, profile: URL, password: String, nickname: String? = nil) async throws -> SigningCertificate {
		let fm = FileManager.default
		let id = UUID()
		let folder = Paths.certificates.appendingPathComponent(id.uuidString, isDirectory: true)
		try fm.createDirectory(at: folder, withIntermediateDirectories: true)

		do {
			let p12Dest = folder.appendingPathComponent("certificate.p12")
			let profileDest = folder.appendingPathComponent("profile.mobileprovision")
			try Self.copy(p12, to: p12Dest)
			try Self.copy(profile, to: profileDest)

			let parsed = try ProvisioningProfile(url: profileDest)

			try await Task.detached(priority: .userInitiated) {
				try ZSKSigner.validate(p12: p12Dest.path, password: password, provision: profileDest.path)
			}.value

			let cert = SigningCertificate(
				id: id,
				name: Self.commonName(p12: p12Dest, password: password) ?? parsed.certificateName ?? parsed.name,
				profileName: parsed.name,
				teamName: parsed.teamName,
				teamID: parsed.teamID,
				appIDName: parsed.appIDName,
				applicationIdentifier: parsed.applicationIdentifier,
				created: parsed.creationDate,
				expiration: parsed.expirationDate,
				isEnterprise: parsed.provisionsAllDevices,
				deviceCount: parsed.devices.count,
				entitlementKeys: parsed.entitlements.keys.sorted(),
				nickname: nickname
			)
			PasswordVault.set(password, for: cert)
			certificates.insert(cert, at: 0)
			if selectedID == nil { selectedID = cert.id }
			save()
			return cert
		} catch {
			try? fm.removeItem(at: folder)
			throw error
		}
	}

	func rename(_ cert: SigningCertificate, to nickname: String) {
		guard let index = certificates.firstIndex(where: { $0.id == cert.id }) else { return }
		certificates[index].nickname = nickname
		save()
	}

	func delete(_ cert: SigningCertificate) {
		PasswordVault.delete(for: cert)
		try? FileManager.default.removeItem(at: cert.folder)
		certificates.removeAll { $0.id == cert.id }
		if selectedID == cert.id { selectedID = certificates.first?.id }
		save()
	}

	func deleteAll() {
		for cert in certificates { delete(cert) }
	}

	private func save() { Persistence.save(certificates, to: Self.file) }

	private static func copy(_ source: URL, to dest: URL) throws {
		let scoped = source.startAccessingSecurityScopedResource()
		defer { if scoped { source.stopAccessingSecurityScopedResource() } }
		try? FileManager.default.removeItem(at: dest)
		try FileManager.default.copyItem(at: source, to: dest)
	}

	private static func commonName(p12: URL, password: String) -> String? {
		guard let data = try? Data(contentsOf: p12) else { return nil }
		var items: CFArray?
		let options = [kSecImportExportPassphrase as String: password] as CFDictionary
		guard
			SecPKCS12Import(data as CFData, options, &items) == errSecSuccess,
			let first = (items as? [[String: Any]])?.first,
			let identityRef = first[kSecImportItemIdentity as String]
		else { return nil }
		let identity = identityRef as! SecIdentity
		var cert: SecCertificate?
		guard SecIdentityCopyCertificate(identity, &cert) == errSecSuccess, let cert else { return nil }
		return SecCertificateCopySubjectSummary(cert) as String?
	}
}
