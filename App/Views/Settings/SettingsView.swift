import SwiftUI

struct SettingsView: View {
	@EnvironmentObject private var certificates: CertificateStore
	@EnvironmentObject private var router: AppRouter

	@State private var path = NavigationPath()

	private var version: String {
		let info = Bundle.main.infoDictionary
		return "\(info?["CFBundleShortVersionString"] as? String ?? "1.0") (\(info?["CFBundleVersion"] as? String ?? "1"))"
	}

	var body: some View {
		NavigationStack(path: $path) {
			List {
				Section {
					HStack(spacing: 16) {
						ZStack {
							Circle().fill(Spectra.angular).frame(width: 70, height: 70).blur(radius: 14).opacity(0.7)
							Image("Logo")
								.resizable()
								.frame(width: 64, height: 64)
								.clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
						}
						VStack(alignment: .leading, spacing: 3) {
							Text("Spectra Signer").font(.title2.weight(.bold))
							Text("Version \(version)").font(.caption).foregroundStyle(.secondary)
							Capsule().fill(Spectra.gradient).frame(width: 90, height: 4).padding(.top, 4)
						}
					}
					.padding(.vertical, 8)
					.cardRow()
				}

				Section {
					NavigationLink(value: Destination.certificates) {
						HStack {
							Label("Certificates", systemImage: "checkmark.seal.fill")
							Spacer()
							if let selected = certificates.selected {
								Text(selected.displayName).foregroundStyle(.secondary).lineLimit(1)
							}
						}
					}
				} header: {
					Text("Signing")
				} footer: {
					if let selected = certificates.selected {
						Text(selected.expiration.expiryDescription)
					} else {
						Text("Add a .p12 certificate and its provisioning profile to start signing.")
					}
				}

				Section {
					NavigationLink(value: Destination.signingDefaults) {
						Label("Signing Options", systemImage: "signature")
					}
					NavigationLink(value: Destination.installation) {
						Label("Installation", systemImage: "arrow.down.app")
					}
					NavigationLink(value: Destination.appearance) {
						Label("Appearance", systemImage: "paintbrush.fill")
					}
					NavigationLink(value: Destination.storage) {
						Label("Storage", systemImage: "internaldrive.fill")
					}
				}

				Section {
					NavigationLink(value: Destination.sources) {
						Label("Sources", systemImage: "globe")
					}
					NavigationLink(value: Destination.about) {
						Label("About", systemImage: "info.circle.fill")
					}
				}
			}
			.spectraBackground()
			.navigationTitle("Settings")
			.navigationDestination(for: Destination.self) { destination in
				switch destination {
				case .certificates: CertificatesView()
				case .signingDefaults: SigningDefaultsView()
				case .installation: InstallationSettingsView()
				case .appearance: AppearanceView()
				case .storage: StorageView()
				case .sources: SourceSettingsView()
				case .about: AboutView()
				}
			}
			.onChange(of: router.pendingCertificate?.id) { pending in
				if pending != nil, path.isEmpty { path.append(Destination.certificates) }
			}
		}
	}

	enum Destination: Hashable {
		case certificates, signingDefaults, installation, appearance, storage, sources, about
	}
}

struct SigningDefaultsView: View {
	@State private var options = SignOptions.defaults

	var body: some View {
		Form {
			Section {
				Toggle("Enable File Sharing", isOn: $options.fileSharing)
				Toggle("Remove Device Restrictions", isOn: $options.removeSupportedDevices)
				Toggle("Remove App Extensions", isOn: $options.removeExtensions)
				Toggle("Remove Watch App", isOn: $options.removeWatchApp)
			} header: {
				Text("Modify")
			} footer: {
				Text("File Sharing shows the app's documents in the Files app. Device Restrictions removal lets iPhone-only apps install on iPad. Removing extensions avoids errors with profiles that don't cover them.")
			}

			Section {
				Toggle("Weak Load Injected Dylibs", isOn: $options.weakInject)
			} footer: {
				Text("The app still launches if a weak-loaded dylib fails to load.")
			}

			Section("After Signing") {
				Toggle("Install Automatically", isOn: $options.installAfterSigning)
				Toggle("Delete Unsigned Copy", isOn: $options.deleteUnsignedAfterSigning)
			}

			Section {
				Button("Reset to Defaults", role: .destructive) { options = SignOptions() }
			}
		}
		.spectraBackground()
		.navigationTitle("Signing Options")
		.onChange(of: options) { SignOptions.defaults = $0 }
	}
}

struct InstallationSettingsView: View {
	@AppStorage(Prefs.keepAliveAudio) private var keepAlive = true
	@AppStorage(Prefs.compressIPAs) private var compress = false

	var body: some View {
		Form {
			Section {
				LabeledContent("Install Server", value: InstallServer.isAvailable ? "Ready" : "Unavailable")
			} footer: {
				Text("Signed apps install through a secure server running on this device, the same way enterprise apps are distributed. Nothing leaves your device.")
			}

			Section {
				Toggle("Stay Active in Background", isOn: $keepAlive)
			} footer: {
				Text("Plays silent audio during an install so iOS doesn't pause the server while it copies a large app.")
			}

			Section {
				Toggle("Compress Signed Apps", isOn: $compress)
			} footer: {
				Text("Smaller .ipa files for sharing, but signing takes longer.")
			}
		}
		.spectraBackground()
		.navigationTitle("Installation")
	}
}

struct AppearanceView: View {
	@AppStorage(Prefs.accentColor) private var accentHex = Color.spectrum[0].hex
	@AppStorage(Prefs.colorScheme) private var colorScheme = 0

	var body: some View {
		Form {
			Section("Theme") {
				Picker("Appearance", selection: $colorScheme) {
					Text("System").tag(0)
					Text("Light").tag(1)
					Text("Dark").tag(2)
				}
				.pickerStyle(.segmented)
			}

			Section("Accent Color") {
				LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
					ForEach(Color.spectrum) { swatch in
						Button {
							accentHex = swatch.hex
						} label: {
							Circle()
								.fill(Color(hex: swatch.hex) ?? .purple)
								.frame(width: 34, height: 34)
								.overlay {
									if accentHex == swatch.hex {
										Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
									}
								}
						}
						.buttonStyle(.plain)
						.accessibilityLabel(swatch.name)
					}
				}
				.padding(.vertical, 6)
			}
		}
		.spectraBackground()
		.navigationTitle("Appearance")
	}
}

struct StorageView: View {
	@EnvironmentObject private var library: LibraryStore
	@EnvironmentObject private var certificates: CertificateStore

	@State private var sizes: [String: Int64] = [:]
	@State private var confirm: Action?

	enum Action: String, Identifiable {
		case unsigned = "Delete All Unsigned Apps"
		case signed = "Delete All Signed Apps"
		case certificates = "Delete All Certificates"
		case everything = "Reset Everything"
		var id: String { rawValue }
	}

	var body: some View {
		Form {
			Section("Usage") {
				LabeledContent("Unsigned Apps", value: (sizes["unsigned"] ?? 0).formattedBytes)
				LabeledContent("Signed Apps", value: (sizes["signed"] ?? 0).formattedBytes)
				LabeledContent("Certificates", value: (sizes["certificates"] ?? 0).formattedBytes)
				LabeledContent("Temporary Files", value: (sizes["temp"] ?? 0).formattedBytes)
			}

			Section {
				Button("Clear Temporary Files") {
					Paths.clearTemp()
					refresh()
				}
			}

			Section {
				Button(Action.unsigned.rawValue, role: .destructive) { confirm = .unsigned }
				Button(Action.signed.rawValue, role: .destructive) { confirm = .signed }
				Button(Action.certificates.rawValue, role: .destructive) { confirm = .certificates }
				Button(Action.everything.rawValue, role: .destructive) { confirm = .everything }
			}
		}
		.spectraBackground()
		.navigationTitle("Storage")
		.onAppear(perform: refresh)
		.confirmationDialog(confirm?.rawValue ?? "", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
			Button("Delete", role: .destructive) {
				switch confirm {
				case .unsigned: library.deleteAll(kind: .unsigned)
				case .signed: library.deleteAll(kind: .signed)
				case .certificates: certificates.deleteAll()
				case .everything:
					library.deleteAll()
					certificates.deleteAll()
					Paths.clearTemp()
				case nil: break
				}
				confirm = nil
				refresh()
			}
		} message: {
			Text("This can't be undone.")
		}
	}

	private func refresh() {
		Task.detached(priority: .utility) {
			let result: [String: Int64] = [
				"unsigned": Paths.size(of: Paths.unsigned),
				"signed": Paths.size(of: Paths.signed),
				"certificates": Paths.size(of: Paths.certificates),
				"temp": Paths.size(of: Paths.temp),
			]
			await MainActor.run { sizes = result }
		}
	}
}

struct AboutView: View {
	var body: some View {
		List {
			Section {
				VStack(spacing: 10) {
					Image("Logo")
						.resizable()
						.frame(width: 88, height: 88)
						.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
					Text("Spectra Signer").font(.title2.weight(.bold))
					Text("Sign and install apps right on your device.")
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}
				.frame(maxWidth: .infinity)
				.padding(.vertical, 8)
				.listRowBackground(Color.clear)
			}

			Section("Open Source") {
				Link("zsign — code signing engine", destination: URL(string: "https://github.com/zhlynn/zsign")!)
				Link("OpenSSL", destination: URL(string: "https://github.com/krzyzanowskim/OpenSSL")!)
				Link("ZIPFoundation", destination: URL(string: "https://github.com/weichsel/ZIPFoundation")!)
			}
		}
		.spectraBackground()
		.navigationTitle("About")
	}
}

struct SourceSettingsView: View {
	@EnvironmentObject private var sources: SourceStore
	@State private var confirmRemoveAll = false

	var body: some View {
		Form {
			Section {
				LabeledContent("Sources", value: "\(sources.sources.count)")
				LabeledContent("Built-in", value: "\(sources.sources.filter { $0.isBuiltin == true }.count) of \(SourceStore.builtin.count)")
				LabeledContent("Apps Available", value: "\(sources.totalApps)")
				if let last = sources.lastRefresh {
					LabeledContent("Last Updated", value: last.formatted(date: .omitted, time: .shortened))
				}
			}

			Section {
				Button {
					Task { await sources.refreshAll() }
				} label: {
					HStack {
						Label("Refresh All Sources", systemImage: "arrow.clockwise")
						if sources.isRefreshing {
							Spacer()
							ProgressView()
						}
					}
				}
				.disabled(sources.isRefreshing)

				if sources.missingBuiltinCount > 0 {
					Button {
						Task { await sources.restoreBuiltins() }
					} label: {
						Label("Restore \(sources.missingBuiltinCount) Built-in Sources", systemImage: "arrow.counterclockwise")
					}
				}
			} footer: {
				Text("Spectra Signer comes with \(SourceStore.builtin.count) hand-picked sources of open-source and developer-published apps. Remove any you don't want from the Sources tab.")
			}

			Section {
				Button("Remove All Sources", role: .destructive) { confirmRemoveAll = true }
			}
		}
		.spectraBackground()
		.navigationTitle("Sources")
		.confirmationDialog("Remove all sources?", isPresented: $confirmRemoveAll, titleVisibility: .visible) {
			Button("Remove All", role: .destructive) { sources.removeAll() }
		} message: {
			Text("You can restore the built-in ones later.")
		}
	}
}
