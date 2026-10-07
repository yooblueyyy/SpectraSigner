import Foundation

/// Per-job signing choices. The defaults are editable in Settings → Signing.
struct SignOptions: Codable, Equatable {
	// Per-app overrides (empty = keep original)
	var name = ""
	var bundleID = ""
	var version = ""
	var minimumOS = ""

	// Modifications
	var fileSharing = false
	var removeSupportedDevices = true
	var removeExtensions = false
	var removeWatchApp = false
	var weakInject = true
	var adhoc = false

	// Behaviour
	var installAfterSigning = true
	var deleteUnsignedAfterSigning = false

	/// Only the settings that make sense as defaults (no per-app fields).
	var asDefaults: SignOptions {
		var copy = self
		copy.name = ""
		copy.bundleID = ""
		copy.version = ""
		copy.minimumOS = ""
		return copy
	}

	private static let key = "signOptionsDefaults"

	static var defaults: SignOptions {
		get {
			guard
				let data = UserDefaults.standard.data(forKey: key),
				let options = try? JSONDecoder().decode(SignOptions.self, from: data)
			else { return SignOptions() }
			return options
		}
		set {
			if let data = try? JSONEncoder().encode(newValue.asDefaults) {
				UserDefaults.standard.set(data, forKey: key)
			}
		}
	}
}

/// App-wide preference keys used with @AppStorage.
enum Prefs {
	static let accentColor = "accentColor"
	static let colorScheme = "colorScheme"
	static let compressIPAs = "compressIPAs"
	static let keepAliveAudio = "keepAliveAudio"
	static let librarySort = "librarySort"
	static let manifestService = "manifestService"
}
