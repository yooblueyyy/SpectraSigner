import SwiftUI

@main
struct SpectraSignerApp: App {
	@StateObject private var router = AppRouter()
	@StateObject private var library = LibraryStore()
	@StateObject private var certificates = CertificateStore()
	@StateObject private var sources = SourceStore()
	@StateObject private var downloads = DownloadManager()
	@StateObject private var installer = InstallManager()

	@AppStorage(Prefs.accentColor) private var accentHex = Color.spectrum[0].hex
	@AppStorage(Prefs.colorScheme) private var colorSchemeSetting = 0

	init() {
		Paths.prepare()
	}

	var body: some Scene {
		WindowGroup {
			RootView()
				.environmentObject(router)
				.environmentObject(library)
				.environmentObject(certificates)
				.environmentObject(sources)
				.environmentObject(downloads)
				.environmentObject(installer)
				.tint(Color(hex: accentHex) ?? .purple)
				.preferredColorScheme(colorSchemeSetting == 1 ? .light : colorSchemeSetting == 2 ? .dark : nil)
				.onAppear { downloads.library = library }
				.onOpenURL { handle($0) }
		}
	}

	/// Files opened from other apps, and `spectrasigner://` links.
	private func handle(_ url: URL) {
		if url.isFileURL {
			switch url.pathExtension.lowercased() {
			case "ipa", "tipa":
				router.tab = .library
				Task {
					do { try await library.importIPA(at: url) } catch { router.show(error) }
				}
			case "p12", "pfx":
				router.tab = .settings
				router.pendingCertificate = .init(p12: url, profile: router.pendingCertificate?.profile)
			case "mobileprovision":
				router.tab = .settings
				router.pendingCertificate = .init(p12: router.pendingCertificate?.p12, profile: url)
			default:
				router.alert = "Spectra Signer can't open .\(url.pathExtension) files."
			}
			return
		}

		// spectrasigner://source?url=…  and  spectrasigner://install?url=…
		guard
			url.scheme?.lowercased() == "spectrasigner",
			let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?
				.queryItems?.first(where: { $0.name == "url" })?.value
		else { return }

		switch url.host?.lowercased() {
		case "source", "add-source":
			router.tab = .sources
			router.pendingSourceURL = target
		case "install", "download":
			if let ipa = URL(string: target) {
				router.tab = .library
				downloads.download(ipa, name: ipa.deletingPathExtension().lastPathComponent)
			}
		default:
			break
		}
	}
}

struct RootView: View {
	@EnvironmentObject private var router: AppRouter
	@EnvironmentObject private var installer: InstallManager
	@EnvironmentObject private var downloads: DownloadManager

	var body: some View {
		TabView(selection: $router.tab) {
			SourcesView()
				.tabItem { Label("Sources", systemImage: "globe") }
				.tag(AppRouter.Tab.sources)
			LibraryView()
				.tabItem { Label("Library", systemImage: "square.stack.3d.up.fill") }
				.tag(AppRouter.Tab.library)
			SettingsView()
				.tabItem { Label("Settings", systemImage: "gearshape.fill") }
				.tag(AppRouter.Tab.settings)
		}
		.sheet(isPresented: $installer.isPresented, onDismiss: { installer.dismiss() }) {
			InstallSheet()
				.presentationDetents([.height(340)])
		}
		.alert("Something went wrong", isPresented: Binding(
			get: { router.alert != nil },
			set: { if !$0 { router.alert = nil } }
		)) {
			Button("OK", role: .cancel) {}
		} message: {
			Text(router.alert ?? "")
		}
		.onChange(of: downloads.lastError) { error in
			if let error {
				router.alert = error
				downloads.lastError = nil
			}
		}
	}
}
