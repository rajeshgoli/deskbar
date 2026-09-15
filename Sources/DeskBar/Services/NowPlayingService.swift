import AppKit
import Combine

/// A snapshot of the system-wide Now Playing state.
struct NowPlayingSnapshot: Equatable {
    let bundleIdentifier: String?
    let appName: String?
    let title: String
    let artist: String
    let album: String
    let isPlaying: Bool

    /// "Artist – Title", title-only fallback. Empty when there is no title.
    var displayString: String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return "" }
        guard !artist.isEmpty else { return title }
        return "\(artist) – \(title)"
    }

    /// Returns true when this snapshot should override the given window's title:
    /// playing, has a displayable title, and belongs to the same app.
    func matches(windowBundleIdentifier: String?) -> Bool {
        guard isPlaying, !displayString.isEmpty else { return false }
        guard let bundleIdentifier, let windowBundleIdentifier else { return false }
        return bundleIdentifier == windowBundleIdentifier
    }

    /// Builds a snapshot, returning nil when nothing should be displayed
    /// (paused/stopped or no title). Callers fall back to the AX/CG window title.
    static func makeSnapshot(
        title: String,
        artist: String = "",
        album: String = "",
        appName: String? = nil,
        bundleIdentifier: String? = nil,
        isPlaying: Bool
    ) -> NowPlayingSnapshot? {
        guard isPlaying else { return nil }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return NowPlayingSnapshot(
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            title: title,
            artist: artist,
            album: album,
            isPlaying: true
        )
    }
}

/// Reads system-wide Now Playing info without linking MediaRemote.
///
/// Direct MediaRemote linking is entitlement-gated since macOS 15.4, and DeskBar
/// ships with system frameworks only, so this service shells out to
/// `/usr/bin/osascript`:
/// 1. Music.app / Spotify are queried first via per-app AppleScript, which
///    reports an accurate player state (satisfies "only while playing").
/// 2. Any other source (browsers, etc.) is queried via an AppleScript bridge to
///    the private `MRNowPlayingRequest` API. A non-empty title is treated as
///    playing (best-effort: browsers may keep reporting while paused).
///
/// All scripts return "" when nothing is playing. Field separator is the ASCII
/// unit separator (character id 31) so titles containing " - " survive parsing.
final class NowPlayingService: ObservableObject {
    static let musicBundleIdentifier = "com.apple.Music"
    static let spotifyBundleIdentifier = "com.spotify.client"

    /// Field order for script output: title, artist, album, appName, bundleID.
    static func parseScriptOutput(_ output: String) -> (title: String, artist: String, album: String, appName: String, bundleID: String?)? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.components(separatedBy: "\u{1F}")
        guard parts.count >= 4, !parts[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return (
            title: parts[0],
            artist: parts.count > 1 ? parts[1] : "",
            album: parts.count > 2 ? parts[2] : "",
            appName: parts.count > 3 ? parts[3] : "",
            bundleID: parts.count > 4 && !parts[4].isEmpty ? parts[4] : nil
        )
    }

    @Published private(set) var snapshot: NowPlayingSnapshot?

    private var timer: Timer?
    private let pollInterval: TimeInterval
    private var isFetching = false

    init(pollInterval: TimeInterval = 2.0) {
        self.pollInterval = pollInterval
    }

    func start() {
        guard timer == nil else { return }
        fetchOnce()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.fetchOnce()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func fetchOnce() {
        guard !isFetching else { return }
        isFetching = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let snapshot = Self.queryNowPlaying()
            DispatchQueue.main.async {
                self?.isFetching = false
                self?.snapshot = snapshot
            }
        }
    }

    // MARK: - Query pipeline

    static func queryNowPlaying() -> NowPlayingSnapshot? {
        // Accurate per-app state first (music apps are the feature's focus).
        if let snapshot = queryMusicApp() { return snapshot }
        if let snapshot = querySpotify() { return snapshot }
        return querySystemBridge()
    }

    private static func queryMusicApp() -> NowPlayingSnapshot? {
        guard let output = runOSAScript(musicScript),
              let fields = parseScriptOutput(output)
        else { return nil }
        // Script only emits while player state is playing.
        return NowPlayingSnapshot.makeSnapshot(
            title: fields.title,
            artist: fields.artist,
            album: fields.album,
            appName: "Music",
            bundleIdentifier: musicBundleIdentifier,
            isPlaying: true
        )
    }

    private static func querySpotify() -> NowPlayingSnapshot? {
        guard let output = runOSAScript(spotifyScript),
              let fields = parseScriptOutput(output)
        else { return nil }
        return NowPlayingSnapshot.makeSnapshot(
            title: fields.title,
            artist: fields.artist,
            album: fields.album,
            appName: "Spotify",
            bundleIdentifier: spotifyBundleIdentifier,
            isPlaying: true
        )
    }

    private static func querySystemBridge() -> NowPlayingSnapshot? {
        guard let output = runOSAScript(bridgeScript),
              let fields = parseScriptOutput(output)
        else { return nil }
        // Best-effort: a reported title counts as playing for generic sources.
        return NowPlayingSnapshot.makeSnapshot(
            title: fields.title,
            artist: fields.artist,
            album: fields.album,
            appName: fields.appName.isEmpty ? nil : fields.appName,
            bundleIdentifier: fields.bundleID,
            isPlaying: true
        )
    }

    // MARK: - Scripts

    static let musicScript = """
        tell application "Music"
            if it is running then
                try
                    if player state is playing then
                        set sep to character id 31
                        set tArtist to artist of current track
                        set tName to name of current track
                        set tAlbum to album of current track
                        return tName & sep & tArtist & sep & tAlbum & sep & "Music" & sep & "com.apple.Music"
                    end if
                end try
            end if
        end tell
        return ""
        """

    static let spotifyScript = """
        tell application "Spotify"
            if it is running then
                try
                    if player state is playing then
                        set sep to character id 31
                        set tArtist to artist of current track
                        set tName to name of current track
                        set tAlbum to album of current track
                        return tName & sep & tArtist & sep & tAlbum & sep & "Spotify" & sep & "com.spotify.client"
                    end if
                end try
            end if
        end tell
        return ""
        """

    /// AppleScript bridge to the private MRNowPlayingRequest API. Works on
    /// macOS 15.4+ where direct MediaRemote linking from third-party apps is
    /// blocked, because osascript runs as an Apple-signed caller.
    static let bridgeScript = """
        use framework "AppKit"
        use scripting additions
        on run
            try
                set MediaRemote to current application's NSBundle's bundleWithPath:"/System/Library/PrivateFrameworks/MediaRemote.framework/"
                MediaRemote's load()
                set MRNowPlayingRequest to current application's NSClassFromString("MRNowPlayingRequest")
                if MRNowPlayingRequest is missing value then return ""
                set playerPath to MRNowPlayingRequest's localNowPlayingPlayerPath()
                if playerPath is missing value then return ""
                set item to MRNowPlayingRequest's localNowPlayingItem()
                if item is missing value then return ""
                set infoDict to item's nowPlayingInfo()
                if infoDict is missing value then return ""
                set tTitle to (infoDict's valueForKey:"kMRMediaRemoteNowPlayingInfoTitle")
                if tTitle is missing value then return ""
                set tArtist to (infoDict's valueForKey:"kMRMediaRemoteNowPlayingInfoArtist")
                if tArtist is missing value then set tArtist to ""
                set tAlbum to (infoDict's valueForKey:"kMRMediaRemoteNowPlayingInfoAlbum")
                if tAlbum is missing value then set tAlbum to ""
                set appName to ""
                set bundleID to ""
                try
                    set client to playerPath's client()
                    set appName to client()'s displayName() as text
                    set bundleID to client()'s bundleIdentifier() as text
                end try
                set sep to character id 31
                return (tTitle as text) & sep & (tArtist as text) & sep & (tAlbum as text) & sep & appName & sep & bundleID
            on error
                return ""
            end try
        end run
        """

    // MARK: - Process runner

    static func runOSAScript(_ script: String, timeout: TimeInterval = 1.5) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            group.leave()
        }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return output.isEmpty ? nil : output
    }
}
