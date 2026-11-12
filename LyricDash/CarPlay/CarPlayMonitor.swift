import AVFoundation
import Foundation
import Observation

/// Detects CarPlay by watching the audio route: CarPlay audio shows up as `.carAudio`
/// (plain Bluetooth car stereos show up as Bluetooth instead).
///
/// This only works while LyricDash is running. For the "app is closed" case, use the
/// Shortcuts automation described in the README (When CarPlay Connects -> Start Lyrics).
@MainActor
@Observable
final class CarPlayMonitor {
    @ObservationIgnored var onConnect: (() -> Void)?
    @ObservationIgnored var onDisconnect: (() -> Void)?
    private(set) var isConnected = false
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        isConnected = Self.carAudioActive()
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
    }

    private func evaluate() {
        let connected = Self.carAudioActive()
        guard connected != isConnected else { return }
        isConnected = connected
        connected ? onConnect?() : onDisconnect?()
    }

    private static func carAudioActive() -> Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .carAudio }
    }
}
