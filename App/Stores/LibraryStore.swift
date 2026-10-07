import Foundation

@MainActor
final class LibraryStore: ObservableObject {
	struct ImportJob: Identifiable {
		let id = UUID()
		let name: String
		let progress = Progress(totalUnitCount: 100)
	}

	@Published private(set) var apps: [LibraryApp] = []
	@Published private(set) var imports: [ImportJob] = []

	private static let file = "library"

	init() {
		apps = Persistence.load([LibraryApp].self, from: Self.file) ?? []
		apps.removeAll { !FileManager.default.fileExists(atPath: $0.folder.path) }
	}

	var unsigned: [LibraryApp] { apps.filter { $0.kind == .unsigned } }
	var signed: [LibraryApp] { apps.filter { $0.kind == .signed } }

	func app(_ id: UUID?) -> LibraryApp? {
		guard let id else { return nil }
		return apps.first { $0.id == id }
	}

	/// Imports an .ipa/.tipa. Security-scoped URLs (from Files) are handled here.
	@discardableResult
	func importIPA(at url: URL, deleteSource: Bool = false) async throws -> LibraryApp {
		let job = ImportJob(name: url.deletingPathExtension().lastPathComponent)
		imports.append(job)
		defer { imports.removeAll { $0.id == job.id } }

		let scoped = url.startAccessingSecurityScopedResource()
		defer {
			if scoped { url.stopAccessingSecurityScopedResource() }
			if deleteSource { try? FileManager.default.removeItem(at: url) }
		}

		let progress = job.progress
		let app = try await Task.detached(priority: .userInitiated) {
			try IPAImporter.importArchive(at: url, progress: progress)
		}.value
		apps.insert(app, at: 0)
		save()
		return app
	}

	func add(_ app: LibraryApp) {
		apps.insert(app, at: 0)
		save()
	}

	func delete(_ app: LibraryApp) {
		try? FileManager.default.removeItem(at: app.folder)
		apps.removeAll { $0.id == app.id }
		save()
	}

	func deleteAll(kind: LibraryApp.Kind? = nil) {
		for app in apps where kind == nil || app.kind == kind {
			try? FileManager.default.removeItem(at: app.folder)
		}
		apps.removeAll { kind == nil || $0.kind == kind }
		save()
	}

	private func save() { Persistence.save(apps, to: Self.file) }
}
