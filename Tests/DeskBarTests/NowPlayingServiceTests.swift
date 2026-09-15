import Testing
@testable import DeskBar

struct NowPlayingServiceTests {
    @Test
    func displayStringFormatsArtistDashTitle() {
        let snap = NowPlayingSnapshot(
            bundleIdentifier: "com.apple.Music",
            appName: "Music",
            title: "Midnight City",
            artist: "M83",
            album: "Hurry Up",
            isPlaying: true
        )
        #expect(snap.displayString == "M83 – Midnight City")
    }

    @Test
    func displayStringFallsBackToTitleWithoutArtist() {
        let snap = NowPlayingSnapshot(
            bundleIdentifier: "com.spotify.client",
            appName: "Spotify",
            title: "Intro",
            artist: "",
            album: "",
            isPlaying: true
        )
        #expect(snap.displayString == "Intro")
    }

    @Test
    func displayStringEmptyWithoutTitle() {
        let snap = NowPlayingSnapshot(
            bundleIdentifier: nil,
            appName: nil,
            title: "   ",
            artist: "M83",
            album: "",
            isPlaying: true
        )
        #expect(snap.displayString == "")
    }

    @Test
    func makeSnapshotReturnsNilWhenPausedOrUntitled() {
        #expect(NowPlayingSnapshot.makeSnapshot(title: "Song", artist: "A", isPlaying: false) == nil)
        #expect(NowPlayingSnapshot.makeSnapshot(title: "  ", artist: "A", isPlaying: true) == nil)
        let snap = NowPlayingSnapshot.makeSnapshot(
            title: "Song",
            artist: "A",
            bundleIdentifier: "com.apple.Music",
            isPlaying: true
        )
        #expect(snap != nil)
        #expect(snap?.displayString == "A – Song")
    }

    @Test
    func matchesRequiresPlayingAndSameBundle() {
        let snap = NowPlayingSnapshot(
            bundleIdentifier: "com.apple.Music",
            appName: "Music",
            title: "Song",
            artist: "A",
            album: "",
            isPlaying: true
        )
        #expect(snap.matches(windowBundleIdentifier: "com.apple.Music"))
        #expect(!snap.matches(windowBundleIdentifier: "com.spotify.client"))
        #expect(!snap.matches(windowBundleIdentifier: nil))

        let paused = NowPlayingSnapshot(
            bundleIdentifier: "com.apple.Music",
            appName: "Music",
            title: "Song",
            artist: "A",
            album: "",
            isPlaying: false
        )
        #expect(!paused.matches(windowBundleIdentifier: "com.apple.Music"))
    }

    @Test
    func parsesUnitSeparatorOutput() {
        let output = ["Midnight City", "M83", "Hurry Up", "Music", "com.apple.Music"].joined(separator: "\u{1F}")
        let fields = NowPlayingService.parseScriptOutput(output)
        #expect(fields?.title == "Midnight City")
        #expect(fields?.artist == "M83")
        #expect(fields?.album == "Hurry Up")
        #expect(fields?.appName == "Music")
        #expect(fields?.bundleID == "com.apple.Music")
    }

    @Test
    func parseKeepsDashesInsideTitles() {
        let output = ["AC-DC - Thunder", "AC-DC", "", "Music", ""].joined(separator: "\u{1F}")
        let fields = NowPlayingService.parseScriptOutput(output)
        #expect(fields?.title == "AC-DC - Thunder")
        #expect(fields?.bundleID == nil)
    }

    @Test
    func parseRejectsEmptyOutput() {
        #expect(NowPlayingService.parseScriptOutput("") == nil)
        #expect(NowPlayingService.parseScriptOutput("   \n") == nil)
    }
}
