import Foundation

/// Downloads .ipa files and imports them into the library when done.
@MainActor
final class DownloadManager: NSObject, ObservableObject {
	struct Item: Identifiable {
		let id: UUID
		let name: String
		let url: URL
		var progress: Double = 0
		var received: Int64 = 0
		var expected: Int64 = 0
		var task: URLSessionDownloadTask?
	}

	@Published private(set) var items: [Item] = []
	@Published var lastError: String?

	weak var library: LibraryStore?

	private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

	func item(for url: URL) -> Item? { items.first { $0.url == url } }

	func download(_ url: URL, name: String) {
		guard item(for: url) == nil else { return }
		let id = UUID()
		let task = session.downloadTask(with: url)
		task.taskDescription = id.uuidString
		items.append(Item(id: id, name: name, url: url, task: task))
		task.resume()
	}

	func cancel(_ item: Item) {
		item.task?.cancel()
		items.removeAll { $0.id == item.id }
	}

	fileprivate func update(_ id: String?, received: Int64, expected: Int64) {
		guard let index = items.firstIndex(where: { $0.id.uuidString == id }) else { return }
		items[index].received = received
		items[index].expected = expected
		items[index].progress = expected > 0 ? Double(received) / Double(expected) : 0
	}

	fileprivate func finish(_ id: String?, file: URL?, error: String?) async {
		guard let index = items.firstIndex(where: { $0.id.uuidString == id }) else {
			if let file { try? FileManager.default.removeItem(at: file) }
			return
		}
		let item = items[index]
		defer { items.removeAll { $0.id == item.id } }

		if let error {
			lastError = "\(item.name): \(error)"
			return
		}
		guard let file, let library else { return }
		do {
			try await library.importIPA(at: file, deleteSource: true)
		} catch {
			lastError = "\(item.name): \(error.localizedDescription)"
		}
	}
}

extension DownloadManager: URLSessionDownloadDelegate {
	nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
		let id = downloadTask.taskDescription
		if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
			Task { @MainActor in await self.finish(id, file: nil, error: "The server responded with \(http.statusCode).") }
			return
		}
		// The temporary file is deleted when this method returns, so move it right away.
		let dest = Paths.temp.appendingPathComponent("\(UUID().uuidString).ipa")
		do {
			try FileManager.default.createDirectory(at: Paths.temp, withIntermediateDirectories: true)
			try FileManager.default.moveItem(at: location, to: dest)
			Task { @MainActor in await self.finish(id, file: dest, error: nil) }
		} catch {
			let message = error.localizedDescription
			Task { @MainActor in await self.finish(id, file: nil, error: message) }
		}
	}

	nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
		let id = downloadTask.taskDescription
		Task { @MainActor in self.update(id, received: totalBytesWritten, expected: totalBytesExpectedToWrite) }
	}

	nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		guard let error, (error as NSError).code != NSURLErrorCancelled else { return }
		let id = task.taskDescription
		let message = error.localizedDescription
		Task { @MainActor in await self.finish(id, file: nil, error: message) }
	}
}
