import Foundation
import UIKit
import ZIPFoundation
import ZSignC

struct SignRequest {
	var app: LibraryApp
	var certificate: SigningCertificate?
	var password: String
	var options: SignOptions
	var icon: UIImage?
	var dylibs: [URL]
}

enum SigningService {
	enum Failure: LocalizedError {
		case noUnsignedCopy, noCertificate, appMissing

		var errorDescription: String? {
			switch self {
			case .noUnsignedCopy: return "The original app is no longer in your library, so it can't be signed again."
			case .noCertificate: return "Add a certificate in Settings first, or turn on ad-hoc signing."
			case .appMissing: return "The signed app couldn't be found."
			}
		}
	}

	/// Copies the unsigned bundle, signs it with zsign and packages a new .ipa in the Signed folder.
	static func sign(_ request: SignRequest, stage: @escaping (String) -> Void) async throws -> LibraryApp {
		try await Task.detached(priority: .userInitiated) {
			try perform(request, stage: { text in DispatchQueue.main.async { stage(text) } })
		}.value
	}

	private static func perform(_ r: SignRequest, stage: (String) -> Void) throws -> LibraryApp {
		let fm = FileManager.default
		guard fm.fileExists(atPath: r.app.payloadURL.path) else { throw Failure.noUnsignedCopy }
		guard r.options.adhoc || r.certificate != nil else { throw Failure.noCertificate }

		stage("Preparing")
		let work = try Paths.makeTemp("sign")
		defer { try? fm.removeItem(at: work) }
		try fm.copyItem(at: r.app.payloadURL, to: work.appendingPathComponent("Payload", isDirectory: true))

		let o = ZSKSignOptions()
		o.appFolder = work.path
		if r.options.adhoc {
			o.adhoc = true
		} else if let cert = r.certificate {
			o.p12Path = cert.p12URL.path
			o.p12Password = r.password
			o.provisionPath = cert.profileURL.path
		}

		func changed(_ value: String, from original: String) -> String? {
			let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
			return trimmed.isEmpty || trimmed == original ? nil : trimmed
		}
		o.displayName = changed(r.options.name, from: r.app.name)
		o.bundleIdentifier = changed(r.options.bundleID, from: r.app.bundleID)
		o.version = changed(r.options.version, from: r.app.version)
		o.minimumOSVersion = changed(r.options.minimumOS, from: r.app.minimumOS ?? "")

		var iconPNG: Data?
		if let icon = r.icon, let png = icon.squared(to: 1024).pngData() {
			let url = work.appendingPathComponent("icon.png")
			try png.write(to: url)
			o.iconPath = url.path
			iconPNG = png
		}

		if !r.dylibs.isEmpty {
			let injectDir = work.appendingPathComponent("inject", isDirectory: true)
			try fm.createDirectory(at: injectDir, withIntermediateDirectories: true)
			var paths: [String] = []
			for dylib in r.dylibs {
				let dest = injectDir.appendingPathComponent(dylib.lastPathComponent)
				try? fm.removeItem(at: dest)
				try fm.copyItem(at: dylib, to: dest)
				paths.append(dest.path)
			}
			o.dylibPaths = paths
			o.weakInject = r.options.weakInject
		}

		o.enableFileSharing = r.options.fileSharing
		o.removeSupportedDevices = r.options.removeSupportedDevices
		o.removeExtensions = r.options.removeExtensions
		o.removeWatchApp = r.options.removeWatchApp

		stage("Signing")
		try ZSKSigner.sign(options: o, log: nil)

		stage("Packaging")
		guard let appURL = BundleMetadata.findApp(in: work) else { throw BundleMetadata.Failure.noApp }
		let meta = try BundleMetadata.read(appURL: appURL)

		let id = UUID()
		let dest = Paths.signed.appendingPathComponent(id.uuidString, isDirectory: true)
		try fm.createDirectory(at: dest, withIntermediateDirectories: true)
		do {
			let compress = UserDefaults.standard.bool(forKey: Prefs.compressIPAs)
			try fm.zipItem(
				at: work.appendingPathComponent("Payload", isDirectory: true),
				to: dest.appendingPathComponent("app.ipa"),
				shouldKeepParent: true,
				compressionMethod: compress ? .deflate : .none
			)
			let iconDest = dest.appendingPathComponent("icon.png")
			if let iconPNG {
				try? iconPNG.write(to: iconDest)
			} else {
				try? fm.copyItem(at: r.app.iconURL, to: iconDest)
			}
		} catch {
			try? fm.removeItem(at: dest)
			throw error
		}

		return LibraryApp(
			id: id,
			kind: .signed,
			name: meta.name,
			bundleID: meta.bundleID,
			version: meta.version,
			minimumOS: meta.minimumOS,
			date: Date(),
			size: Paths.size(of: dest.appendingPathComponent("app.ipa")),
			certificateName: r.options.adhoc ? "Ad-hoc" : r.certificate?.displayName,
			certificateExpiry: r.options.adhoc ? nil : r.certificate?.expiration,
			originID: r.app.id
		)
	}
}
