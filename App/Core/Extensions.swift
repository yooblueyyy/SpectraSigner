import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension UTType {
	static let ipa = UTType(importedAs: "com.apple.itunes.ipa", conformingTo: .zip)
	static let tipa = UTType(importedAs: "dev.spectra.tipa", conformingTo: .zip)
	static let mobileProvision = UTType(importedAs: "com.apple.mobileprovision", conformingTo: .data)
	static let dylib = UTType(importedAs: "com.apple.mach-o-dylib", conformingTo: .data)
}

extension Color {
	init?(hex: String?) {
		guard var hex = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else { return nil }
		if hex.hasPrefix("#") { hex.removeFirst() }
		guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
		self.init(
			red: Double((value >> 16) & 0xFF) / 255,
			green: Double((value >> 8) & 0xFF) / 255,
			blue: Double(value & 0xFF) / 255
		)
	}

	/// The spectrum used for accent choices, matching the app icon.
	static let spectrum: [AccentSwatch] = [
		AccentSwatch(name: "Violet", hex: "8B5CF6"),
		AccentSwatch(name: "Indigo", hex: "5E5CE6"),
		AccentSwatch(name: "Blue", hex: "0AB4FF"),
		AccentSwatch(name: "Green", hex: "34C759"),
		AccentSwatch(name: "Yellow", hex: "FFC60A"),
		AccentSwatch(name: "Orange", hex: "FF9500"),
		AccentSwatch(name: "Pink", hex: "FF3B78"),
	]
}

struct AccentSwatch: Identifiable {
	let name: String
	let hex: String
	var id: String { hex }
}

extension UIImage {
	/// Centre-crops to a square and scales to `side` points at scale 1.
	func squared(to side: CGFloat) -> UIImage {
		let edge = min(size.width, size.height)
		let origin = CGPoint(x: (size.width - edge) / 2, y: (size.height - edge) / 2)
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		format.opaque = true
		return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
			let scale = side / edge
			draw(in: CGRect(x: -origin.x * scale, y: -origin.y * scale, width: size.width * scale, height: size.height * scale))
		}
	}
}

extension Int64 {
	var formattedBytes: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}

extension Date {
	/// "Expires in 3 days", "Expired 2 days ago".
	var expiryDescription: String {
		let relative = RelativeDateTimeFormatter()
		relative.unitsStyle = .full
		let phrase = relative.localizedString(for: self, relativeTo: Date())
		return self < Date() ? "Expired \(phrase)" : "Expires \(phrase)"
	}

	var expiryColor: Color {
		let days = timeIntervalSinceNow / 86_400
		if days < 0 { return .red }
		if days < 7 { return .orange }
		return .green
	}
}

/// Rounded app icon from a local file or remote URL.
struct AppIconView: View {
	var url: URL?
	var size: CGFloat = 52

	var body: some View {
		ZStack {
			RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
				.fill(Color(.secondarySystemFill))
			if let url {
				if url.isFileURL {
					if let image = UIImage(contentsOfFile: url.path) {
						Image(uiImage: image).resizable().scaledToFill()
					} else {
						placeholder
					}
				} else {
					AsyncImage(url: url) { phase in
						if let image = phase.image {
							image.resizable().scaledToFill()
						} else {
							placeholder
						}
					}
				}
			} else {
				placeholder
			}
		}
		.frame(width: size, height: size)
		.clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
				.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
		)
	}

	private var placeholder: some View {
		Image(systemName: "app.dashed")
			.font(.system(size: size * 0.45, weight: .light))
			.foregroundStyle(.secondary)
	}
}

/// iOS 16-compatible empty state.
struct EmptyStateView: View {
	var title: String
	var systemImage: String
	var message: String

	var body: some View {
		VStack(spacing: 10) {
			Image(systemName: systemImage)
				.font(.system(size: 44, weight: .light))
				.foregroundStyle(.secondary)
			Text(title).font(.title3.weight(.semibold))
			Text(message)
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
		}
		.padding(32)
		.frame(maxWidth: .infinity)
	}
}

/// Small capsule label, e.g. "Signed".
struct Pill: View {
	var text: String
	var color: Color

	var body: some View {
		Text(text)
			.font(.caption2.weight(.semibold))
			.padding(.horizontal, 7)
			.padding(.vertical, 3)
			.foregroundStyle(color)
			.background(color.opacity(0.15), in: Capsule())
	}
}
