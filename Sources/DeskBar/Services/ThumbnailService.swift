import AppKit
import Combine
import ScreenCaptureKit

@MainActor
final class ThumbnailService: ObservableObject {
    @Published var isScreenRecordingGranted: Bool

    private let cacheTTL: TimeInterval = 2
    private var cache: [CGWindowID: CachedThumbnail] = [:]
    private let checkScreenCaptureAccess: () -> Bool
    private let shareableContentProvider: () async throws -> SCShareableContent

    init(
        checkScreenCaptureAccess: @escaping () -> Bool = CGPreflightScreenCaptureAccess,
        shareableContentProvider: @escaping () async throws -> SCShareableContent = { try await SCShareableContent.current }
    ) {
        self.checkScreenCaptureAccess = checkScreenCaptureAccess
        self.shareableContentProvider = shareableContentProvider
        isScreenRecordingGranted = checkScreenCaptureAccess()
    }

    func refreshScreenRecordingPermission() {
        isScreenRecordingGranted = checkScreenCaptureAccess()
    }

    @discardableResult
    func requestScreenRecordingPermission() -> Bool {
        if checkScreenCaptureAccess() {
            isScreenRecordingGranted = true
            return true
        }

        let granted = CGRequestScreenCaptureAccess()
        isScreenRecordingGranted = granted
        return granted
    }

    func captureThumbnail(
        windowID: CGWindowID,
        size: CGSize = CGSize(width: 200, height: 200)
    ) async -> NSImage? {
        guard windowID != 0 else {
            return nil
        }

        pruneExpiredCache()

        guard checkScreenCaptureAccess() else {
            isScreenRecordingGranted = false
            // A legacy capture attempt here can prompt even though this was only a hover.
            return nil
        }

        isScreenRecordingGranted = true

        if let cached = cachedThumbnail(windowID: windowID) {
            return cached
        }

        guard let content = try? await shareableContentProvider() else {
            return nil
        }

        let windowsByID = Dictionary(preservingFirstValues: content.windows.map { ($0.windowID, $0) })
        return await captureThumbnail(
            windowID: windowID,
            size: size,
            screenCaptureWindowsByID: windowsByID
        )
    }

    func cachedThumbnail(windowID: CGWindowID) -> NSImage? {
        guard windowID != 0 else {
            return nil
        }

        pruneExpiredCache()
        guard let cached = cache[windowID], cached.expirationDate > Date() else {
            return nil
        }

        return cached.image
    }

    func makeCaptureSession() async -> ThumbnailCaptureSession {
        pruneExpiredCache()

        guard checkScreenCaptureAccess() else {
            isScreenRecordingGranted = false
            return ThumbnailCaptureSession(
                thumbnailService: self,
                screenCaptureWindowsByID: nil
            )
        }

        isScreenRecordingGranted = true

        guard let content = try? await shareableContentProvider() else {
            return ThumbnailCaptureSession(
                thumbnailService: self,
                screenCaptureWindowsByID: nil
            )
        }

        return ThumbnailCaptureSession(
            thumbnailService: self,
            screenCaptureWindowsByID: Dictionary(preservingFirstValues: content.windows.map { ($0.windowID, $0) })
        )
    }

    fileprivate func captureThumbnail(
        windowID: CGWindowID,
        size: CGSize,
        screenCaptureWindowsByID: [CGWindowID: SCWindow]?
    ) async -> NSImage? {
        guard windowID != 0 else {
            return nil
        }

        guard checkScreenCaptureAccess() else {
            isScreenRecordingGranted = false
            return nil
        }

        if let cached = cachedThumbnail(windowID: windowID) {
            return cached
        }

        guard let window = screenCaptureWindowsByID?[windowID] else {
            return nil
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)

        let config = SCStreamConfiguration()
        config.width = Int(size.width) * 2
        config.height = Int(size.height) * 2
        config.scalesToFit = true
        config.showsCursor = false

        guard let image = try? await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        ) else {
            return nil
        }

        let thumbnail = NSImage(cgImage: image, size: size)
        cache[windowID] = CachedThumbnail(
            image: thumbnail,
            expirationDate: Date().addingTimeInterval(cacheTTL)
        )
        return thumbnail
    }

    private func pruneExpiredCache() {
        let now = Date()
        cache = cache.filter { $0.value.expirationDate > now }
    }
}

private struct CachedThumbnail {
    let image: NSImage
    let expirationDate: Date
}

@MainActor
final class ThumbnailCaptureSession {
    private weak var thumbnailService: ThumbnailService?
    private let screenCaptureWindowsByID: [CGWindowID: SCWindow]?

    init(
        thumbnailService: ThumbnailService,
        screenCaptureWindowsByID: [CGWindowID: SCWindow]?
    ) {
        self.thumbnailService = thumbnailService
        self.screenCaptureWindowsByID = screenCaptureWindowsByID
    }

    func captureThumbnail(
        windowID: CGWindowID,
        size: CGSize
    ) async -> NSImage? {
        await thumbnailService?.captureThumbnail(
            windowID: windowID,
            size: size,
            screenCaptureWindowsByID: screenCaptureWindowsByID
        )
    }
}
