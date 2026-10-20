import Foundation
import AVFoundation
import AppKit
import FocusCore

/// Manages both the built-in Nature & Ambient studio recordings (`.m4a` loops) and Spotify playback (Courten, Deep Work & Jazz).
@MainActor
final class FocusAudioController {
    private let preview: Bool
    private var audioPlayer: AVAudioPlayer?
    private var stopTimer: Task<Void, Never>?

    private var currentActiveSound: FocusSound = .off
    private var spotifyControlled = false
    private var lastSpotifyURI: String?
    private var lastSubmittedVolume: Int = -1
    private var spotifyPollTask: Task<Void, Never>?

    var onNowPlayingChanged: ((String?) -> Void)?
    private(set) var nowPlayingTrack: String? {
        didSet {
            if oldValue != nowPlayingTrack {
                onNowPlayingChanged?(nowPlayingTrack)
            }
        }
    }

    init(preview: Bool) {
        self.preview = preview
    }

    nonisolated static var isSpotifyInstalled: Bool {
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil {
            return true
        }
        let fm = FileManager.default
        let standardPaths = [
            "/Applications/Spotify.app",
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Spotify.app").path
        ]
        return standardPaths.contains { fm.fileExists(atPath: $0) }
    }

    nonisolated static func resolveNatureAudioURL(named resource: String) -> URL? {
        let fm = FileManager.default
        if let bundleResources = Bundle.main.resourceURL {
            let candidate = bundleResources.appendingPathComponent("Sounds/\(resource).m4a")
            if fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        if let bundled = Bundle.main.url(forResource: resource, withExtension: "m4a", subdirectory: "Sounds") {
            return bundled
        }
        if let execURL = Bundle.main.executableURL {
            let siblingResources = execURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/Sounds/\(resource).m4a")
            if fm.fileExists(atPath: siblingResources.path) {
                return siblingResources
            }
        }
        let cwdCandidate = URL(fileURLWithPath: fm.currentDirectoryPath)
            .appendingPathComponent("Resources/Sounds/\(resource).m4a")
        if fm.fileExists(atPath: cwdCandidate.path) {
            return cwdCandidate
        }
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fallback = repoRoot.appendingPathComponent("Resources/Sounds/\(resource).m4a")
        if fm.fileExists(atPath: fallback.path) {
            return fallback
        }
        return nil
    }

    func play(sound: FocusSound, volume: Double) {
        guard !preview, sound != .off else {
            stop()
            return
        }
        let clampedVolume = Float(min(1.0, max(0.05, volume)))

        if currentActiveSound == sound {
            stopTimer?.cancel()
            stopTimer = nil
            if !sound.isSpotify, let player = audioPlayer, !player.isPlaying {
                player.play()
            }
            updateVolume(volume)
            return
        }

        if let uri = sound.spotifyURI {
            fadeOutNaturePlayer(immediate: true)
            startOrResumeSpotify(sound: sound, uri: uri, volume: clampedVolume)
            currentActiveSound = sound
            return
        }

        if spotifyControlled {
            pauseSpotify()
        }

        currentActiveSound = sound
        nowPlayingTrack = nil
        stopTimer?.cancel()
        stopTimer = nil

        startNaturePlayer(for: sound, volume: clampedVolume)
    }

    func updateVolume(_ volume: Double) {
        guard !preview, currentActiveSound != .off else { return }
        let clamped = Float(min(1.0, max(0.05, volume)))
        if currentActiveSound.isSpotify {
            let volPercent = Int((clamped * 100).rounded())
            if abs(volPercent - lastSubmittedVolume) >= 2 {
                lastSubmittedVolume = volPercent
                runSpotifyScript("tell application \"Spotify\" to if it is running then set sound volume to \(volPercent)")
            }
        } else {
            audioPlayer?.setVolume(clamped, fadeDuration: 0.12)
        }
    }

    func stop(immediate: Bool = false) {
        currentActiveSound = .off
        if spotifyControlled {
            pauseSpotify()
        }
        fadeOutNaturePlayer(immediate: immediate)
    }

    func skipSpotifyTrack() {
        guard !preview, currentActiveSound.isSpotify else { return }
        Task { [weak self] in
            let info: String? = await Task.detached {
                Self.executeOsaScript("""
                tell application "Spotify"
                    if it is running then
                        if shuffling enabled then set shuffling to true
                        next track
                    end if
                end tell
                """)
                try? await Task.sleep(nanoseconds: 450_000_000)
                return Self.fetchSpotifyTrack()
            }.value
            self?.nowPlayingTrack = info
        }
    }

    func openInSpotifyApp(sound: FocusSound) {
        guard !preview else { return }
        if Self.isSpotifyInstalled, let uri = sound.spotifyURI, let url = URL(string: uri) {
            NSWorkspace.shared.open(url)
        } else if let webURL = sound.spotifyWebURL {
            NSWorkspace.shared.open(webURL)
        }
    }

    // MARK: - Built-in Nature & Ambient Audio Player

    private func startNaturePlayer(for sound: FocusSound, volume: Float) {
        audioPlayer?.stop()
        audioPlayer = nil

        guard let resource = sound.audioResourceName,
              let url = Self.resolveNatureAudioURL(named: resource) else {
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0.0
            player.prepareToPlay()
            player.play()
            player.setVolume(volume, fadeDuration: 0.35)
            self.audioPlayer = player
        } catch {
            self.audioPlayer = nil
        }
    }

    private func fadeOutNaturePlayer(immediate: Bool = false) {
        stopTimer?.cancel()
        stopTimer = nil
        guard let player = audioPlayer else { return }
        if immediate || !player.isPlaying {
            player.stop()
            audioPlayer = nil
            return
        }
        player.setVolume(0.0, fadeDuration: 0.28)
        stopTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled, let self else { return }
            if self.currentActiveSound == .off || self.currentActiveSound.isSpotify {
                self.audioPlayer?.stop()
                self.audioPlayer = nil
            }
        }
    }

    // MARK: - Spotify Control

    private func startOrResumeSpotify(sound: FocusSound, uri: String, volume: Float) {
        let volPercent = Int((volume * 100).rounded())
        let isSameURI = (lastSpotifyURI == uri)
        let wasAlreadyControlled = spotifyControlled
        let previousFrontApp = NSWorkspace.shared.frontmostApplication
        let spotifyWasFrontmost = (previousFrontApp?.bundleIdentifier == "com.spotify.client")
        spotifyControlled = true
        lastSpotifyURI = uri
        lastSubmittedVolume = volPercent

        // If the user's Mac does not have Spotify.app installed, automatically open the
        // curated playlist in the Spotify Web Player so it works out of the box on any Mac.
        guard Self.isSpotifyInstalled else {
            if !isSameURI || !wasAlreadyControlled, let webURL = sound.spotifyWebURL {
                NSWorkspace.shared.open(webURL)
            }
            nowPlayingTrack = "Spotify Web · \(sound.shortTitle)"
            return
        }

        Task { [weak self] in
            let info: String? = await Task.detached {
                Self.ensureSpotifyRunningInBackground()
                // Note: Passing `in context " "` prevents Spotify's SPPlayTrackScriptCommand
                // from navigating its CEF browser window to the playlist URI and bringing
                // the Spotify window to the foreground, while still playing `uri` normally.
                // On a brand-new cold start, if `in context " "` does not immediately transition
                // `player state` to `playing`, we automatically retry with `play track "<uri>"`
                // and then re-hide Spotify so playback starts reliably on every Mac.
                let playPlaylistScript = """
                tell application "Spotify"
                    set sound volume to 0
                    set shuffling to true
                    play track "\(uri)" in context " "
                    delay 0.34
                    if player state is not playing then
                        play track "\(uri)"
                        delay 0.55
                    end if
                    if shuffling enabled then set shuffling to true
                    if repeating enabled then set repeating to true
                    next track
                    set sound volume to \(volPercent)
                end tell
                """
                var scriptSucceeded = true
                if wasAlreadyControlled && isSameURI {
                    let state = Self.executeOsaScript("tell application \"Spotify\" to if it is running then return (player state as string)")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if state == "paused" {
                        scriptSucceeded = Self.executeOsaScript("""
                        tell application "Spotify"
                            set sound volume to \(volPercent)
                            if shuffling enabled then set shuffling to true
                            if repeating enabled then set repeating to true
                            play
                        end tell
                        """) != nil
                    } else if state != "playing" {
                        scriptSucceeded = Self.executeOsaScript(playPlaylistScript) != nil
                    } else {
                        scriptSucceeded = Self.executeOsaScript("""
                        tell application "Spotify"
                            if shuffling enabled then set shuffling to true
                            set sound volume to \(volPercent)
                        end tell
                        """) != nil
                    }
                } else {
                    scriptSucceeded = Self.executeOsaScript(playPlaylistScript) != nil
                }
                if !scriptSucceeded, let url = URL(string: uri) {
                    _ = await MainActor.run {
                        NSWorkspace.shared.open(url)
                    }
                }
                if !spotifyWasFrontmost {
                    await MainActor.run {
                        if let sp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first, sp.isActive {
                            sp.hide()
                            previousFrontApp?.activate()
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: 550_000_000)
                return Self.fetchSpotifyTrack()
            }.value
            guard let self, self.spotifyControlled else { return }
            self.nowPlayingTrack = info
        }
        startSpotifyPolling()
    }

    nonisolated private static func ensureSpotifyRunningInBackground() {
        let wasAlreadyRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
        if !wasAlreadyRunning {
            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            launcher.arguments = ["-g", "-j", "-b", "com.spotify.client"]
            launcher.standardOutput = FileHandle.nullDevice
            launcher.standardError = FileHandle.nullDevice
            try? launcher.run()
            launcher.waitUntilExit()
            for _ in 0..<30 {
                if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty {
                    break
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            // Wait until Spotify's AppleScript player dictionary is initialized on cold start.
            for _ in 0..<20 {
                let state = executeOsaScript("tell application \"Spotify\" to if it is running then return (player state as string)")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if state == "stopped" || state == "paused" || state == "playing" {
                    Thread.sleep(forTimeInterval: 0.35)
                    break
                }
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
    }

    private func pauseSpotify() {
        spotifyControlled = false
        spotifyPollTask?.cancel()
        spotifyPollTask = nil
        nowPlayingTrack = nil
        runSpotifyScript("tell application \"Spotify\" to if it is running then pause")
    }

    private func startSpotifyPolling() {
        spotifyPollTask?.cancel()
        spotifyPollTask = Task { [weak self] in
            while !Task.isCancelled {
                let info = await Task.detached { Self.fetchSpotifyTrack() }.value
                guard !Task.isCancelled, let self, self.spotifyControlled else { return }
                self.nowPlayingTrack = info
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    private func runSpotifyScript(_ source: String) {
        Task.detached {
            _ = Self.executeOsaScript(source)
        }
    }

    nonisolated private static func fetchSpotifyTrack() -> String? {
        let script = """
        tell application "Spotify"
            if it is running and player state is playing then
                return (artist of current track) & " – " & (name of current track)
            end if
        end tell
        return ""
        """
        let output = executeOsaScript(script)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return output.isEmpty ? nil : output
    }

    @discardableResult
    nonisolated private static func executeOsaScript(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
