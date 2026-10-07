import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The system document picker in copy mode: picked files arrive as local copies the app owns,
/// which is more reliable than SwiftUI's fileImporter when presented from inside a sheet.
struct DocumentPicker: UIViewControllerRepresentable {
	let types: [UTType]
	var allowsMultipleSelection = true
	let onPick: ([URL]) -> Void

	func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

	func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
		let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
		picker.allowsMultipleSelection = allowsMultipleSelection
		picker.delegate = context.coordinator
		return picker
	}

	func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {
		context.coordinator.onPick = onPick
	}

	final class Coordinator: NSObject, UIDocumentPickerDelegate {
		var onPick: ([URL]) -> Void

		init(onPick: @escaping ([URL]) -> Void) {
			self.onPick = onPick
		}

		func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
			onPick(urls)
		}
	}
}
