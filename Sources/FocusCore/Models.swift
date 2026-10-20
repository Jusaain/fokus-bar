import Foundation

public enum Priority: String, Codable, CaseIterable, Identifiable, Sendable {
    case low, normal, high
    public var id: String { rawValue }
    public var title: String { switch self { case .low: "Niedrig"; case .normal: "Normal"; case .high: "Hoch" } }
    public var rank: Int { switch self { case .low: 0; case .normal: 1; case .high: 2 } }
}
public enum RepeatRule: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, daily, weekdays, weekly, monthly
    public var id: String { rawValue }
    public var title: String { switch self { case .none: "Nie"; case .daily: "Täglich"; case .weekdays: "Werktags"; case .weekly: "Wöchentlich"; case .monthly: "Monatlich" } }
}
public struct FocusTask: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var project: String
    public var priority: Priority
    public var createdAt: Date
    public var dueDate: Date?
    public var reminder: Date?
    public var recurrence: RepeatRule
    public var completedAt: Date?
    public var archived: Bool
    public var predecessorID: UUID?
    public var isCompleted: Bool { completedAt != nil }
    public init(id: UUID = UUID(), title: String = "", notes: String = "", project: String = "", priority: Priority = .normal, createdAt: Date = Date(), dueDate: Date? = nil, reminder: Date? = nil, recurrence: RepeatRule = .none, completedAt: Date? = nil, archived: Bool = false) {
        self.id = id; self.title = title; self.notes = notes; self.project = project; self.priority = priority; self.createdAt = createdAt; self.dueDate = dueDate; self.reminder = reminder; self.recurrence = recurrence; self.completedAt = completedAt; self.archived = archived
    }
}
public enum TimerMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case stopwatch, countdown, focus, rest
    public var id: String { rawValue }
    public var title: String { switch self { case .stopwatch: "Stoppuhr"; case .countdown: "Countdown"; case .focus: "Fokus"; case .rest: "Pause" } }
    public var isWork: Bool { self != .rest }
}
public struct TimeEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var taskID: UUID?
    public var taskTitle: String
    public var project: String
    public var start: Date
    public var end: Date
    public var mode: TimerMode
    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    public init(id: UUID = UUID(), taskID: UUID? = nil, taskTitle: String = "Freie Sitzung", project: String = "", start: Date, end: Date, mode: TimerMode = .stopwatch) {
        self.id = id; self.taskID = taskID; self.taskTitle = taskTitle; self.project = project; self.start = start; self.end = end; self.mode = mode
    }
}
public struct ActiveTimer: Codable, Equatable, Sendable {
    public var taskID: UUID?
    public var title: String
    public var project: String
    public var mode: TimerMode
    public var target: TimeInterval
    public var accumulated: TimeInterval
    public var segmentStart: Date?
    public var suspendedDeadline: Date?
    public var isRunning: Bool { segmentStart != nil }
    public var deadline: Date? { guard mode != .stopwatch, let start = segmentStart else { return nil }; return start.addingTimeInterval(max(0, target - accumulated)) }
    public func elapsed(at now: Date) -> TimeInterval {
        let value = accumulated + max(0, segmentStart.map { now.timeIntervalSince($0) } ?? 0)
        return mode == .stopwatch ? value : min(target, value)
    }
    public func remaining(at now: Date) -> TimeInterval { max(0, target - elapsed(at: now)) }
    public init(taskID: UUID? = nil, title: String = "Freie Sitzung", project: String = "", mode: TimerMode, target: TimeInterval = 1500, accumulated: TimeInterval = 0, segmentStart: Date? = nil) {
        self.taskID = taskID; self.title = title; self.project = project; self.mode = mode; self.target = target; self.accumulated = accumulated; self.segmentStart = segmentStart
    }
}
public enum FocusSoundCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case nature
    case spotifyDeepWork
    case spotifyJazz

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .nature: "Natur & Entspannte Klänge (Direkt in FokusBar)"
        case .spotifyDeepWork: "Spotify · Courten & Deep Work"
        case .spotifyJazz: "Spotify · Jazz House & Jazz Lounge"
        }
    }

    public var items: [FocusSound] {
        FocusSound.playableCases.filter { $0.category == self }
    }
}

public enum FocusSound: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    // Real Nature & Ambient Field Recordings (bundled .m4a)
    case gentleRain
    case forestNature
    case forestStream
    case windowRain
    case oceanWaves
    case fireplace
    case cozyCafe
    // Spotify · Courten & Deep Work
    case courtenRadio
    case thisIsCourten
    case courtenPenthouseRadio
    case deepFocus
    case focusFlow
    case houseFocus
    case beatsToThinkTo
    // Spotify · Jazz House & Jazz Lounge
    case jazzHouseLounge
    case smoothJazzBeats
    case jazzVibes
    case coffeeTableJazz
    case jazzInBackground
    case lofiCafe

    public var id: String { rawValue }

    public var category: FocusSoundCategory? {
        switch self {
        case .off:
            nil
        case .gentleRain, .forestNature, .forestStream, .windowRain, .oceanWaves, .fireplace, .cozyCafe:
            .nature
        case .courtenRadio, .thisIsCourten, .courtenPenthouseRadio, .deepFocus, .focusFlow, .houseFocus, .beatsToThinkTo:
            .spotifyDeepWork
        case .jazzHouseLounge, .smoothJazzBeats, .jazzVibes, .coffeeTableJazz, .jazzInBackground, .lofiCafe:
            .spotifyJazz
        }
    }

    public var isSpotify: Bool { spotifyURI != nil }
    public var isNatureSound: Bool { audioResourceName != nil }

    /// Bundled `.m4a` filename (without extension) inside `Resources/Sounds/`.
    public var audioResourceName: String? {
        switch self {
        case .gentleRain: "rain-gentle"
        case .forestNature: "forest-nature"
        case .forestStream: "forest-stream"
        case .windowRain: "rain-window"
        case .oceanWaves: "ocean-waves"
        case .fireplace: "fireplace-cozy"
        case .cozyCafe: "cafe-lounge"
        default: nil
        }
    }

    public var spotifyURI: String? {
        switch self {
        case .courtenRadio: "spotify:playlist:37i9dQZF1E4viP52QtYaG5"
        case .thisIsCourten: "spotify:playlist:37i9dQZF1DZ06evO29wWby"
        case .courtenPenthouseRadio: "spotify:playlist:37i9dQZF1E8MYiee1jfrBS"
        case .deepFocus: "spotify:playlist:37i9dQZF1DWZeKCadgRdKQ"
        case .focusFlow: "spotify:playlist:37i9dQZF1DWZZbwlv3Vmtr"
        case .houseFocus: "spotify:playlist:37i9dQZF1DX8wtrGDH81Oa"
        case .beatsToThinkTo: "spotify:playlist:37i9dQZF1DXa2SPUyWl8Y5"
        case .jazzHouseLounge: "spotify:playlist:37i9dQZF1DX82pCGH5USnM"
        case .smoothJazzBeats: "spotify:playlist:37i9dQZF1DX06817kK7cRP"
        case .jazzVibes: "spotify:playlist:37i9dQZF1DX0SM0LYsmbMT"
        case .coffeeTableJazz: "spotify:playlist:37i9dQZF1DWVqfgj8NZEp1"
        case .jazzInBackground: "spotify:playlist:37i9dQZF1DWV7EzJMK2FUI"
        case .lofiCafe: "spotify:playlist:37i9dQZF1DX9RwfGbeGQwP"
        default: nil
        }
    }

    public var spotifyPlaylistID: String? {
        guard let uri = spotifyURI else { return nil }
        let prefix = "spotify:playlist:"
        guard uri.hasPrefix(prefix) else { return nil }
        return String(uri.dropFirst(prefix.count))
    }

    /// Public HTTPS Spotify playlist link so any user can open/play or save the playlist even if `Spotify.app` is not yet installed.
    public var spotifyWebURL: URL? {
        guard let id = spotifyPlaylistID else { return nil }
        return URL(string: "https://open.spotify.com/playlist/\(id)")
    }

    public var title: String {
        switch self {
        case .off: "Aus"
        case .gentleRain: "Sanfter Sommerregen (Natur)"
        case .forestNature: "Waldruhe & Vögel (Natur)"
        case .forestStream: "Waldbach & Blätterwind (Natur)"
        case .windowRain: "Regen am Fenster (Natur)"
        case .oceanWaves: "Meereswellen · Küste (Natur)"
        case .fireplace: "Kaminfeuer & Regen (Ambient)"
        case .cozyCafe: "Entspanntes Café (Ambient)"
        case .courtenRadio: "Courten Radio (Spotify)"
        case .thisIsCourten: "This Is Courten (Spotify)"
        case .courtenPenthouseRadio: "Courten · Penthouse Radio (Spotify)"
        case .deepFocus: "Deep Focus · Deep Work (Spotify)"
        case .focusFlow: "Focus Flow · Lock-In (Spotify)"
        case .houseFocus: "House Focus · Deep Work (Spotify)"
        case .beatsToThinkTo: "Beats to Think To (Spotify)"
        case .jazzHouseLounge: "Jazz House & Soft Lounge (Spotify)"
        case .smoothJazzBeats: "Smooth Jazz Beats (Spotify)"
        case .jazzVibes: "Jazz Vibes · Chill Beats (Spotify)"
        case .coffeeTableJazz: "Coffee Table Jazz (Spotify)"
        case .jazzInBackground: "Jazz in the Background (Spotify)"
        case .lofiCafe: "Lo-Fi Jazz Café (Spotify)"
        }
    }

    public var shortTitle: String {
        switch self {
        case .off: "Ton aus"
        case .gentleRain: "Sanfter Regen"
        case .forestNature: "Wald & Vögel"
        case .forestStream: "Waldbach"
        case .windowRain: "Fensterregen"
        case .oceanWaves: "Meereswellen"
        case .fireplace: "Kaminfeuer"
        case .cozyCafe: "Café-Atmosphäre"
        case .courtenRadio: "Courten Radio"
        case .thisIsCourten: "This Is Courten"
        case .courtenPenthouseRadio: "Penthouse Radio"
        case .deepFocus: "Deep Focus"
        case .focusFlow: "Focus Flow"
        case .houseFocus: "House Focus"
        case .beatsToThinkTo: "Beats to Think"
        case .jazzHouseLounge: "Jazz House"
        case .smoothJazzBeats: "Smooth Jazz"
        case .jazzVibes: "Jazz Vibes"
        case .coffeeTableJazz: "Coffee Jazz"
        case .jazzInBackground: "Background Jazz"
        case .lofiCafe: "Lo-Fi Jazz Café"
        }
    }

    public var subtitle: String {
        switch self {
        case .off: "Keine Hintergrundklänge während der Sitzung"
        case .gentleRain: "Echte Naturaufnahme · Warmer, gleichmäßiger Sommerregen auf Blättern"
        case .forestNature: "Echte Naturaufnahme · Entspannter Wald mit Blätterwind & sanftem Vogelgesang"
        case .forestStream: "Echte Naturaufnahme · Plätschernder Waldbach und sanfte Brise in den Bäumen"
        case .windowRain: "Echte Naturaufnahme · Gemütlicher Regen an der Fensterscheibe mit fernem Grollen"
        case .oceanWaves: "Echte Naturaufnahme · Ruhige, gleichmäßige Meeresbrandung am Strand"
        case .fireplace: "Echte Aufnahme · Warmes, knisterndes Kaminfeuer mit sanftem Regen"
        case .cozyCafe: "Echte Aufnahme · Entspannte, warme Café-Atmosphäre für produktiven Flow"
        case .courtenRadio: "Spotify · Courten Radio mit LAGXNA, Spaceouters & purity. für tiefen Fokus"
        case .thisIsCourten: "Spotify · Alle wichtigen Ambient- & Electronic-Tracks von Courten"
        case .courtenPenthouseRadio: "Spotify · Atmosphärisches Penthouse Radio mit Courten & LAGXNA"
        case .deepFocus: "Spotify · Bleib ruhig und fokussiert mit Ambient und Post-Rock für Deep Work"
        case .focusFlow: "Spotify · Instrumentale Deep-Work-Beats zum kompletten Abschottungs-Flow"
        case .houseFocus: "Spotify · Instrumentaler Deep & Melodic House für konzentriertes Arbeiten"
        case .beatsToThinkTo: "Spotify · Fokus mit Melodic House, Deep Electronica und ruhigem Puls"
        case .jazzHouseLounge: "Spotify · Entspannter Jazz-House & Soft-House-Grooves für angenehmen Flow"
        case .smoothJazzBeats: "Spotify · Warme, entspannte Jazz-Beats als ruhiger Hintergrund-Soundtrack"
        case .jazzVibes: "Spotify · Chillige instrumentale Jazz-Hop- & Lounge-Beats zum Arbeiten"
        case .coffeeTableJazz: "Spotify · Sanfter Instrumental-Jazz wie in einer ruhigen Café-Lounge"
        case .jazzInBackground: "Spotify · Ruhige Jazz-Instrumentals für Arbeit, Konzeptphasen & Lesen"
        case .lofiCafe: "Spotify · Entspannte Lo-Fi- & Jazz-Beats für lässige Coffeehouse-Vibes"
        }
    }

    public var badge: String {
        switch self {
        case .off: "AUS"
        case .gentleRain: "NATUR · REGEN"
        case .forestNature: "NATUR · WALD"
        case .forestStream: "NATUR · BACH"
        case .windowRain: "NATUR · FENSTER"
        case .oceanWaves: "NATUR · MEER"
        case .fireplace: "AMBIENT · KAMIN"
        case .cozyCafe: "AMBIENT · CAFÉ"
        case .courtenRadio: "SPOTIFY · COURTEN"
        case .thisIsCourten: "SPOTIFY · COURTEN"
        case .courtenPenthouseRadio: "SPOTIFY · COURTEN"
        case .deepFocus: "SPOTIFY · DEEP WORK"
        case .focusFlow: "SPOTIFY · DEEP WORK"
        case .houseFocus: "SPOTIFY · HOUSE"
        case .beatsToThinkTo: "SPOTIFY · DEEP WORK"
        case .jazzHouseLounge: "SPOTIFY · JAZZ HOUSE"
        case .smoothJazzBeats: "SPOTIFY · JAZZ BEATS"
        case .jazzVibes: "SPOTIFY · JAZZ VIBES"
        case .coffeeTableJazz: "SPOTIFY · JAZZ"
        case .jazzInBackground: "SPOTIFY · JAZZ"
        case .lofiCafe: "SPOTIFY · LO-FI JAZZ"
        }
    }

    public var icon: String {
        switch self {
        case .off: "speaker.slash"
        case .gentleRain: "cloud.rain.fill"
        case .forestNature: "tree.fill"
        case .forestStream: "water.waves"
        case .windowRain: "cloud.heavyrain.fill"
        case .oceanWaves: "wind"
        case .fireplace: "flame.fill"
        case .cozyCafe: "cup.and.saucer.fill"
        case .courtenRadio: "dot.radiowaves.left.and.right"
        case .thisIsCourten: "music.note.list"
        case .courtenPenthouseRadio: "building.2.crop.circle"
        case .deepFocus: "brain.head.profile"
        case .focusFlow: "bolt.horizontal.circle"
        case .houseFocus: "waveform"
        case .beatsToThinkTo: "sparkles"
        case .jazzHouseLounge: "music.quarternote.3"
        case .smoothJazzBeats: "pianokeys"
        case .jazzVibes: "guitars.fill"
        case .coffeeTableJazz: "music.mic"
        case .jazzInBackground: "music.note"
        case .lofiCafe: "headphones"
        }
    }

    public static var playableCases: [FocusSound] {
        allCases.filter { $0 != .off }
    }

    /// Quick-access favorites shown as one-tap pills in the timer start form.
    public static var quickFavorites: [FocusSound] {
        [.gentleRain, .forestNature, .forestStream, .courtenRadio, .deepFocus, .jazzHouseLounge]
    }

    /// Resolves current and legacy raw values so older `state.json` files migrate cleanly.
    public static func resolved(from raw: String?) -> FocusSound? {
        guard let raw else { return nil }
        if let exact = FocusSound(rawValue: raw) { return exact }
        switch raw {
        case "binauralRain", "gamma40", "solfeggio852", "betaFocus", "alphaFlow":
            return .gentleRain
        case "brownNoise":
            return .forestNature
        case "courtenSlowedRadio", "courtenMix":
            return .courtenRadio
        default:
            return nil
        }
    }
}
public struct BlockedApp: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var bundleIdentifier: String
    public var name: String
    public var path: String?

    public var id: String { bundleIdentifier.lowercased() }

    public init(bundleIdentifier: String, name: String, path: String? = nil) {
        self.bundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.path = path
    }

    public static let protectedBundleIdentifiers: Set<String> = [
        "de.justin.fokusbar",
        "com.apple.finder",
        "com.apple.systempreferences",
        "com.apple.systemsettings",
        "com.apple.activitymonitor",
        "com.apple.terminal",
        "com.apple.loginwindow",
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui"
    ]

    public static func isProtected(_ bundleIdentifier: String) -> Bool {
        protectedBundleIdentifiers.contains(bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

public struct BlockedWebsitePreset: Equatable, Hashable, Identifiable, Sendable {
    public let domain: String
    public let title: String
    public let icon: String
    public let aliases: [String]

    public var id: String { domain }

    public init(domain: String, title: String, icon: String, aliases: [String] = []) {
        self.domain = domain
        self.title = title
        self.icon = icon
        self.aliases = aliases
    }
}

public enum BlockedWebsite {
    public static let presets: [BlockedWebsitePreset] = [
        BlockedWebsitePreset(
            domain: "instagram.com",
            title: "Instagram",
            icon: "camera.fill",
            aliases: ["instagr.am", "ig.me", "imginn.com", "picuki.com", "dumpor.com", "iganony.io"]
        ),
        BlockedWebsitePreset(
            domain: "youtube.com",
            title: "YouTube",
            icon: "play.rectangle.fill",
            aliases: ["youtu.be", "youtube-nocookie.com", "yewtu.be", "piped.video", "piped.kavin.rocks", "inv.nadeko.net"]
        ),
        BlockedWebsitePreset(
            domain: "x.com",
            title: "X.com (Twitter)",
            icon: "bubble.left.and.exclamationmark.bubble.right.fill",
            aliases: ["twitter.com", "t.co", "nitter.net", "nitter.poast.org", "xcancel.com"]
        ),
        BlockedWebsitePreset(
            domain: "tiktok.com",
            title: "TikTok",
            icon: "music.note.tv.fill",
            aliases: ["vm.tiktok.com", "vt.tiktok.com", "urlebird.com", "proxitok.pabloferreiro.es", "tikwm.com"]
        ),
        BlockedWebsitePreset(
            domain: "reddit.com",
            title: "Reddit",
            icon: "text.bubble.fill",
            aliases: ["old.reddit.com", "redd.it", "redlib.catsarch.com", "libredd.it", "teddit.net"]
        ),
        BlockedWebsitePreset(domain: "netflix.com", title: "Netflix", icon: "film.fill"),
        BlockedWebsitePreset(domain: "facebook.com", title: "Facebook", icon: "person.2.fill", aliases: ["fb.com", "messenger.com"]),
        BlockedWebsitePreset(domain: "twitch.tv", title: "Twitch", icon: "gamecontroller.fill"),
        BlockedWebsitePreset(domain: "linkedin.com", title: "LinkedIn", icon: "briefcase.fill", aliases: ["lnkd.in"])
    ]

    /// Known browser web-proxy / unblocker services automatically blocked whenever website blocking is active,
    /// preventing users from loading blocked sites inside an in-browser proxy tab.
    public static let webProxyDomains: [String] = [
        "croxyproxy.com",
        "croxyproxy.rocks",
        "proxysite.com",
        "blockaway.net",
        "filterbypass.me",
        "kproxy.com",
        "4everproxy.com",
        "hidester.com",
        "plainproxies.com",
        "megaproxy.com",
        "proxium.com",
        "lumiproxy.com"
    ]

    public static func preset(for domain: String) -> BlockedWebsitePreset? {
        guard let norm = normalizeDomain(domain) else { return nil }
        return presets.first { $0.domain == norm || $0.aliases.contains(norm) }
    }

    public static func displayName(for domain: String) -> String {
        if webProxyDomains.contains(domain.lowercased()) {
            return "Web-Proxy (\(domain))"
        }
        if let p = preset(for: domain) { return p.title }
        return normalizeDomain(domain) ?? domain
    }

    public static func icon(for domain: String) -> String {
        preset(for: domain)?.icon ?? "globe"
    }

    /// Normalizes a user-entered URL or domain (e.g. "https://www.instagram.com/reels" -> "instagram.com", "twitter.com" -> "x.com").
    public static func normalizeDomain(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return nil }
        if let schemeRange = s.range(of: "://") {
            s = String(s[schemeRange.upperBound...])
        }
        if let slashIndex = s.firstIndex(of: "/") {
            s = String(s[..<slashIndex])
        }
        if let queryIndex = s.firstIndex(of: "?") {
            s = String(s[..<queryIndex])
        }
        if let hashIndex = s.firstIndex(of: "#") {
            s = String(s[..<hashIndex])
        }
        if let colonIndex = s.firstIndex(of: ":") {
            s = String(s[..<colonIndex])
        }
        while s.hasPrefix(".") { s.removeFirst() }
        while s.hasSuffix(".") { s.removeLast() }
        if s.hasPrefix("www.") {
            s = String(s.dropFirst(4))
        }
        if s.hasPrefix("m.") && s.count > 5 {
            let withoutM = String(s.dropFirst(2))
            if withoutM.contains(".") { s = withoutM }
        }
        guard s.count >= 3, s.count <= 120, s.contains(".") else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard s.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              !s.contains(".."),
              !s.hasPrefix("-"),
              !s.hasSuffix("-") else {
            return nil
        }
        for p in presets where p.aliases.contains(s) {
            return p.domain
        }
        return s
    }

    /// Expands canonical domains with their known aliases (e.g. `x.com` -> `x.com` + `twitter.com` + `nitter.net`, `youtube.com` -> `youtube.com` + `youtu.be` + `yewtu.be`) AND includes known web-proxy unblocker domains so web proxies cannot bypass the block.
    public static func expandedDomains(for domains: [String]) -> [String] {
        var result = Set<String>()
        for d in domains {
            guard let norm = normalizeDomain(d) else { continue }
            result.insert(norm)
            if let p = presets.first(where: { $0.domain == norm }) {
                for alias in p.aliases {
                    result.insert(alias)
                }
            }
        }
        if !result.isEmpty {
            for proxy in webProxyDomains {
                result.insert(proxy)
            }
        }
        return result.sorted()
    }

    /// Returns the matched canonical domain if `urlOrHost` belongs to any of the `blockedDomains`, a web-proxy service, or embeds a blocked domain in its URL query/path (e.g. Google Translate proxy or Web Archive).
    public static func matchedDomain(for urlOrHost: String, in blockedDomains: [String]) -> String? {
        guard let host = normalizeHostOnly(urlOrHost) else { return nil }
        let lowerFull = urlOrHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let decodedFull = lowerFull.removingPercentEncoding ?? lowerFull

        for raw in blockedDomains {
            guard let canonical = normalizeDomain(raw) else { continue }
            let candidates = [canonical] + (presets.first(where: { $0.domain == canonical })?.aliases ?? [])
            for candidate in candidates {
                if host == candidate || host.hasSuffix("." + candidate) {
                    return canonical
                }
                // Also detect blocked domain passed inside a proxy/translator URL parameter or path
                if decodedFull.contains("://\(candidate)") ||
                    decodedFull.contains(".\(candidate)/") ||
                    decodedFull.contains("=\(candidate)") {
                    return canonical
                }
            }
        }
        if !blockedDomains.isEmpty {
            for proxy in webProxyDomains {
                if host == proxy || host.hasSuffix("." + proxy) {
                    return proxy
                }
            }
        }
        return nil
    }

    private static func normalizeHostOnly(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return nil }
        if let schemeRange = s.range(of: "://") {
            s = String(s[schemeRange.upperBound...])
        }
        if let slashIndex = s.firstIndex(of: "/") {
            s = String(s[..<slashIndex])
        }
        if let queryIndex = s.firstIndex(of: "?") {
            s = String(s[..<queryIndex])
        }
        if let hashIndex = s.firstIndex(of: "#") {
            s = String(s[..<hashIndex])
        }
        if let colonIndex = s.firstIndex(of: ":") {
            s = String(s[..<colonIndex])
        }
        while s.hasPrefix(".") { s.removeFirst() }
        while s.hasSuffix(".") { s.removeLast() }
        if s.hasPrefix("www.") {
            s = String(s.dropFirst(4))
        }
        return s.isEmpty ? nil : s
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var sound = "Glass"
    public var soundEnabled = true
    public var notificationsEnabled = true
    public var showMenuTime = true
    public var focusMinutes = 25
    public var breakMinutes = 5
    public var longBreakMinutes = 15
    public var appearance = "system"
    /// Daily work goal in minutes. Optional so older state files still load: `nil` means four hours, `0` turns the goal off.
    public var dailyGoalMinutes: Int?
    public static let defaultDailyGoalMinutes = 240
    public var dailyGoal: TimeInterval { TimeInterval(dailyGoalMinutes ?? Self.defaultDailyGoalMinutes) * 60 }
    /// System-wide quick entry shortcut. Optional for older state files: `nil` means on.
    public var quickEntryHotKey: Bool?
    public var quickEntryEnabled: Bool { quickEntryHotKey ?? true }
    /// Floating LED timer clock in the top-right screen corner. Optional for older state files: `nil` means on.
    public var floatingTimer: Bool?
    public var showFloatingTimer: Bool { floatingTimer ?? true }
    /// Selected background focus sound during focus sessions. Optional for older state files: `nil` defaults to `.gentleRain`.
    public var focusSound: String?
    /// Last non-off focus sound so muting/unmuting restores the user's preferred sound.
    public var lastFocusSound: String?
    /// Volume for the background focus sound (0.0 ... 1.0). Optional for older state files: `nil` defaults to 0.45.
    public var focusSoundVolume: Double?
    /// Whether the focus sound also plays in Countdown and Stopwatch modes, not only Focus mode. Optional: `nil` means true.
    public var focusSoundAllWorkModes: Bool?
    /// Whether the App & Website Blocker is enabled during Focus sessions. Optional for older state files: `nil` means true.
    public var appBlockerEnabled: Bool?
    /// User-selected macOS apps to close and block while Focus is active.
    public var blockedApps: [BlockedApp]?
    /// User-selected website domains (e.g. "instagram.com", "youtube.com", "x.com") to close and block in browsers while Focus is active.
    public var blockedWebsites: [String]?
    /// Whether blocked apps & websites should also be blocked in Countdown and Stopwatch modes. Optional: `nil` means false (Focus only).
    public var blockAppsInAllWorkModes: Bool?
    /// Whether pausing or stopping a running Focus session requires completing the breathing & reflection challenge first. Optional: `nil` means true.
    public var focusGuardEnabled: Bool?
    /// Duration in seconds for the breathing challenge before pausing/stopping a Focus session is allowed. Optional: `nil` defaults to 30.
    public var focusGuardSeconds: Int?
    public static let defaultFocusSound: FocusSound = .gentleRain
    public static let defaultFocusSoundVolume: Double = 0.45
    public static let defaultFocusGuardSeconds: Int = 30
    public var selectedFocusSound: FocusSound { FocusSound.resolved(from: focusSound) ?? Self.defaultFocusSound }
    public var preferredPlayableFocusSound: FocusSound {
        if selectedFocusSound != .off { return selectedFocusSound }
        if let last = FocusSound.resolved(from: lastFocusSound), last != .off { return last }
        return Self.defaultFocusSound
    }
    public var effectiveFocusSoundVolume: Double { min(1.0, max(0.05, focusSoundVolume ?? Self.defaultFocusSoundVolume)) }
    public var playsFocusSoundInAllWorkModes: Bool { focusSoundAllWorkModes ?? true }
    public func shouldPlayFocusSound(for mode: TimerMode) -> Bool {
        guard selectedFocusSound != .off, mode.isWork else { return false }
        return mode == .focus || playsFocusSoundInAllWorkModes
    }
    public var isAppBlockerEnabled: Bool { appBlockerEnabled ?? true }
    public var effectiveBlockedApps: [BlockedApp] {
        (blockedApps ?? []).filter { !BlockedApp.isProtected($0.bundleIdentifier) }
    }
    public var effectiveBlockedWebsites: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in blockedWebsites ?? [] {
            guard let norm = BlockedWebsite.normalizeDomain(raw), !seen.contains(norm) else { continue }
            seen.insert(norm)
            result.append(norm)
        }
        return result.sorted()
    }
    public var totalBlockedItemsCount: Int {
        effectiveBlockedApps.count + effectiveBlockedWebsites.count
    }
    public var blocksAppsInAllWorkModes: Bool { blockAppsInAllWorkModes ?? false }
    public func shouldBlockApps(for mode: TimerMode) -> Bool {
        guard isAppBlockerEnabled, totalBlockedItemsCount > 0, mode.isWork else { return false }
        return mode == .focus || blocksAppsInAllWorkModes
    }
    public var isFocusGuardEnabled: Bool { focusGuardEnabled ?? true }
    public var effectiveFocusGuardSeconds: Int { min(180, max(15, focusGuardSeconds ?? Self.defaultFocusGuardSeconds)) }
    public func shouldRequireFocusGuard(for mode: TimerMode) -> Bool {
        guard isFocusGuardEnabled, mode.isWork else { return false }
        return mode == .focus || blocksAppsInAllWorkModes
    }
    public init() {}
}
public struct AppState: Codable, Equatable, Sendable {
    public var version = 1
    public var tasks: [FocusTask] = []
    public var entries: [TimeEntry] = []
    public var active: ActiveTimer?
    public var preferences = Preferences()
    public var completedFocusSessions = 0
    public var lastWorkTaskID: UUID?
    public var dismissedReminderKeys: [String]?
    public var lastCheckpoint: Date?
    public init() {}
    public func validated() throws -> AppState {
        guard version == 1 else { throw DataError.invalid("Diese Sicherung stammt aus einer nicht unterstützten Version.") }
        guard Set(tasks.map(\.id)).count == tasks.count, Set(entries.map(\.id)).count == entries.count else { throw DataError.invalid("Die Datei enthält doppelte Einträge.") }
        guard tasks.count <= 100_000, entries.count <= 1_000_000 else { throw DataError.invalid("Diese Datei ist zu groß.") }
        guard tasks.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.title.count <= 500 && $0.notes.count <= 50_000 && $0.project.count <= 100 }) else { throw DataError.invalid("Ungültige Aufgabendaten.") }
        guard entries.allSatisfy({ $0.start.timeIntervalSince1970.isFinite && $0.end.timeIntervalSince1970.isFinite && $0.end >= $0.start && $0.duration <= 604800 }) else { throw DataError.invalid("Ungültige Zeitintervalle.") }
        if let active { guard active.target.isFinite, active.accumulated.isFinite, active.accumulated >= 0, active.accumulated <= 604800, active.target > 0, active.target <= 86400, active.mode == .stopwatch || active.accumulated <= active.target else { throw DataError.invalid("Ungültiger Timer.") } }
        let validFocusSound = preferences.focusSound.map { FocusSound.resolved(from: $0) != nil } ?? true
        let validLastFocusSound = preferences.lastFocusSound.map { FocusSound.resolved(from: $0) != nil } ?? true
        let validFocusVolume = preferences.focusSoundVolume.map { $0.isFinite && (0.0...1.0).contains($0) } ?? true
        let validBlockedApps = (preferences.blockedApps ?? []).count <= 200 && (preferences.blockedApps ?? []).allSatisfy {
            !$0.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            $0.bundleIdentifier.count <= 200 &&
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            $0.name.count <= 200 &&
            !BlockedApp.isProtected($0.bundleIdentifier)
        }
        let validBlockedWebsites = (preferences.blockedWebsites ?? []).count <= 200 && (preferences.blockedWebsites ?? []).allSatisfy {
            $0.count <= 120 && BlockedWebsite.normalizeDomain($0) != nil
        }
        let validFocusGuardSeconds = preferences.focusGuardSeconds.map { (15...180).contains($0) } ?? true
        guard (1...240).contains(preferences.focusMinutes), (1...120).contains(preferences.breakMinutes), (1...120).contains(preferences.longBreakMinutes), ["system", "light", "dark"].contains(preferences.appearance), (0...960).contains(preferences.dailyGoalMinutes ?? 0), ["Glass", "Ping", "Pop", "Hero", "Submarine"].contains(preferences.sound), validFocusSound, validLastFocusSound, validFocusVolume, validBlockedApps, validBlockedWebsites, validFocusGuardSeconds else { throw DataError.invalid("Ungültige Einstellungen.") }
        return self
    }
}
public enum DataError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let message): message } }
}
public enum TimeFormat {
    public static func clock(_ value: TimeInterval) -> String {
        let seconds = Int(min(31_536_000, max(0, value.isFinite ? value : 0)).rounded(.down))
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    public static func short(_ value: TimeInterval) -> String {
        let minutes = Int(min(31_536_000, max(0, value.isFinite ? value : 0))) / 60
        if minutes < 1 { return value > 0 ? "< 1 Min." : "0 Min." }
        return minutes >= 60 ? "\(minutes / 60) Std. \(minutes % 60) Min." : "\(minutes) Min."
    }
}
