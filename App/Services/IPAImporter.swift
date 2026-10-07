import Foundation
import UIKit
import ZIPFoundation

/// Extracts an .ipa / .tipa into the library's Unsigned folder.
enum IPAImporter {
	static func importArchive(at url: URL, progress: Progress? = nil) throws -> LibraryApp {
		let fm = FileManager.default
		let id = UUID()
		let dest = Paths.unsigned.appendingPathComponent(id.uuidString, isDirectory: true)
		try fm.createDirectory(at: dest, withIntermediateDirectories: true)

		do {
			try fm.unzipItem(at: url, to: dest, skipCRC32: true, progress: progress)

			guard let appURL = BundleMetadata.findApp(in: dest) else { throw BundleMetadata.Failure.noApp }

			// Normalise to Payload/<Name>.app so signing always finds it in the same place.
			let payload = dest.appendingPathComponent("Payload", isDirectory: true)
			var finalAppURL = appURL
			if appURL.deletingLastPathComponent().standardizedFileURL != payload.standardizedFileURL {
				try fm.createDirectory(at: payload, withIntermediateDirectories: true)
				finalAppURL = payload.appendingPathComponent(appURL.lastPathComponent)
				try fm.moveItem(at: appURL, to: finalAppURL)
			}

			// Drop anything that isn't the app (e.g. iTunesMetadata.plist, __MACOSX).
			for item in (try? fm.contentsOfDirectory(at: dest, includingPropertiesForKeys: nil)) ?? []
			where item.lastPathComponent != "Payload" {
				try? fm.removeItem(at: item)
			}

			let meta = try BundleMetadata.read(appURL: finalAppURL)
			saveIcon(from: meta.iconURL, to: dest.appendingPathComponent("icon.png"))

			return LibraryApp(
				id: id,
				kind: .unsigned,
				name: meta.name,
				bundleID: meta.bundleID,
				version: meta.version,
				minimumOS: meta.minimumOS,
				date: Date(),
				size: Paths.size(of: dest)
			)
		} catch {
			try? fm.removeItem(at: dest)
			throw error
		}
	}

	/// Re-encodes the icon so the Apple-optimised (CgBI) PNGs inside apps become normal PNGs.
	static func saveIcon(from source: URL?, to dest: URL) {
		guard let source, let image = UIImage(contentsOfFile: source.path), let png = image.pngData() else { return }
		try? png.write(to: dest)
	}
}
