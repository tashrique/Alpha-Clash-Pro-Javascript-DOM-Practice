import AuthenticationServices
import CoreLocation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.webAuthenticationSession) private var webAuth

    @AppStorage(Prefs.Key.chimeEnabled) private var chimeEnabled = true
    @AppStorage(Prefs.Key.chimeStyle) private var chimeStyle = ChimePlayer.Style.rise.rawValue
    @AppStorage(Prefs.Key.chimeVolume) private var chimeVolume = 0.8
    @AppStorage(Prefs.Key.autoStart) private var autoStart = true
    @AppStorage(Prefs.Key.autoStop) private var autoStop = true
    @AppStorage(Prefs.Key.lyricOffset) private var lyricOffset = 0.0
    @AppStorage(Prefs.Key.customChimeFile) private var customChimeFile = ""

    @State private var errorText: String?
    @State private var showImporter = false

    private var model: AppModel { .shared }
    private var engine: NowPlayingEngine { model.engine }
    private var auth: SpotifyAuth { model.auth }

    var body: some View {
        NavigationStack {
            Form {
                nowPlayingSection
                spotifySection
                timingSection
                soundSection
                automationSection
                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("LyricDash")
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { result in
                importCustomSound(result)
            }
        }
    }

    // MARK: Sections

    private var nowPlayingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(model.carPlay.isConnected ? "CarPlay connected" : "CarPlay not connected",
                          systemImage: "car.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(model.carPlay.isConnected ? .green : .secondary)
                    Spacer()
                    Text(engine.status).font(.caption).foregroundStyle(.secondary)
                }
                if let track = engine.track {
                    Text(track.name).font(.headline)
                    Text(track.artistLine).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(engine.track == nil ? "Lyrics show up here" : engine.currentLine)
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeInOut, value: engine.currentIndex)
                if !engine.nextLine.isEmpty {
                    Text(engine.nextLine).font(.body).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)

            Button {
                engine.isRunning ? engine.stop() : engine.start()
            } label: {
                Label(engine.isRunning ? "Stop lyrics" : "Start lyrics",
                      systemImage: engine.isRunning ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!auth.isSignedIn)

            if !model.liveActivity.isEnabledBySystem {
                Text("Live Activities are off for LyricDash. Turn them on in Settings > LyricDash.")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }
    }

    private var spotifySection: some View {
        Section("Spotify") {
            if auth.isSignedIn {
                Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Disconnect", role: .destructive) {
                    engine.stop()
                    auth.signOut()
                }
            } else {
                Button("Connect Spotify", action: connectSpotify)
            }
            Button("Allow background (location)") { model.background.requestPermission() }
            Text("Tap twice: first allow \"While Using\", then \"Always\". Needed so lyrics keep updating while Maps is on screen and so the CarPlay automation can start lyrics. Location is never stored or sent.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var timingSection: some View {
        Section {
            VStack(alignment: .leading) {
                Text("Lyric timing: \(lyricOffset, specifier: "%+.1f") s")
                Slider(value: $lyricOffset, in: -2...2, step: 0.1)
            }
        } header: {
            Text("Sync")
        } footer: {
            Text("Lyrics late? Slide right. Early? Slide left.")
        }
    }

    private var soundSection: some View {
        Section("CarPlay connect sound") {
            Toggle("Play a sound when CarPlay connects", isOn: $chimeEnabled)
            Picker("Sound", selection: $chimeStyle) {
                ForEach(ChimePlayer.Style.allCases) { Text($0.label).tag($0.rawValue) }
            }
            if chimeStyle == ChimePlayer.Style.custom.rawValue {
                Button(customChimeFile.isEmpty ? "Choose a sound file…" : "Replace \(customChimeFile)") {
                    showImporter = true
                }
            }
            HStack {
                Image(systemName: "speaker.fill")
                Slider(value: $chimeVolume, in: 0.1...1)
                Image(systemName: "speaker.wave.3.fill")
            }
            Button("Preview") {
                Task { await ChimePlayer.shared.play(Prefs.chimeStyle, volume: chimeVolume, force: true) }
            }
        }
    }

    private var automationSection: some View {
        Section {
            Toggle("Start lyrics when CarPlay connects", isOn: $autoStart)
            Toggle("Stop lyrics when CarPlay disconnects", isOn: $autoStop)
        } header: {
            Text("Automation")
        } footer: {
            Text("These work while LyricDash is open or running in the background. To have it start even when the app is closed, add a Shortcuts automation: Automation > New > CarPlay > Connects > Run Immediately, then add \"Start CarPlay Lyrics\" and \"Play CarPlay Connect Sound\". See the README.")
        }
    }

    // MARK: Actions

    private func connectSpotify() {
        Task {
            do {
                let url = try auth.makeAuthorizeURL()
                let callback = try await webAuth.authenticate(using: url, callbackURLScheme: SpotifyAuth.callbackScheme)
                try await auth.handleCallback(callback)
                errorText = nil
            } catch ASWebAuthenticationSessionError.canceledLogin {
                // user closed the sheet
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func importCustomSound(_ result: Result<URL, Error>) {
        do {
            let source = try result.get()
            guard source.startAccessingSecurityScopedResource() else { return }
            defer { source.stopAccessingSecurityScopedResource() }
            let name = "custom-chime.\(source.pathExtension.isEmpty ? "m4a" : source.pathExtension)"
            let dest = URL.documentsDirectory.appending(path: name)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: source, to: dest)
            customChimeFile = name
        } catch {
            errorText = "Couldn't import sound: \(error.localizedDescription)"
        }
    }
}
