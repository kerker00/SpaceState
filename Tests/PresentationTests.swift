import AppIntents
import CoreLocation
import Foundation
import MainframeStatus
import SpaceAPI
import SwiftUI
import Testing

@Suite
struct PresentationTests {
    // MARK: Status words, symbols and colors

    @Test func spaceStatusesHaveDistinctWordsAndSymbols() {
        let statuses: [SpaceStatus] = [.open, .closed, .unknown]
        #expect(statuses.map { String(localized: $0.title) } == ["Open", "Closed", "Unknown"])
        #expect(Set(statuses.map(\.symbolName)).count == 3)
        #expect(statuses.map(\.color) == [.green, .red, .secondary])
    }

    @Test func roomStatesHaveWordsAndColors() {
        let states: [MainframeRoomState] = [.closed, .keyholder, .member, .open, .openPlus, .closing, .unknown(""), .unknown("odd")]
        #expect(states.map { String(localized: $0.title) } == ["Closed", "Keyholders only", "Members only", "Open", "Open+", "Closing", "Unknown", "Unknown (odd)"])
        #expect(states.map(\.color) == [.red, .orange, .orange, .green, .green, .orange, .secondary, .secondary])
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func paletteColorsFollowTheStatus(scheme: ColorScheme) {
        let palette = SpacePalette(colorScheme: scheme, contrast: .standard)
        #expect(SpaceStatus.open.color(in: palette) == palette.statusOpen)
        #expect(SpaceStatus.closed.color(in: palette) == palette.statusClosed)
        #expect(SpaceStatus.unknown.color(in: palette) == palette.statusUnknown)
        #expect(MainframeRoomState.openPlus.color(in: palette) == palette.statusOpen)
        #expect(MainframeRoomState.member.color(in: palette) == palette.accent)
        #expect(MainframeRoomState.closed.color(in: palette) == palette.statusClosed)
        #expect(MainframeRoomState.unknown("").color(in: palette) == palette.statusUnknown)
    }

    @Test func pushStatusMessagesExplainEveryStateButOff() {
        #expect(PushStore.Status.off.message == nil)
        let states: [PushStore.Status] = [.denied, .registering, .registered, .failed("timeout")]
        #expect(states.allSatisfy { $0.message != nil })
        // Interpolated keys do not compare by value; the reason must at least be part of the key.
        #expect(String(describing: PushStore.Status.failed("timeout").message).contains("timeout"))
    }

    // MARK: Palette legibility (WCAG AA: 4.5 : 1 for text)

    private static func luminance(_ color: Color) -> Double {
        let resolved = color.resolve(in: EnvironmentValues())
        return 0.2126 * Double(resolved.linearRed) + 0.7152 * Double(resolved.linearGreen) + 0.0722 * Double(resolved.linearBlue)
    }

    private static func contrast(_ a: Color, _ b: Color) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    @Test(arguments: [ColorScheme.light, .dark], [ColorSchemeContrast.standard, .increased])
    func textColorsAreLegibleOnEverySurface(scheme: ColorScheme, contrast: ColorSchemeContrast) {
        let p = SpacePalette(colorScheme: scheme, contrast: contrast)
        for foreground in [p.text, p.secondaryText, p.accent, p.statusOpen, p.statusClosed, p.statusUnknown] {
            for background in [p.background, p.surface] {
                #expect(Self.contrast(foreground, background) >= 4.5)
            }
        }
        // Prominent buttons draw the page background on the accent.
        #expect(Self.contrast(p.background, p.accent) >= 4.5)
    }

    @Test func increasedContrastStrengthensSecondaryTextAndBorders() {
        for scheme in [ColorScheme.light, .dark] {
            let standard = SpacePalette(colorScheme: scheme, contrast: .standard)
            let increased = SpacePalette(colorScheme: scheme, contrast: .increased)
            #expect(increased.secondaryText == increased.text)
            #expect(increased.border == increased.text)
            #expect(Self.contrast(increased.secondaryText, increased.surface) > Self.contrast(standard.secondaryText, standard.surface))
        }
    }

    @Test func menuBarAppearanceUsesSystemColors() {
        let standard = SpacePalette(colorScheme: .dark, contrast: .standard, appearance: .menuBar)
        #expect(standard.background == .clear)
        #expect(standard.surface == .clear)
        #expect(standard.text == .primary)
        #expect(standard.secondaryText == .secondary)
        #expect(standard.statusOpen == .green)
        #expect(standard.statusClosed == .red)
        let increased = SpacePalette(colorScheme: .light, contrast: .increased, appearance: .menuBar)
        #expect(increased.secondaryText == .primary)
        #expect(increased.statusUnknown == .primary)
    }

    @Test func appearanceDefaultsToTheAppStyle() {
        #expect(EnvironmentValues().spaceAppearance == .app)
        var values = EnvironmentValues()
        values.spaceAppearance = .menuBar
        #expect(values.spaceAppearance == .menuBar)
    }

    // MARK: Onboarding location

    private func fix(accuracy: Double = 100, age: TimeInterval = 0, latitude: Double = 53.14, now: Date) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: 8.21), altitude: 0,
                   horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: now.addingTimeInterval(-age))
    }

    @Test func onlyRecentValidFixesSuggestASpace() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let good = fix(now: now)
        #expect(OnboardingLocation.usableLocation(in: [good], now: now) === good)
        #expect(OnboardingLocation.usableLocation(in: [], now: now) == nil)
        #expect(OnboardingLocation.usableLocation(in: [fix(accuracy: -1, now: now)], now: now) == nil)
        #expect(OnboardingLocation.usableLocation(in: [fix(accuracy: .infinity, now: now)], now: now) == nil)
        #expect(OnboardingLocation.usableLocation(in: [fix(age: 61, now: now)], now: now) == nil)
        #expect(OnboardingLocation.usableLocation(in: [fix(age: -61, now: now)], now: now) == nil)
        #expect(OnboardingLocation.usableLocation(in: [fix(latitude: 91, now: now)], now: now) == nil)
    }

    @Test func theNewestUsableFixWins() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let older = fix(age: 30, now: now)
        let newer = fix(age: 5, now: now)
        let invalid = fix(accuracy: -1, now: now)
        #expect(OnboardingLocation.usableLocation(in: [older, newer, invalid], now: now) === newer)
    }

    @MainActor
    @Test func callbacksFromAnotherManagerAreIgnored() {
        let location = OnboardingLocation()
        let foreign = CLLocationManager()
        location.locationManagerDidChangeAuthorization(foreign)
        location.locationManager(foreign, didUpdateLocations: [fix(now: Date())])
        location.locationManager(foreign, didFailWithError: CLError(.locationUnknown))
        #expect(!location.isRequesting)
        location.cancel()
        #expect(!location.isRequesting)
    }
}

// MARK: Widget space settings

@Suite(.serialized)
@MainActor
struct SpaceEntityTests {
    private let namesKey = "spaceNames"

    @Test func mainframeIsBuiltIn() async throws {
        #expect(SpaceEntity.known(Mainframe.spaceAPIEndpoint.absoluteString).name == "Mainframe")
        #expect(SpaceEntity.mainframe.address == "Oldenburg")
        #expect(await SpaceQuery().defaultResult()?.id == SpaceEntity.mainframe.id)
    }

    @Test func rememberedNamesAreUsedWithoutTheNetwork() async throws {
        defer { UserDefaults.standard.removeObject(forKey: namesKey) }
        SpaceEntity.remember([
            SpaceEntity(id: "https://a.invalid/api", name: "A", address: nil),
            SpaceEntity(id: "https://a.invalid/api", name: "Duplicate", address: nil)
        ])
        #expect(SpaceEntity.known("https://a.invalid/api").name == "A")
        #expect(SpaceEntity.known("https://unknown.invalid/api").name == "unknown.invalid")
        #expect(SpaceEntity.known("not a url").name == "not a url")
        let found = try await SpaceQuery().entities(for: ["https://a.invalid/api", Mainframe.spaceAPIEndpoint.absoluteString])
        #expect(found.map(\.name) == ["A", "Mainframe"])
    }

    @Test func directoryEntriesBecomeSettings() async throws {
        let responses = ObservationResponses()
        responses.directoryBody = #"[{"url":"https://lab.invalid/api","data":{"space":"Lab","location":{"address":"Main Street 1"},"state":{"open":true}}}]"#
        let directory = DirectoryStore(service: responses.service(proxy: false), now: { responses.clock.date })
        await directory.load()
        let entity = try #require(directory.entries.first.map(SpaceEntity.init))
        #expect(entity.id == "https://lab.invalid/api")
        #expect(entity.name == "Lab")
        #expect(entity.address == "Main Street 1")
        #expect(String(localized: entity.displayRepresentation.title) == "Lab")
    }
}
