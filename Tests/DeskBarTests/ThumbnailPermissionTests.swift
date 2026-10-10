import AppKit
import Testing
@testable import DeskBar

@MainActor
struct ThumbnailPermissionTests {
    @Test
    func deniedAccessDoesNotAttemptCaptureOnHoverOrInSwitcherSession() async {
        var contentRequests = 0
        let service = ThumbnailService(checkScreenCaptureAccess: { false }, shareableContentProvider: {
            contentRequests += 1
            throw NSError(domain: "ThumbnailPermissionTests", code: 1)
        })
        #expect(await service.captureThumbnail(windowID: 123) == nil)
        let session = await service.makeCaptureSession()
        #expect(await session.captureThumbnail(windowID: 123, size: NSSize(width: 200, height: 200)) == nil)
        #expect(contentRequests == 0)
        #expect(!service.isScreenRecordingGranted)
    }

    @Test
    func shareableContentFailureReturnsNoPreviewWithoutLegacyFallback() async {
        var contentRequests = 0
        let service = ThumbnailService(checkScreenCaptureAccess: { true }, shareableContentProvider: {
            contentRequests += 1
            throw NSError(domain: "ThumbnailPermissionTests", code: 1)
        })
        #expect(await service.captureThumbnail(windowID: 123) == nil)
        let session = await service.makeCaptureSession()
        #expect(await session.captureThumbnail(windowID: 123, size: NSSize(width: 200, height: 200)) == nil)
        #expect(contentRequests == 2)
    }

    @Test
    func captureSessionRechecksPermissionAfterRevocation() async {
        var hasAccess = true
        let service = ThumbnailService(checkScreenCaptureAccess: { hasAccess }, shareableContentProvider: {
            throw NSError(domain: "ThumbnailPermissionTests", code: 1)
        })
        let session = await service.makeCaptureSession()
        hasAccess = false
        #expect(await session.captureThumbnail(windowID: 123, size: NSSize(width: 200, height: 200)) == nil)
        #expect(!service.isScreenRecordingGranted)
    }
}
