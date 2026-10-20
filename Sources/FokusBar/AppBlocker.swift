import AppKit
import SwiftUI
import Foundation
import UniformTypeIdentifiers
import FocusCore

public enum FocusGuardIntent: String, Equatable, Sendable {
    case pause
    case stop
    case unlockBlocker

    var title: String {
        switch self {
        case .pause: "Fokus wirklich pausieren?"
        case .stop: "Fokus-Sitzung wirklich abbrechen?"
        case .unlockBlocker: "App- & Web-Blocker wirklich entsperren?"
        }
    }

    var subtitle: String {
        switch self {
        case .pause:
            "Bevor du deinen Fokus unterbrichst: Nimm dir einen Moment zum bewussten Durchatmen. Meistens verschwindet der Ablenkungs-Impuls nach wenigen Atemzügen."
        case .stop:
            "Bevor du die laufende Fokus-Sitzung vorzeitig abbrichst: Atme ruhig durch und prüfe, ob du nicht doch noch ein paar Minuten im Flow bleiben kannst."
        case .unlockBlocker:
            "Während einer laufenden Fokus-Sitzung sind blockierte Apps & Webseiten geschützt. Atme erst ruhig durch, bevor du die Sperre aufhebst."
        }
    }

    var confirmButtonTitle: String {
        switch self {
        case .pause: "Fokus jetzt pausieren"
        case .stop: "Fokus-Sitzung jetzt beenden"
        case .unlockBlocker: "Blocker jetzt entsperren"
        }
    }

    static let requiredPhrase = "Ich unterbreche meinen Fokus bewusst"
}

public enum BlockerSelectorTab: String, CaseIterable, Identifiable {
    case websites = "Webseiten"
    case apps = "Apps"
    public var id: String { rawValue }
}

@MainActor
final class AppBlockerController {
    private let preview: Bool
    private var activeBlockedBundleIDs: Set<String> = []
    private var activeBlockedNames: [String: String] = [:]
    private var activeBlockedWebsites: [String] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var watchdogTask: Task<Void, Never>?
    private var lastInterceptNoticeAt: [String: Date] = [:]
    private var isCheckingBrowsers = false

    var onAppBlocked: ((String) -> Void)?
    var onWebsiteBlocked: ((String) -> Void)?

    private static var iconCache: [String: NSImage] = [:]

    /// Common communication, social, messenger, mail, gaming & entertainment apps surfaced as quick suggestions when installed on the user's Mac.
    /// Note: Web browsers and Spotify are intentionally kept separate so 1-click app blocking never closes the user's work browser or Spotify Focus music.
    static let commonDistractionBundleIDs: Set<String> = [
        "net.whatsapp.whatsapp",
        "desktop.whatsapp",
        "ru.keepcoder.telegram",
        "com.tdesktop.telegram",
        "org.telegram.desktop",
        "com.hnc.discord",
        "com.hnc.discordptb",
        "com.hnc.discordcanary",
        "org.whispersystems.signal-desktop",
        "com.tinyspeck.slackmacgap",
        "ch.threema.threema-desktop",
        "ch.threema.work.desktop",
        "facebook.avc",
        "com.facebook.archon",
        "com.apple.mobilesms",
        "com.apple.mail",
        "com.apple.facetime",
        "com.readdle.smartemail-mac",
        "com.readdle.sparkdesktop",
        "com.microsoft.outlook",
        "org.mozilla.thunderbird",
        "com.mimestream.mimestream",
        "com.valvesoftware.steam",
        "com.epicgames.epicgameslauncher",
        "net.battle.app",
        "com.riotgames.leagueoflegends.leagueclientux",
        "com.riotgames.riotgames.riotclient",
        "com.mojang.minecraftlauncher",
        "com.apple.tv",
        "com.apple.podcasts",
        "com.apple.news",
        "com.apple.chess",
        "com.apple.photobooth",
        "com.colliderli.iina",
        "org.videolan.vlc"
    ]

    /// Priority order for surfacing up to 4 quick 1-click app chips directly in the Timer Start Card.
    private static let priorityQuickChipBundleIDs: [String] = [
        "net.whatsapp.whatsapp",
        "desktop.whatsapp",
        "com.hnc.discord",
        "ru.keepcoder.telegram",
        "com.tdesktop.telegram",
        "org.whispersystems.signal-desktop",
        "com.tinyspeck.slackmacgap",
        "com.apple.mobilesms",
        "com.apple.mail",
        "com.valvesoftware.steam",
        "com.apple.tv",
        "com.apple.podcasts",
        "com.apple.news",
        "com.apple.facetime"
    ]

    private static let chromiumBrowsers: [(bundleID: String, appName: String)] = [
        ("com.google.Chrome", "Google Chrome"),
        ("com.google.Chrome.canary", "Google Chrome Canary"),
        ("com.brave.Browser", "Brave Browser"),
        ("com.brave.Browser.beta", "Brave Browser Beta"),
        ("company.thebrowser.Browser", "Arc"),
        ("com.microsoft.edgemac", "Microsoft Edge"),
        ("com.vivaldi.Vivaldi", "Vivaldi"),
        ("com.operasoftware.Opera", "Opera"),
        ("com.operasoftware.OperaGX", "Opera GX"),
        ("org.chromium.Chromium", "Chromium")
    ]

    private static let webkitBrowsers: [(bundleID: String, appName: String)] = [
        ("com.apple.Safari", "Safari"),
        ("com.apple.SafariTechnologyPreview", "Safari Technology Preview"),
        ("com.kagi.kagimacOS", "Orion")
    ]

    /// Browsers without a standard Chromium/Safari AppleScript tab dictionary – monitored via window titles (`CGWindowListCopyWindowInfo` / `System Events`).
    private static let nonScriptableBrowsers: [(bundleID: String, appName: String)] = [
        ("org.mozilla.firefox", "Firefox"),
        ("app.zen-browser.zen", "Zen Browser"),
        ("org.mozilla.com.zen.browser", "Zen Browser"),
        ("com.duckduckgo.macos.browser", "DuckDuckGo"),
        ("org.WaterfoxProject.Waterfox", "Waterfox"),
        ("org.mozilla.librewolf", "LibreWolf"),
        ("one.ablaze.floorp", "Floorp")
    ]

    /// Dedicated anonymizing/proxy browsers automatically blocked whenever website blocking is active so users cannot switch to Tor/Mullvad Browser to bypass website rules.
    static let bypassBrowserBundleIDs: [String: String] = [
        "org.torproject.torbrowser": "Tor Browser (Proxy-Schutz)",
        "net.mullvad.mullvadbrowser": "Mullvad Browser (Proxy-Schutz)",
        "com.epicbrowser.epic": "Epic Proxy Browser (Proxy-Schutz)"
    ]

    /// Known macOS VPN, Proxy & Anti-Detect Browser Launcher clients surfaced automatically in App Discovery.
    static let vpnAndProxyBundleIDs: Set<String> = [
        "com.nordvpn.macos",
        "com.nordvpn.osx",
        "ch.protonvpn.mac",
        "net.mullvad.vpn",
        "com.expressvpn.expressvpn",
        "com.surfshark.vpnclient.macos",
        "com.cloudflare.1dot1dot1dot1.macos",
        "com.windscribe.launcher.macos",
        "com.tunnelbear.mac.tunnelbear",
        "com.adguard.mac.vpn",
        "com.wireguard.macos",
        "org.openvpn.client.app",
        "com.qiuyuzhou.shadowsocksx-ng",
        "com.west2online.clashx",
        "com.proxyman.nsproxy",
        "com.xk72.charles",
        // Anti-Detect Browsers
        "com.ru.dolphin.anty",
        "com.adspower.global",
        "com.adspower.adspower",
        "com.gologin.desktop",
        "com.multilogin.app",
        "com.incogniton.app",
        "net.octobrowser.app",
        "com.morelogin.app",
        "io.undetectable.app",
        "com.bitbrowser.app",
        "com.hidemyacc.app",
        "com.ixbrowser.app",
        "com.nstbrowser.app"
    ]

    /// Maps Anti-Detect Browser launcher bundle IDs to the hidden child browser bundle IDs they spawn for proxy profiles.
    private static let antiDetectParentToChildBundleIDs: [String: [String]] = [
        "com.ru.dolphin.anty": ["org.anty.anty", "com.dolphin.anty.browser"],
        "com.adspower.global": ["com.adspower.sunbrowser", "org.adspower.sunbrowser", "com.adspower.flowerbrowser"],
        "com.adspower.adspower": ["com.adspower.sunbrowser", "org.adspower.sunbrowser", "com.adspower.flowerbrowser"],
        "com.gologin.desktop": ["com.gologin.orbita", "org.gologin.orbita"],
        "com.multilogin.app": ["com.multilogin.mimic", "com.multilogin.stealthfox"]
    ]

    /// Path fragments inside `~/Library/Application Support` or `~` used by Anti-Detect Browsers to spawn proxy profile browser instances.
    private static let antiDetectChildPathFragments: [String: String] = [
        "com.ru.dolphin.anty": "/dolphin_anty/",
        "com.adspower.global": "/adspower_global/",
        "com.adspower.adspower": "/adspower_global/",
        "com.gologin.desktop": "/.gologin/",
        "com.multilogin.app": "/multilogin/",
        "com.incogniton.app": "/incogniton/",
        "net.octobrowser.app": "/octo browser/",
        "com.morelogin.app": "/morelogin/",
        "io.undetectable.app": "/undetectable/"
    ]

    /// Known child browser bundle IDs spawned by Anti-Detect Browsers (Dolphin Anty, AdsPower SunBrowser/FlowerBrowser, GoLogin Orbita, Multilogin Mimic/Stealthfox, Octo, Incogniton, MoreLogin, Undetectable).
    private static let antiDetectEngineBundleIDs: Set<String> = [
        "org.anty.anty",
        "com.dolphin.anty.browser",
        "com.adspower.sunbrowser",
        "org.adspower.sunbrowser",
        "com.adspower.flowerbrowser",
        "com.gologin.orbita",
        "org.gologin.orbita",
        "com.multilogin.mimic",
        "com.multilogin.stealthfox"
    ]

    /// Returns true if a running application is a spawned Anti-Detect Browser profile instance (e.g. Anty.app, SunBrowser.app, Orbita-Browser.app).
    private static func isAntiDetectProfileBrowser(_ app: NSRunningApplication) -> Bool {
        if let rawID = app.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           antiDetectEngineBundleIDs.contains(rawID) {
            return true
        }
        if let path = app.bundleURL?.path.lowercased() {
            for fragment in antiDetectChildPathFragments.values where path.contains(fragment) {
                return true
            }
        }
        return false
    }

    init(preview: Bool) {
        self.preview = preview
    }

    func sync(
        isBlocking: Bool,
        blockedApps: [BlockedApp],
        blockedWebsites: [String],
        keepSpotifyAlive: Bool = false
    ) {
        guard !preview, isBlocking, (!blockedApps.isEmpty || !blockedWebsites.isEmpty) else {
            stopBlocking()
            return
        }

        var ids = Set<String>()
        var names: [String: String] = [:]
        for item in blockedApps {
            let lower = item.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !lower.isEmpty, !BlockedApp.isProtected(lower) else { continue }
            if keepSpotifyAlive && lower == "com.spotify.client" { continue }
            ids.insert(lower)
            names[lower] = item.name
            // If an Anti-Detect Browser launcher (e.g. Dolphin Anty, AdsPower, GoLogin) is blocked,
            // automatically block its spawned proxy profile browser processes (Anty.app, SunBrowser.app, Orbita-Browser.app) too.
            if let childIDs = Self.antiDetectParentToChildBundleIDs[lower] {
                for childID in childIDs {
                    ids.insert(childID)
                    names[childID] = "\(item.name) (Profil-Browser)"
                }
            }
        }

        let normalizedSites = blockedWebsites.compactMap { BlockedWebsite.normalizeDomain($0) }

        // Automatically block dedicated proxy/anonymizer browsers (Tor Browser, Mullvad Browser) when website blocking is active
        if !normalizedSites.isEmpty {
            for (bundleID, label) in Self.bypassBrowserBundleIDs {
                ids.insert(bundleID)
                names[bundleID] = label
            }
        }

        guard !ids.isEmpty || !normalizedSites.isEmpty else {
            stopBlocking()
            return
        }

        activeBlockedBundleIDs = ids
        activeBlockedNames = names
        activeBlockedWebsites = normalizedSites

        installObserversIfNeeded()
        enforceBlockedApps(announce: false)
        enforceBlockedWebsites(announce: false)
    }

    func stopBlocking() {
        activeBlockedBundleIDs.removeAll()
        activeBlockedNames.removeAll()
        activeBlockedWebsites.removeAll()
        watchdogTask?.cancel()
        watchdogTask = nil
        let center = NSWorkspace.shared.notificationCenter
        for obs in workspaceObservers {
            center.removeObserver(obs)
        }
        workspaceObservers.removeAll()
    }

    private func installObserversIfNeeded() {
        if workspaceObservers.isEmpty {
            let center = NSWorkspace.shared.notificationCenter
            let names: [NSNotification.Name] = [
                NSWorkspace.willLaunchApplicationNotification,
                NSWorkspace.didLaunchApplicationNotification,
                NSWorkspace.didActivateApplicationNotification
            ]
            for notifName in names {
                let obs = center.addObserver(forName: notifName, object: nil, queue: .main) { [weak self] notification in
                    let runningApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if let runningApp {
                            self.interceptIfNeeded(runningApp, announce: true)
                        } else {
                            self.enforceBlockedApps(announce: true)
                        }
                    }
                }
                workspaceObservers.append(obs)
            }
        }

        if watchdogTask == nil {
            watchdogTask = Task { [weak self] in
                var tickCount = 0
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    guard !Task.isCancelled, let self,
                          (!self.activeBlockedBundleIDs.isEmpty || !self.activeBlockedWebsites.isEmpty) else { return }
                    self.enforceBlockedApps(announce: true)
                    tickCount += 1
                    if !self.activeBlockedWebsites.isEmpty && tickCount % 2 == 0 {
                        self.enforceBlockedWebsites(announce: true)
                    }
                }
            }
        }
    }

    private func enforceBlockedApps(announce: Bool) {
        guard !activeBlockedBundleIDs.isEmpty else { return }
        for app in NSWorkspace.shared.runningApplications {
            interceptIfNeeded(app, announce: announce)
        }
    }

    private func interceptIfNeeded(_ app: NSRunningApplication, announce: Bool) {
        guard !app.isTerminated else { return }
        let rawID = app.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if !rawID.isEmpty && BlockedApp.isProtected(rawID) {
            return
        }

        var matchedKey: String?
        if !rawID.isEmpty && activeBlockedBundleIDs.contains(rawID) {
            matchedKey = rawID
        } else if let appPath = app.bundleURL?.path.lowercased() {
            for (parentID, fragment) in Self.antiDetectChildPathFragments where activeBlockedBundleIDs.contains(parentID) {
                if appPath.contains(fragment) {
                    matchedKey = parentID
                    break
                }
            }
        }

        guard let blockedKey = matchedKey else { return }

        let displayName = activeBlockedNames[blockedKey] ?? app.localizedName ?? blockedKey
        app.hide()
        _ = app.terminate()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 550_000_000)
            if !app.isTerminated {
                _ = app.forceTerminate()
            }
        }

        if announce {
            let now = Date()
            if now.timeIntervalSince(lastInterceptNoticeAt[blockedKey] ?? .distantPast) > 2.5 {
                lastInterceptNoticeAt[blockedKey] = now
                onAppBlocked?(displayName)
            }
        }
    }

    // MARK: - Browser Website Blocking

    private func enforceBlockedWebsites(announce: Bool) {
        guard !preview, !activeBlockedWebsites.isEmpty, !isCheckingBrowsers else { return }
        let expandedDomains = BlockedWebsite.expandedDomains(for: activeBlockedWebsites)
        let canonicalDomains = activeBlockedWebsites
        guard !expandedDomains.isEmpty else { return }

        let runningChromium = Self.chromiumBrowsers.filter { browser in
            !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty &&
            !activeBlockedBundleIDs.contains(browser.bundleID.lowercased())
        }
        let runningWebKit = Self.webkitBrowsers.filter { browser in
            !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty &&
            !activeBlockedBundleIDs.contains(browser.bundleID.lowercased())
        }
        let runningNonScriptable = Self.nonScriptableBrowsers.filter { browser in
            !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty &&
            !activeBlockedBundleIDs.contains(browser.bundleID.lowercased())
        }

        // Detect running Anti-Detect Browser profile instances (Dolphin Anty's Anty.app, AdsPower's SunBrowser.app / FlowerBrowser.app, GoLogin's Orbita-Browser.app, Multilogin's Mimic/Stealthfox, etc.)
        var dynamicAntiDetectScriptTargets: [String] = []
        var runningAntiDetectApps: [NSRunningApplication] = []
        for app in NSWorkspace.shared.runningApplications where !app.isTerminated {
            guard Self.isAntiDetectProfileBrowser(app) else { continue }
            runningAntiDetectApps.append(app)
            if let bundlePath = app.bundleURL?.path,
               !dynamicAntiDetectScriptTargets.contains(bundlePath) {
                let sdefPath = (bundlePath as NSString).appendingPathComponent("Contents/Resources/scripting.sdef")
                if FileManager.default.fileExists(atPath: sdefPath) {
                    dynamicAntiDetectScriptTargets.append(bundlePath)
                }
            }
        }

        // Also inspect on-screen window titles for non-AppleScript browsers (Firefox, Zen, DuckDuckGo, LibreWolf)
        // AND for Anti-Detect profile browsers (catches multi-profile instances and Firefox-based engines like FlowerBrowser/Stealthfox)
        if !runningNonScriptable.isEmpty || !runningAntiDetectApps.isEmpty {
            enforceNonScriptableBrowserWindowTitles(
                runningBrowsers: runningNonScriptable,
                extraRunningApps: runningAntiDetectApps,
                canonicalDomains: canonicalDomains,
                announce: announce
            )
        }

        let chromiumNames = runningChromium.map(\.appName) + dynamicAntiDetectScriptTargets
        let webkitNames = runningWebKit.map(\.appName)
        guard !chromiumNames.isEmpty || !webkitNames.isEmpty else { return }
        isCheckingBrowsers = true

        Task { [weak self] in
            let closedURLs = await Task.detached(priority: .utility) {
                Self.closeMatchingBrowserTabs(
                    expandedDomains: expandedDomains,
                    chromiumApps: chromiumNames,
                    webkitApps: webkitNames
                )
            }.value
            guard let self else { return }
            self.isCheckingBrowsers = false
            guard announce, !closedURLs.isEmpty else { return }
            for url in closedURLs {
                if let matched = BlockedWebsite.matchedDomain(for: url, in: canonicalDomains) {
                    let key = "web:\(matched)"
                    let now = Date()
                    if now.timeIntervalSince(self.lastInterceptNoticeAt[key] ?? .distantPast) > 3.0 {
                        self.lastInterceptNoticeAt[key] = now
                        self.onWebsiteBlocked?(BlockedWebsite.displayName(for: matched))
                    }
                }
            }
        }
    }

    private func enforceNonScriptableBrowserWindowTitles(
        runningBrowsers: [(bundleID: String, appName: String)],
        extraRunningApps: [NSRunningApplication] = [],
        canonicalDomains: [String],
        announce: Bool
    ) {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return
        }
        var pidToBrowser: [pid_t: NSRunningApplication] = [:]
        for browser in runningBrowsers {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID) {
                pidToBrowser[app.processIdentifier] = app
            }
        }
        for app in extraRunningApps {
            pidToBrowser[app.processIdentifier] = app
        }
        guard !pidToBrowser.isEmpty else { return }

        for entry in windowList {
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let app = pidToBrowser[pid],
                  let title = (entry[kCGWindowName as String] as? String)?.lowercased(),
                  !title.isEmpty else { continue }

            for domain in canonicalDomains {
                let keyword = domain.components(separatedBy: ".").first ?? domain
                let matchesTitle = (keyword.count >= 3 && title.contains(keyword)) ||
                    (domain == "x.com" && (title.contains(" / x") || title.contains("twitter")))
                if matchesTitle {
                    app.hide()
                    if announce {
                        let key = "web-win:\(domain)"
                        let now = Date()
                        if now.timeIntervalSince(lastInterceptNoticeAt[key] ?? .distantPast) > 3.0 {
                            lastInterceptNoticeAt[key] = now
                            onWebsiteBlocked?(BlockedWebsite.displayName(for: domain))
                        }
                    }
                    break
                }
            }
        }
    }

    nonisolated private static func closeMatchingBrowserTabs(
        expandedDomains: [String],
        chromiumApps: [String],
        webkitApps: [String]
    ) -> [String] {
        let appleScriptList = expandedDomains
            .map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"" }
            .joined(separator: ", ")

        var scriptLines: [String] = [
            "set blockedList to {\(appleScriptList)}",
            "set closedURLs to {}"
        ]

        for appName in (chromiumApps + webkitApps) {
            scriptLines.append("""
            try
                tell application "\(appName)"
                    repeat with w in windows
                        set tabList to tabs of w
                        repeat with t in tabList
                            try
                                set u to URL of t
                                if u is not missing value then
                                    repeat with d in blockedList
                                        set dom to contents of d
                                        if u contains ("://" & dom) or u contains ("." & dom & "/") or u ends with ("." & dom) or u contains ("/" & dom & "/") or u contains ("=" & dom) or u contains ("%2F" & dom) or u contains ("%2f" & dom) then
                                            set end of closedURLs to u
                                            close t
                                            exit repeat
                                        end if
                                    end repeat
                                end if
                            end try
                        end repeat
                    end repeat
                end tell
            end try
            """)
        }

        scriptLines.append("""
        set AppleScript's text item delimiters to "\\n"
        return closedURLs as string
        """)

        let fullScript = scriptLines.joined(separator: "\n")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", fullScript]
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return [] }
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return [] }
            return text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        } catch {
            return []
        }
    }

    // MARK: - App Discovery & Icons

    static func icon(for app: BlockedApp) -> NSImage {
        let key = app.bundleIdentifier.lowercased()
        if let cached = iconCache[key] {
            return cached
        }
        if let path = app.path, FileManager.default.fileExists(atPath: path) {
            let img = NSWorkspace.shared.icon(forFile: path)
            img.size = NSSize(width: 24, height: 24)
            iconCache[key] = img
            return img
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
            let img = NSWorkspace.shared.icon(forFile: url.path)
            img.size = NSSize(width: 24, height: 24)
            iconCache[key] = img
            return img
        }
        let fallback = NSImage(systemSymbolName: "app.fill", accessibilityDescription: app.name) ?? NSImage()
        return fallback
    }

    static func blockedApp(from bundleURL: URL) -> BlockedApp? {
        guard bundleURL.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: bundleURL),
              let bundleID = bundle.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleID.isEmpty,
              !BlockedApp.isProtected(bundleID) else {
            return nil
        }
        let localizedFileName = FileManager.default.displayName(atPath: bundleURL.path).replacingOccurrences(of: ".app", with: "")
        let displayName = (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (!localizedFileName.isEmpty ? localizedFileName : nil)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? bundleID
        return BlockedApp(bundleIdentifier: bundleID, name: displayName, path: bundleURL.path)
    }

    /// Automatically detects supported browsers installed on the current Mac.
    static func discoverInstalledBrowsers() -> [String] {
        var found: [String] = []
        var seen = Set<String>()
        for browser in (webkitBrowsers + chromiumBrowsers + nonScriptableBrowsers) {
            if !seen.contains(browser.appName),
               NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) != nil {
                seen.insert(browser.appName)
                found.append(browser.appName)
            }
        }
        return found
    }

    private static func isDistractionPWA(_ app: BlockedApp) -> Bool {
        let lowerID = app.bundleIdentifier.lowercased()
        let isPWA = lowerID.hasPrefix("com.apple.safari.webapp.") ||
            lowerID.hasPrefix("com.google.chrome.app.") ||
            lowerID.hasPrefix("com.brave.browser.app.") ||
            lowerID.hasPrefix("com.microsoft.edgemac.app.")
        guard isPWA else { return false }
        let lowerName = app.name.lowercased()
        let keywords = ["instagram", "youtube", "tiktok", "netflix", "twitch", "reddit", "twitter", "whatsapp", "discord", "telegram", "facebook"]
        return keywords.contains { lowerName.contains($0) }
    }

    /// Automatically scans the current Mac for running applications, LaunchServices-registered apps, and `.app` bundles in `/Applications`, `~/Applications`, and `/System/Applications` (including 1st-level subfolders like Setapp or Dock Web Apps).
    static func discoverInstalledApps() -> (running: [BlockedApp], suggestions: [BlockedApp], quickChips: [BlockedApp], all: [BlockedApp]) {
        var byID: [String: BlockedApp] = [:]
        var runningIDs = Set<String>()

        // 1. Currently running regular applications
        for running in NSWorkspace.shared.runningApplications where running.activationPolicy == .regular {
            guard let id = running.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty,
                  !BlockedApp.isProtected(id) else { continue }
            let lower = id.lowercased()
            runningIDs.insert(lower)
            let name = running.localizedName ?? id
            let path = running.bundleURL?.path
            byID[lower] = BlockedApp(bundleIdentifier: id, name: name, path: path)
        }

        // 2. LaunchServices lookup for known distraction apps, VPN/Proxy clients & browsers (finds apps anywhere on the Mac)
        let launchServicesProbeIDs = Array(commonDistractionBundleIDs) +
            Array(vpnAndProxyBundleIDs) +
            chromiumBrowsers.map(\.bundleID) +
            webkitBrowsers.map(\.bundleID) +
            nonScriptableBrowsers.map(\.bundleID)
        for probeID in launchServicesProbeIDs {
            let lower = probeID.lowercased()
            guard byID[lower] == nil,
                  let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: probeID),
                  let app = blockedApp(from: appURL) else { continue }
            byID[app.bundleIdentifier.lowercased()] = app
        }

        // 3. Scan standard application directories + 1 level of subdirectories (Setapp, Utilities, Chrome/Safari Web Apps)
        let roots: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true)
        ]

        let fm = FileManager.default
        for root in roots {
            guard let level1 = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in level1 {
                if url.pathExtension.lowercased() == "app" {
                    if let app = blockedApp(from: url) {
                        let lower = app.bundleIdentifier.lowercased()
                        if byID[lower] == nil {
                            byID[lower] = app
                        }
                    }
                } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    guard let level2 = try? fm.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    ) else { continue }
                    for subURL in level2 where subURL.pathExtension.lowercased() == "app" {
                        if let app = blockedApp(from: subURL) {
                            let lower = app.bundleIdentifier.lowercased()
                            if byID[lower] == nil {
                                byID[lower] = app
                            }
                        }
                    }
                }
            }
        }

        let allSorted = byID.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        let runningApps = allSorted.filter {
            let lower = $0.bundleIdentifier.lowercased()
            return runningIDs.contains(lower) && lower != "com.spotify.client"
        }
        let suggestions = allSorted.filter {
            let lower = $0.bundleIdentifier.lowercased()
            return commonDistractionBundleIDs.contains(lower) || isDistractionPWA($0)
        }

        // Build up to 4 quick-access app chips tailored to THIS Mac (prioritizing running distractions, then installed priority distractions)
        var quickChips: [BlockedApp] = []
        var quickSeen = Set<String>()
        for app in suggestions where runningIDs.contains(app.bundleIdentifier.lowercased()) {
            let lower = app.bundleIdentifier.lowercased()
            if !quickSeen.contains(lower) {
                quickSeen.insert(lower)
                quickChips.append(app)
            }
        }
        for prioID in priorityQuickChipBundleIDs {
            if let app = byID[prioID.lowercased()], !quickSeen.contains(prioID.lowercased()) {
                quickSeen.insert(prioID.lowercased())
                quickChips.append(app)
            }
        }
        for app in suggestions where !quickSeen.contains(app.bundleIdentifier.lowercased()) {
            quickSeen.insert(app.bundleIdentifier.lowercased())
            quickChips.append(app)
        }

        return (
            running: runningApps,
            suggestions: suggestions,
            quickChips: Array(quickChips.prefix(4)),
            all: allSorted
        )
    }
}

// MARK: - App & Website Blocker SwiftUI Components

struct BlockedAppIconView: View {
    let app: BlockedApp
    var size: CGFloat = 16

    var body: some View {
        Image(nsImage: AppBlockerController.icon(for: app))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

struct BlockedAppSelectorPopover: View {
    @ObservedObject var store: FocusStore
    @State var selectedTab: BlockerSelectorTab = .websites
    @State private var searchText = ""
    @State private var customDomainInput = ""
    @State private var domainError: String?
    @State private var catalog = AppBlockerController.discoverInstalledApps()
    @State private var detectedBrowsers = AppBlockerController.discoverInstalledBrowsers()

    private var filteredAll: [BlockedApp] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return catalog.all }
        return catalog.all.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            $0.bundleIdentifier.localizedCaseInsensitiveContains(q)
        }
    }

    private var customBlockedDomains: [String] {
        let presetSet = Set(BlockedWebsite.presets.map(\.domain))
        return store.blockedWebsites.filter { !presetSet.contains($0) }
    }

    var body: some View {
        let totalCount = store.totalBlockedItemsCount

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Ablenkungen im Fokus blockieren", systemImage: "lock.shield.fill")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(FokusTheme.accent)
                Spacer()
                if totalCount > 0 {
                    Text("\(totalCount) aktiv")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(FokusTheme.accent.opacity(0.14)))
                        .foregroundStyle(FokusTheme.accent)
                }
            }

            Picker("Kategorie", selection: $selectedTab) {
                Text("Webseiten (\(store.blockedWebsites.count))").tag(BlockerSelectorTab.websites)
                Text("Apps (\(store.blockedApps.count))").tag(BlockerSelectorTab.apps)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if selectedTab == .websites {
                websitesTabContent
            } else {
                appsTabContent
            }

            Divider()

            HStack {
                if selectedTab == .apps {
                    Button {
                        store.pickBlockedAppFromFinder()
                        catalog = AppBlockerController.discoverInstalledApps()
                    } label: {
                        Label("Aus Programme-Ordner …", systemImage: "folder.badge.plus")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(FokusTheme.accent)
                } else {
                    Text(
                        detectedBrowsers.isEmpty
                            ? "Schließt offene Tabs in Safari, Chrome, Arc & Brave sofort."
                            : "Erkannte Browser: \(detectedBrowsers.joined(separator: ", "))"
                    )
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer()

                if totalCount > 0 {
                    Toggle("Aktiv", isOn: Binding(
                        get: { store.preferences.isAppBlockerEnabled },
                        set: { store.setAppBlockerEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 11.5))
                }
            }
        }
        .padding(14)
        .frame(width: 360)
        .onAppear {
            catalog = AppBlockerController.discoverInstalledApps()
            detectedBrowsers = AppBlockerController.discoverInstalledBrowsers()
        }
    }

    // MARK: Websites Tab

    private var websitesTabContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Blockierte Webseiten wie Instagram, YouTube oder X.com werden während deiner Fokus-Sitzung im Browser automatisch geschlossen.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                TextField("Eigene Webseite (z. B. instagram.com, twitch.tv …)", text: $customDomainInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .onSubmit {
                        submitCustomDomain()
                    }
                Button("Blockieren") {
                    submitCustomDomain()
                }
                .buttonStyle(FokusSoftButtonStyle())
                .controlSize(.small)
                .disabled(customDomainInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(FokusTheme.track)
            )

            if let domainError {
                Text(domainError)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("BELIEBTE ABLENKUNGEN (1-KLICK)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                store.blockTopSocialWebsites()
                            } label: {
                                Text("Top 5 aktivieren")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(FokusTheme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 4)

                        VStack(spacing: 2) {
                            ForEach(BlockedWebsite.presets) { preset in
                                let isSelected = store.isWebsiteBlocked(preset.domain)
                                Button {
                                    store.toggleBlockedWebsite(preset.domain)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: preset.icon)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(isSelected ? FokusTheme.accent : .secondary)
                                            .frame(width: 20)
                                        VStack(alignment: .leading, spacing: 0.5) {
                                            Text(preset.title)
                                                .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                                                .foregroundStyle(.primary)
                                            Text(preset.domain)
                                                .font(.system(size: 10.5))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 14))
                                            .foregroundStyle(isSelected ? FokusTheme.accent : Color.secondary.opacity(0.45))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(isSelected ? FokusTheme.accent.opacity(0.10) : Color.clear)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !customBlockedDomains.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("EIGENE BLOCKIERTE DOMAINS")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            VStack(spacing: 2) {
                                ForEach(customBlockedDomains, id: \.self) { domain in
                                    HStack(spacing: 8) {
                                        Image(systemName: "globe")
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .foregroundStyle(FokusTheme.accent)
                                            .frame(width: 20)
                                        Text(domain)
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Button {
                                            store.removeBlockedWebsite(domain)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 13))
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(FokusTheme.accent.opacity(0.10))
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 240)
        }
    }

    private func submitCustomDomain() {
        let raw = customDomainInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        if store.addBlockedWebsite(raw) {
            customDomainInput = ""
            domainError = nil
        } else {
            domainError = "Bitte gib eine gültige Domain ein (z. B. instagram.com oder youtube.com)."
        }
    }

    // MARK: Apps Tab

    private var appsTabContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FokusBar erkennt installierte Apps auf deinem Mac automatisch. Ausgewählte Apps werden beim Fokus-Start geschlossen und gesperrt.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                TextField("App suchen (z. B. WhatsApp, Discord, Mail …)", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(FokusTheme.track)
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if !store.blockedApps.isEmpty {
                            appSection(title: "Blockiert (\(store.blockedApps.count))", items: store.blockedApps)
                        }
                        if !catalog.suggestions.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("AUF DIESEM MAC ERKANNTE ABLENKUNGEN (\(catalog.suggestions.count))")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button {
                                        store.blockDetectedDistractionApps(catalog.suggestions)
                                    } label: {
                                        Text("Alle auswählen")
                                            .font(.system(size: 10.5, weight: .semibold))
                                            .foregroundStyle(FokusTheme.accent)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 4)

                                appRows(items: catalog.suggestions)
                            }
                        }
                        if !catalog.running.isEmpty {
                            appSection(title: "Gerade geöffnet", items: catalog.running)
                        }
                        appSection(title: "Alle installierten Apps (\(catalog.all.count))", items: catalog.all)
                    } else {
                        if filteredAll.isEmpty {
                            Text("Keine passende App gefunden.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            appSection(title: "Suchergebnisse", items: filteredAll)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 240)
        }
    }

    private func appSection(title: String, items: [BlockedApp]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            appRows(items: items)
        }
    }

    private func appRows(items: [BlockedApp]) -> some View {
        VStack(spacing: 2) {
            ForEach(items) { app in
                let isSelected = store.isAppBlocked(app)
                Button {
                    store.toggleBlockedApp(app)
                } label: {
                    HStack(spacing: 8) {
                        BlockedAppIconView(app: app, size: 18)
                        Text(app.name)
                            .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14))
                            .foregroundStyle(isSelected ? FokusTheme.accent : Color.secondary.opacity(0.45))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelected ? FokusTheme.accent.opacity(0.10) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct FocusAppBlockerStartPicker: View {
    @ObservedObject var store: FocusStore
    @State private var showsSelector = false
    @State private var initialTab: BlockerSelectorTab = .websites
    @State private var detectedQuickApps: [BlockedApp] = AppBlockerController.discoverInstalledApps().quickChips

    var body: some View {
        let blockedApps = store.blockedApps
        let blockedSites = store.blockedWebsites
        let totalCount = store.totalBlockedItemsCount
        let isEnabled = store.preferences.isAppBlockerEnabled
        let activeCount = isEnabled ? totalCount : 0

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Button {
                    if totalCount > 0 {
                        store.setAppBlockerEnabled(!isEnabled)
                    } else {
                        initialTab = .websites
                        showsSelector = true
                    }
                } label: {
                    Label(
                        "App- & Web-Blocker",
                        systemImage: (isEnabled && totalCount > 0) ? "lock.shield.fill" : "lock.shield"
                    )
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle((isEnabled && totalCount > 0) ? FokusTheme.accent : Color.secondary)
                    .lineLimit(1)
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .help(totalCount == 0 ? "Apps & Webseiten zum Blockieren auswählen" : (isEnabled ? "Blocker ausschalten" : "Blocker einschalten"))

                if totalCount > 0 {
                    Text(isEnabled ? "\(activeCount) aktiv" : "Pausiert")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .foregroundStyle(isEnabled ? FokusTheme.accent : Color.secondary)
                        .background(
                            Capsule()
                                .fill(isEnabled ? FokusTheme.accent.opacity(0.14) : FokusTheme.track)
                        )
                }

                Spacer(minLength: 4)

                Button {
                    initialTab = .websites
                    showsSelector = true
                } label: {
                    HStack(spacing: 3.5) {
                        Image(systemName: totalCount == 0 ? "plus.circle.fill" : "slider.horizontal.3")
                            .font(.system(size: 10, weight: .semibold))
                        Text(totalCount == 0 ? "Auswählen" : "Bearbeiten")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .foregroundStyle(FokusTheme.accent)
                    .background(
                        Capsule()
                            .fill(FokusTheme.accent.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showsSelector, arrowEdge: .bottom) {
                    BlockedAppSelectorPopover(store: store, selectedTab: initialTab)
                }
            }

            // Quick 1-click website pills for Instagram, YouTube, X.com, TikTok
            HStack(spacing: 5) {
                ForEach(BlockedWebsite.presets.prefix(4)) { preset in
                    let isBlocked = store.isWebsiteBlocked(preset.domain)
                    Button {
                        store.toggleBlockedWebsite(preset.domain)
                    } label: {
                        HStack(spacing: 3.5) {
                            Image(systemName: isBlocked ? "lock.fill" : preset.icon)
                                .font(.system(size: 9, weight: .semibold))
                            Text(preset.title.replacingOccurrences(of: " (Twitter)", with: ""))
                                .font(.system(size: 10.5, weight: .medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 4)
                        .foregroundStyle(isBlocked ? Color.white : Color.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isBlocked ? AnyShapeStyle(FokusTheme.accent) : AnyShapeStyle(FokusTheme.track))
                        )
                    }
                    .buttonStyle(.plain)
                    .help(isBlocked ? "\(preset.title) wird im Fokus blockiert" : "\(preset.title) im Fokus blockieren")
                }
            }

            // Automatically detected distraction apps on THIS Mac (1-click toggle with real macOS app icons)
            if !detectedQuickApps.isEmpty {
                HStack(spacing: 5) {
                    ForEach(detectedQuickApps) { app in
                        let isBlocked = store.isAppBlocked(app)
                        Button {
                            store.toggleBlockedApp(app)
                        } label: {
                            HStack(spacing: 3.5) {
                                BlockedAppIconView(app: app, size: 12)
                                Text(app.name)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 4)
                            .foregroundStyle(isBlocked ? Color.white : Color.secondary)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(isBlocked ? AnyShapeStyle(FokusTheme.accent) : AnyShapeStyle(FokusTheme.track))
                            )
                        }
                        .buttonStyle(.plain)
                        .help(isBlocked ? "\(app.name) wird im Fokus geschlossen & blockiert" : "Auf diesem Mac erkannt: \(app.name) im Fokus blockieren")
                    }
                }
            }

            if totalCount == 0 {
                Text("Tippe oben auf Instagram, YouTube, X.com oder wähle Apps (z. B. WhatsApp, Discord), die im Fokus geschlossen & gesperrt werden.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(blockedSites, id: \.self) { domain in
                            HStack(spacing: 4) {
                                Image(systemName: BlockedWebsite.icon(for: domain))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(FokusTheme.accent)
                                Text(BlockedWebsite.displayName(for: domain))
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Button {
                                    store.removeBlockedWebsite(domain)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8.5, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .opacity(isEnabled ? 1.0 : 0.55)
                            .background(Capsule().fill(FokusTheme.track))
                        }

                        ForEach(blockedApps) { app in
                            HStack(spacing: 4.5) {
                                BlockedAppIconView(app: app, size: 14)
                                Text(app.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Button {
                                    store.removeBlockedApp(app)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8.5, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("\(app.name) nicht mehr blockieren")
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .opacity(isEnabled ? 1.0 : 0.55)
                            .background(Capsule().fill(FokusTheme.track))
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(FokusTheme.track.opacity(0.55))
        )
    }
}

struct ActiveAppBlockerBar: View {
    @ObservedObject var store: FocusStore
    let active: ActiveTimer
    @State private var showsSelector = false

    private var summaryNames: String {
        let siteNames = store.blockedWebsites.map { BlockedWebsite.displayName(for: $0) }
        let appNames = store.blockedApps.map(\.name)
        return (siteNames + appNames).joined(separator: ", ")
    }

    var body: some View {
        let totalCount = store.totalBlockedItemsCount
        let isBlocking = store.isAppBlockerActive
        let isEnabled = store.preferences.isAppBlockerEnabled

        HStack(spacing: 8) {
            Button {
                if totalCount == 0 {
                    showsSelector = true
                } else {
                    store.requestToggleBlockerDuringSession()
                }
            } label: {
                Image(systemName: isBlocking ? "lock.shield.fill" : "lock.shield")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(isBlocking ? 1.0 : 0.7))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(isBlocking ? 0.24 : 0.12)))
            }
            .buttonStyle(.plain)
            .help(totalCount == 0 ? "Apps & Webseiten zum Blockieren auswählen" : (isEnabled ? "Blocker entsperren (erfordert Atem-Übung)" : "Blocker aktivieren"))

            if totalCount == 0 {
                Text("Keine Apps oder Webseiten blockiert")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(isBlocking
                         ? "\(store.blockedApps.count) Apps & \(store.blockedWebsites.count) Webseiten gesperrt"
                         : "Blocker pausiert (\(totalCount))")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(summaryNames)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 4)

            Button {
                showsSelector = true
            } label: {
                Text(totalCount == 0 ? "+ Sperren" : "Sperrliste")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showsSelector, arrowEdge: .bottom) {
                BlockedAppSelectorPopover(store: store)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.13), lineWidth: 0.8)
        )
    }
}

// MARK: - Focus Guard / Breathing Challenge (Anti-Impulse Barrier)

struct FocusGuardChallengeCard: View {
    @ObservedObject var store: FocusStore
    let intent: FocusGuardIntent

    @State private var remainingSeconds: Int = 30
    @State private var totalSeconds: Int = 30
    @State private var elapsedInCurrentSegment: Int = 0
    @State private var needsBreathConfirmation = false
    @State private var typedPhrase = ""
    @State private var pasteWarning = false
    @State private var breathPhaseIndex = 0 // 0 = Einatmen, 1 = Halten, 2 = Ausatmen
    @State private var breathScale: CGFloat = 0.72

    private var phraseMatches: Bool {
        typedPhrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ==
            FocusGuardIntent.requiredPhrase.lowercased()
    }

    private var canConfirmBreak: Bool {
        remainingSeconds <= 0 && phraseMatches
    }

    private var breathInstruction: (title: String, detail: String, color: Color) {
        if remainingSeconds <= 0 {
            return ("Atem-Übung abgeschlossen", "Tippe unten noch den Bestätigungssatz ab, falls du wirklich unterbrechen musst.", FokusTheme.accent)
        }
        if needsBreathConfirmation {
            return ("Atemzug bestätigen", "Klicke auf den Kreis, um zu bestätigen, dass du ruhig weiteratmest.", Color.orange)
        }
        switch breathPhaseIndex % 3 {
        case 0:
            return ("Tief einatmen … (4 Sek.)", "Ruhig durch die Nase einatmen und Schultern entspannen", FokusTheme.accent)
        case 1:
            return ("Atem halten … (4 Sek.)", "Kurz innehalten – spüre, wie der Ablenkungs-Impuls nachlässt", Color(red: 0.36, green: 0.62, blue: 0.98))
        default:
            return ("Langsam ausatmen … (4 Sek.)", "Gleichmäßig ausatmen und zurück in die Ruhe finden", Color(red: 0.20, green: 0.78, blue: 0.68))
        }
    }

    var body: some View {
        let info = breathInstruction
        let progress = totalSeconds > 0 ? Double(totalSeconds - remainingSeconds) / Double(totalSeconds) : 1.0
        let darkPrimary = Color(red: 0.08, green: 0.11, blue: 0.18)
        let darkSecondary = Color(red: 0.34, green: 0.40, blue: 0.50)
        let softTrack = Color(red: 0.93, green: 0.95, blue: 0.98)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wind.circle.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(FokusTheme.accent)
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(intent.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(darkPrimary)
                    Text("Fokus-Schutz · \(totalSeconds) Sek. Durchatmen-Hürde")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(darkSecondary)
                }
                Spacer()
                Menu {
                    ForEach([30, 45, 60, 90], id: \.self) { secs in
                        Button {
                            store.setFocusGuardSeconds(secs)
                            if secs > totalSeconds {
                                remainingSeconds += (secs - totalSeconds)
                                totalSeconds = secs
                            }
                        } label: {
                            HStack {
                                Text("\(secs) Sekunden")
                                if store.preferences.effectiveFocusGuardSeconds == secs {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text("\(totalSeconds)s")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(FokusTheme.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(softTrack))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            // Interactive Breathing Circle
            HStack(spacing: 12) {
                Button {
                    if needsBreathConfirmation {
                        needsBreathConfirmation = false
                        elapsedInCurrentSegment = 0
                    }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.black.opacity(0.08), lineWidth: 5.5)
                            .frame(width: 74, height: 74)

                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(info.color, style: StrokeStyle(lineWidth: 5.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 74, height: 74)
                            .animation(.easeInOut(duration: 0.4), value: progress)

                        Circle()
                            .fill(info.color.opacity(needsBreathConfirmation ? 0.28 : 0.16))
                            .frame(width: 58 * breathScale, height: 58 * breathScale)
                            .animation(.easeInOut(duration: 3.6), value: breathScale)

                        VStack(spacing: 1) {
                            if remainingSeconds > 0 {
                                Text(TimeFormat.clock(TimeInterval(remainingSeconds)))
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(darkPrimary)
                                    .monospacedDigit()
                                Text(needsBreathConfirmation ? "KLICKEN" : "ATMEN")
                                    .font(.system(size: 8, weight: .bold, design: .rounded))
                                    .foregroundStyle(needsBreathConfirmation ? Color.orange : darkSecondary)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(FokusTheme.accent)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(needsBreathConfirmation ? "Klicken, um deinen Atemzug zu bestätigen" : "Ruhig im Takt mitatmen")

                VStack(alignment: .leading, spacing: 3.5) {
                    Text(info.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(needsBreathConfirmation ? Color.orange : darkPrimary)

                    Text(info.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(darkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if needsBreathConfirmation && remainingSeconds > 0 {
                        Button {
                            needsBreathConfirmation = false
                            elapsedInCurrentSegment = 0
                        } label: {
                            Label("Atemzug bestätigen", systemImage: "hand.tap.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .foregroundStyle(.white)
                                .background(Capsule().fill(Color.orange))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(softTrack)
            )

            // Step 2: Typing verification phrase (prevents mindless waiting)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Bestätigungssatz abtippen:")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(darkSecondary)
                    Spacer()
                    if phraseMatches {
                        Label("Bestätigt", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(FokusTheme.accent)
                    }
                }

                Text("„\(FocusGuardIntent.requiredPhrase)“")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(darkPrimary)
                    .textSelection(.disabled)

                TextField("Satz hier Wort für Wort eintippen …", text: Binding(
                    get: { typedPhrase },
                    set: { newValue in
                        if abs(newValue.count - typedPhrase.count) > 6 {
                            pasteWarning = true
                        } else {
                            pasteWarning = false
                            typedPhrase = newValue
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .foregroundStyle(darkPrimary)

                if pasteWarning {
                    Text("Bitte tippe den Satz selbst ein (Copy & Paste ist deaktiviert).")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 8) {
                Button {
                    store.cancelFocusGuardChallenge()
                } label: {
                    Label("Weiter fokussieren", systemImage: "flame.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FokusFilledButtonStyle(color: FokusTheme.accent))

                Button {
                    store.completeFocusGuardChallenge()
                } label: {
                    Text(intent.confirmButtonTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FokusSoftButtonStyle(color: canConfirmBreak ? .red : .secondary))
                .disabled(!canConfirmBreak)
            }
        }
        .foregroundStyle(darkPrimary)
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(FokusTheme.accent.opacity(0.35), lineWidth: 1.2)
        )
        .onAppear {
            let secs = store.preferences.effectiveFocusGuardSeconds
            totalSeconds = secs
            remainingSeconds = secs
            elapsedInCurrentSegment = 0
            needsBreathConfirmation = false
            breathScale = 1.04
        }
        .task(id: store.pendingFocusGuardIntent) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                guard remainingSeconds > 0 else { continue }
                if !needsBreathConfirmation {
                    remainingSeconds = max(0, remainingSeconds - 1)
                    elapsedInCurrentSegment += 1
                    let elapsedTotal = totalSeconds - remainingSeconds
                    if elapsedTotal % 4 == 0 {
                        breathPhaseIndex = (breathPhaseIndex + 1) % 3
                        switch breathPhaseIndex {
                        case 0: breathScale = 1.05
                        case 1: breathScale = 1.05
                        default: breathScale = 0.68
                        }
                    }
                    if elapsedInCurrentSegment >= 10 && remainingSeconds > 3 {
                        needsBreathConfirmation = true
                    }
                }
            }
        }
    }
}
