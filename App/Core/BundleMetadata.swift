import Foundation

/// Information read from an `.app` bundle's Info.plist.
struct BundleMetadata {
	var name: String
	var bundleID: String
	var version: String
	var build: String?
	var minimumOS: String?
	var iconURL: URL?

	enum Failure: LocalizedError {
		case noApp, noInfoPlist

		var errorDescription: String? {
			switch self {
			case .noApp: return "This file doesn't contain an app. Make sure it's a valid .ipa."
			case .noInfoPlist: return "The app is missing its Info.plist."
			}
		}
	}

	/// Finds `Payload/<Name>.app` inside an extracted archive, or a bare `<Name>.app` at the top level.
	static func findApp(in folder: URL) -> URL? {
		let fm = FileManager.default
		for dir in [folder.appendingPathComponent("Payload", isDirectory: true), folder] {
			let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
			if let app = items.first(where: { $0.pathExtension.lowercased() == "app" }) {
				return app
			}
		}
		return nil
	}

	static func read(appURL: URL) throws -> BundleMetadata {
		let plistURL = appURL.appendingPathComponent("Info.plist")
		guard
			let data = try? Data(contentsOf: plistURL),
			let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
		else { throw Failure.noInfoPlist }

		let name = [info["CFBundleDisplayName"], info["CFBundleName"], info["CFBundleExecutable"]]
			.compactMap { $0 as? String }
			.first { !$0.isEmpty } ?? appURL.deletingPathExtension().lastPathComponent

		return BundleMetadata(
			name: name,
			bundleID: info["CFBundleIdentifier"] as? String ?? "unknown",
			version: info["CFBundleShortVersionString"] as? String ?? info["CFBundleVersion"] as? String ?? "1.0",
			build: info["CFBundleVersion"] as? String,
			minimumOS: info["MinimumOSVersion"] as? String,
			iconURL: findIcon(in: appURL, info: info)
		)
	}

	/// Picks the largest loose PNG named by the bundle's icon keys.
	/// Apps that keep icons only in Assets.car return nil.
	private static func findIcon(in appURL: URL, info: [String: Any]) -> URL? {
		var names: [String] = []
		for key in ["CFBundleIcons", "CFBundleIcons~ipad"] {
			if
				let icons = info[key] as? [String: Any],
				let primary = icons["CFBundlePrimaryIcon"] as? [String: Any]
			{
				names += primary["CFBundleIconFiles"] as? [String] ?? []
				if let iconName = primary["CFBundleIconName"] as? String { names.append(iconName) }
			}
		}
		names += info["CFBundleIconFiles"] as? [String] ?? []
		if let single = info["CFBundleIconFile"] as? String { names.append(single) }
		names.append("AppIcon")

		let files = (try? FileManager.default.contentsOfDirectory(at: appURL, includingPropertiesForKeys: [.fileSizeKey])) ?? []
		let pngs = files.filter { $0.pathExtension.lowercased() == "png" }

		for name in names {
			let base = (name as NSString).deletingPathExtension
			let matches = pngs.filter { $0.lastPathComponent.hasPrefix(base) }
			let best = matches.max { lhs, rhs in
				let l = (try? lhs.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
				let r = (try? rhs.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
				return l < r
			}
			if let best { return best }
		}
		return nil
	}
}
