import Foundation
import MainframeStatus
import SpaceAPI
import SpacePushClient
import Testing

@Suite(.serialized)
@MainActor
struct SupportTypesTests {
    // MARK: Navigation

    @Test func openingAStatusURLCreatesATemporaryTarget() async throws {
        let f = StatusFixture(); defer { f.close() }
        let transport = f.transport
        let service = StatusService(spacePush: nil, direct: StatusClient(load: { try await transport.load($0) }))
        let navigation = SpaceNavigation { StatusStore(service: service, defaults: f.defaults, selection: .temporary($0)) }
        defer { navigation.close() }
        let target = try #require(SpaceDestination(endpoint: f.b.absoluteString))
        #expect(navigation.open(url: target.url))
        #expect(navigation.destination?.target == target)
        #expect(!navigation.open(url: URL(string: "https://example.org")!))
        #expect(navigation.destination?.target == target)
        // Rooms exist only for Mainframe.
        let room = try #require(SpaceDestination(endpoint: Mainframe.spaceAPIEndpoint.absoluteString, room: "radstelle"))
        #expect(navigation.open(url: room.url))
        #expect(navigation.destination?.target.room == "radstelle")
    }

    @Test func resumingAndPausingOnlyAffectTheTemporaryTarget() async throws {
        let f = StatusFixture(); defer { f.close() }
        let transport = f.transport
        let service = StatusService(spacePush: nil, direct: StatusClient(load: { try await transport.load($0) }))
        let navigation = SpaceNavigation { StatusStore(service: service, defaults: f.defaults, selection: .temporary($0)) }
        defer { navigation.close() }
        navigation.resume()
        navigation.pause()
        #expect(f.transport.requests.isEmpty)
        navigation.open(try #require(SpaceDestination(endpoint: f.b.absoluteString)))
        navigation.resume()
        try await f.waitForRequests(1)
        #expect(f.transport.requests[0].url?.host == "b.invalid")
        navigation.pause()
        #expect(navigation.destination?.store.isRefreshing == false)
        #expect(f.store.endpoint == f.a)
    }

    @Test func navigationDestinationsAreDistinct() throws {
        let target = try #require(SpaceDestination(endpoint: "https://a.invalid/status"))
        let store = StatusStore(defaults: UserDefaults(suiteName: "SupportTypesTests.\(UUID().uuidString)")!, selection: .temporary(target.endpoint))
        let first = SpaceNavigation.Destination(target: target, store: store)
        let second = SpaceNavigation.Destination(target: target, store: store)
        #expect(first.id != second.id)
    }

    // MARK: Sensors

    @Test func everySensorKindHasATitleAndSymbol() {
        for kind in SpaceSensorKind.allCases {
            #expect(!String(localized: kind.title).isEmpty)
            #expect(!kind.symbol.isEmpty)
        }
        #expect(SpaceSensorKind.visitors.symbol == SpaceSensorKind.members.symbol)
        #expect(Set(SpaceSensorKind.allCases.map(\.symbol)).count == SpaceSensorKind.allCases.count - 1)
        #expect(String(localized: SpaceSensorKind.carbonDioxide.title) == "CO₂")
    }

    @Test func doorLockValuesReadAsWords() {
        let english = Locale(identifier: "en_US")
        #expect(SpaceSensorReading.Value.boolean(true).text(locale: english) == "Locked")
        #expect(SpaceSensorReading.Value.boolean(false).text(locale: english) == "Unlocked")
    }

    @Test func widgetReadingsFormatLikeTheApp() {
        let reading = WidgetSensorReading(kind: .temperature, value: 21.15358495178445, unit: "°C", place: "Lab")
        #expect(reading.id == .temperature)
        #expect(reading.valueText(locale: Locale(identifier: "de_DE")) == "21,2 °C")
        #expect(WidgetSensorReading(kind: .visitors, value: 7, unit: nil, place: nil).valueText(locale: Locale(identifier: "en_US")) == "7")
    }

    // MARK: Identity and configuration

    @Test func userAgentNamesTheAppVersionAndSystem() throws {
        let agent = try #require(ClientIdentity.headers["User-Agent"])
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #expect(agent.hasPrefix("SpaceState/"))
        #expect(agent.contains("(macOS \(os.majorVersion).\(os.minorVersion)"))
        #expect(agent.hasSuffix(")"))
        #expect(ClientIdentity.headers.count == 1)
        #expect(ClientIdentity.platform == "macos")
    }

    @Test func appsOutsideAWidgetReportActivePeriods() {
        // The test bundle is not an app extension, so it counts like the app.
        #expect(ClientIdentity.activePeriods != nil)
    }

    @Test func missingServiceURLMeansDirectReadsOnly() {
        // The test bundle has no SpacePushURL in its Info.plist.
        #expect(StatusService.configuredServiceURL == nil)
        #expect(StatusService.configured.spacePush == nil)
    }

    @Test func configuredClientsIdentifyTheApp() {
        let base = URL(string: "https://push.invalid")!
        let client = SpacePushClient.configured(baseURL: base)
        #expect(client.baseURL == base)
        #expect(client.headers == ClientIdentity.headers)
        #expect(client.activePeriods != nil)
    }
}
