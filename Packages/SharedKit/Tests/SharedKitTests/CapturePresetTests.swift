import CoreGraphics
import Foundation
import Testing
@testable import SharedKit

@Suite("CapturePreset")
struct CapturePresetTests {
    @Test("Display name for freeform")
    func freeformDisplayName() {
        #expect(CapturePreset.freeform.displayName == "Freeform")
    }

    @Test("Display name for ratio with name")
    func ratioWithName() {
        let preset = CapturePreset.aspectRatio(width: 1, height: 1, name: "Square")
        #expect(preset.displayName == "1:1 (Square)")
    }

    @Test("Display name for ratio without name")
    func ratioWithoutName() {
        let preset = CapturePreset.aspectRatio(width: 16, height: 9, name: nil)
        #expect(preset.displayName == "16:9")
    }

    @Test("Display name for fixed size with name")
    func fixedSizeWithName() {
        let preset = CapturePreset.fixedSize(width: 1280, height: 720, name: "720p")
        #expect(preset.displayName == "1280 × 720 (720p)")
    }

    @Test("Display name for fixed size without name")
    func fixedSizeWithoutName() {
        let preset = CapturePreset.fixedSize(width: 512, height: 512, name: nil)
        #expect(preset.displayName == "512 × 512")
    }

    @Test("Badge text is nil for freeform")
    func freeformBadge() {
        #expect(CapturePreset.freeform.badgeText == nil)
    }

    @Test("Badge text for ratio")
    func ratioBadge() {
        let preset = CapturePreset.aspectRatio(width: 4, height: 3, name: nil)
        #expect(preset.badgeText == "4:3")
    }

    @Test("Badge text for fixed size")
    func fixedSizeBadge() {
        let preset = CapturePreset.fixedSize(width: 512, height: 512, name: nil)
        #expect(preset.badgeText == "Fixed")
    }

    @Test("isFixedSize returns true only for fixedSize")
    func isFixedSize() {
        #expect(CapturePreset.freeform.isFixedSize == false)
        #expect(CapturePreset.aspectRatio(width: 4, height: 3, name: nil).isFixedSize == false)
        #expect(CapturePreset.fixedSize(width: 512, height: 512, name: nil).isFixedSize == true)
    }

    @Test("Ratio calculation")
    func ratioCalculation() {
        #expect(CapturePreset.freeform.ratio == nil)
        #expect(CapturePreset.aspectRatio(width: 16, height: 9, name: nil).ratio == CGFloat(16) / CGFloat(9))
        #expect(CapturePreset.fixedSize(width: 1920, height: 1080, name: nil).ratio == CGFloat(1920) / CGFloat(1080))
    }

    @Test("Fixed pixel size extraction")
    func fixedPixelSize() {
        #expect(CapturePreset.freeform.fixedPixelSize == nil)
        #expect(CapturePreset.aspectRatio(width: 4, height: 3, name: nil).fixedPixelSize == nil)
        let size = CapturePreset.fixedSize(width: 512, height: 512, name: nil).fixedPixelSize
        #expect(size?.width == 512)
        #expect(size?.height == 512)
    }

    @Test("Unique IDs for all built-in presets")
    func uniqueBuiltinIDs() {
        let ids = CapturePreset.allBuiltins.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let presets: [CapturePreset] = [
            .freeform,
            .aspectRatio(width: 4, height: 3, name: "Test"),
            .fixedSize(width: 800, height: 600, name: nil),
        ]
        let data = try JSONEncoder().encode(presets)
        let decoded = try JSONDecoder().decode([CapturePreset].self, from: data)
        #expect(decoded == presets)
    }

    @Test("Built-in counts")
    func builtinCounts() {
        #expect(CapturePreset.builtinAspectRatios.count == 5)
        #expect(CapturePreset.builtinFixedSizes.count == 3)
        #expect(CapturePreset.allBuiltins.count == 8)
    }

    @Test("AppSettings defaults to freeform preset")
    func settingsDefaultPreset() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-presets-\(UUID())")!)
        #expect(settings.capturePreset == .freeform)
        #expect(settings.customCapturePresets.isEmpty)
        #expect(settings.hiddenBuiltinPresets.isEmpty)
    }

    @Test("AppSettings persists capture preset round-trip")
    func settingsPersistPreset() {
        let suite = UserDefaults(suiteName: "test-presets-\(UUID())")!
        let settings = AppSettings(defaults: suite)
        settings.capturePreset = .aspectRatio(width: 16, height: 9, name: nil)

        let settings2 = AppSettings(defaults: suite)
        #expect(settings2.capturePreset == .aspectRatio(width: 16, height: 9, name: nil))
    }

    @Test("visiblePresets excludes hidden built-ins")
    func visiblePresetsFiltering() {
        let suite = UserDefaults(suiteName: "test-presets-\(UUID())")!
        let settings = AppSettings(defaults: suite)
        settings.hiddenBuiltinPresets = [.aspectRatio(width: 3, height: 2, name: nil)]
        settings.customCapturePresets = [.fixedSize(width: 800, height: 600, name: "Custom")]

        let visible = settings.visiblePresets
        #expect(!visible.contains(.aspectRatio(width: 3, height: 2, name: nil)))
        #expect(visible.contains(.fixedSize(width: 800, height: 600, name: "Custom")))
        #expect(visible.first == .freeform)
    }
}
