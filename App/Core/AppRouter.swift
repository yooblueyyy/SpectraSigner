import SwiftUI

/// Cross-tab navigation and app-wide alerts.
@MainActor
final class AppRouter: ObservableObject {
	enum Tab: Hashable {
		case discover, sources, library, settings
	}

	struct PendingCertificate: Identifiable {
		let id = UUID()
		var p12: URL?
		var profile: URL?
	}

	@Published var tab: Tab = .discover
	@Published var alert: String?
	@Published var pendingSourceURL: String?
	@Published var pendingCertificate: PendingCertificate?

	func show(_ error: Error) {
		alert = error.localizedDescription
	}
}
