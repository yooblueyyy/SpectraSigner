import SwiftUI

/// Spectra's visual language: the spectrum from the app icon, soft aurora backgrounds and rounded glass cards.
enum Spectra {
	static let colors: [Color] = ["FF3B78", "FF9500", "FFC60A", "34C759", "0AB4FF", "5E5CE6", "BF5AF2"]
		.compactMap { Color(hex: $0) }

	static var gradient: LinearGradient {
		LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
	}

	static var angular: AngularGradient {
		AngularGradient(colors: colors + [colors[0]], center: .center)
	}

	static let cardRadius: CGFloat = 22
}

/// Blurred colour glow behind every screen; tinted by the user's accent colour.
struct AuroraBackground: View {
	@Environment(\.colorScheme) private var scheme

	var body: some View {
		GeometryReader { geo in
			let w = geo.size.width
			ZStack(alignment: .top) {
				Color(.systemGroupedBackground)
				ZStack {
					Circle().fill(Color.accentColor).frame(width: w * 0.95).offset(x: -w * 0.35, y: -w * 0.5)
					Circle().fill(Spectra.colors[4]).frame(width: w * 0.75).offset(x: w * 0.42, y: -w * 0.42)
					Circle().fill(Spectra.colors[0]).frame(width: w * 0.55).offset(x: w * 0.05, y: -w * 0.72)
				}
				.blur(radius: 90)
				.opacity(scheme == .dark ? 0.38 : 0.2)
				.frame(width: w)
			}
		}
		.ignoresSafeArea()
	}
}

extension View {
	/// Replaces a List/Form's flat background with the aurora.
	func spectraBackground() -> some View {
		scrollContentBackground(.hidden).background(AuroraBackground())
	}

	/// Rounded material card.
	func glassCard(padding: CGFloat = 16, radius: CGFloat = Spectra.cardRadius) -> some View {
		self
			.padding(padding)
			.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
			.overlay(
				RoundedRectangle(cornerRadius: radius, style: .continuous)
					.strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
			)
	}

	/// List row that renders as a floating card.
	func cardRow() -> some View {
		self
			.listRowBackground(
				RoundedRectangle(cornerRadius: 18, style: .continuous)
					.fill(.regularMaterial)
					.padding(.vertical, 4)
			)
			.listRowSeparator(.hidden)
			.listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
	}
}

/// Full-width accent button with a soft glow.
struct SpectraButtonStyle: ButtonStyle {
	var tint: Color = .accentColor

	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(.headline)
			.foregroundStyle(.white)
			.frame(maxWidth: .infinity)
			.padding(.vertical, 15)
			.background(
				LinearGradient(colors: [tint, tint.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing),
				in: Capsule()
			)
			.overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
			.shadow(color: tint.opacity(0.35), radius: 14, y: 6)
			.scaleEffect(configuration.isPressed ? 0.97 : 1)
			.opacity(configuration.isPressed ? 0.9 : 1)
			.animation(.spring(response: 0.25), value: configuration.isPressed)
	}
}

/// Small rounded "GET"-style pill button.
struct PillButtonStyle: ButtonStyle {
	var filled = false

	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(.subheadline.weight(.bold))
			.padding(.horizontal, 16)
			.padding(.vertical, 7)
			.foregroundStyle(filled ? Color.white : Color.accentColor)
			.background(filled ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
			.scaleEffect(configuration.isPressed ? 0.94 : 1)
			.animation(.spring(response: 0.2), value: configuration.isPressed)
	}
}

/// Horizontal capsule filter chips.
struct ChipBar<Option: Hashable>: View {
	let options: [Option]
	@Binding var selection: Option
	let title: (Option) -> String

	var body: some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 8) {
				ForEach(options, id: \.self) { option in
					let selected = option == selection
					Button {
						withAnimation(.spring(response: 0.3)) { selection = option }
					} label: {
						Text(title(option))
							.font(.subheadline.weight(.semibold))
							.padding(.horizontal, 15)
							.padding(.vertical, 8)
							.foregroundStyle(selected ? Color.white : Color.primary)
							.background(selected ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
					}
					.buttonStyle(.plain)
				}
			}
			.padding(.horizontal, 2)
		}
	}
}

/// Spectrum progress ring. A nil progress spins indefinitely.
struct SpectraRing<Center: View>: View {
	var progress: Double?
	var size: CGFloat = 110
	var lineWidth: CGFloat = 8
	@ViewBuilder var center: () -> Center

	@State private var spin = false

	var body: some View {
		ZStack {
			Circle().stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
			Circle()
				.trim(from: 0, to: progress.map { max(0.02, $0) } ?? 0.28)
				.stroke(Spectra.angular, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
				.rotationEffect(.degrees(progress == nil ? (spin ? 270 : -90) : -90))
				.animation(progress == nil ? .linear(duration: 1).repeatForever(autoreverses: false) : .easeInOut, value: spin)
				.animation(.easeInOut, value: progress)
			center()
		}
		.frame(width: size, height: size)
		.onAppear { spin = true }
	}
}

/// Big number tile used in headers.
struct StatTile: View {
	var value: String
	var label: String
	var systemImage: String
	var tint: Color = .accentColor

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Image(systemName: systemImage)
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(tint)
				.frame(width: 30, height: 30)
				.background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
			Text(value)
				.font(.title3.weight(.bold))
				.lineLimit(1)
				.minimumScaleFactor(0.6)
			Text(label)
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(1)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.glassCard(padding: 12, radius: 18)
	}
}

/// Section title with an optional trailing link.
struct ShelfHeader<Destination: View>: View {
	var title: String
	var subtitle: String?
	@ViewBuilder var destination: () -> Destination

	var body: some View {
		HStack(alignment: .firstTextBaseline) {
			VStack(alignment: .leading, spacing: 2) {
				Text(title).font(.title3.weight(.bold))
				if let subtitle {
					Text(subtitle).font(.caption).foregroundStyle(.secondary)
				}
			}
			Spacer()
			NavigationLink {
				destination()
			} label: {
				Text("See All").font(.subheadline.weight(.semibold))
			}
		}
		.padding(.horizontal, 20)
	}
}
