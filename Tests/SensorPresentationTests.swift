import Foundation
import MainframeStatus
import SpaceAPI
import SpacePushClient
import Testing

@MainActor
private final class SensorFixture {
    let clock = ObservationTestClock(Date(timeIntervalSince1970: 1000))
    let suite = "net.grafixmafia.SpaceState.SensorTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let expiry = ControlledRetry()
    var temperature = 21.5
    var changed = 100.0
    var failed = false
    var reloads = 0
    var store: StatusStore!

    init(temporary: Bool = false) {
        defaults = UserDefaults(suiteName: suite)!
        defaults.set("https://primary.invalid/api", forKey: "spaceEndpoint")
        let clock = clock
        let service = StatusService(spacePush: nil, direct: StatusClient(now: { clock.date }, load: { request in
            try await self.load(request)
        }))
        store = StatusStore(service: service, defaults: defaults,
            reloadWidgets: { [weak self] in self?.reloads += 1 },
            waitForExpiry: { [weak self] _ in
                guard let self else { throw CancellationError() }
                try await self.expiry.sleep()
            }, now: { clock.date },
            selection: temporary ? .temporary(URL(string: "https://temporary.invalid/api")!) : .saved)
    }

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        if failed { throw URLError(.timedOut) }
        let body: [String: Any] = ["space": "Sensor Space", "state": ["open": true], "sensors": [
            "temperature": [["value": temperature, "unit": "°C", "location": "Lab", "lastchange": changed]],
            "people_now_present": [["value": 3]]]]
        return (try JSONSerialization.data(withJSONObject: body),
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    func close() {
        store.pausePolling()
        expiry.close()
        defaults.removePersistentDomain(forName: suite)
    }
}

@Suite(.serialized)
@MainActor
struct SensorPresentationTests {
    private let date = Date(timeIntervalSince1970: 1000)
    private let endpoint = URL(string: "https://sensor.invalid/api")!
    private var sensors: SpaceInfo.Sensors {
        .init(temperature: [.init(value: 21.5, unit: "°C", location: "Lab", name: "Desk", description: "Inside", lastChange: Date(timeIntervalSince1970: 100))],
              humidity: [.init(value: 50, unit: "%")], carbonDioxide: [.init(value: 600, unit: "ppm")],
              peopleNowPresent: [.init(value: 3)])
    }
    private func timing(_ observed: TimeInterval? = 900) -> ObservationTiming {
        ObservationTiming(source: .spacePush, observedAt: observed.map(Date.init(timeIntervalSince1970:)),
                          receivedAt: date, maximumAge: 200)
    }
    private func info(_ sensors: SpaceInfo.Sensors) -> SpaceInfo {
        SpaceInfo(name: "A", state: .init(open: true, lastChange: nil, message: nil, triggerPerson: nil), sensors: sensors)
    }
    private func widget(spaceTime: TimeInterval? = 900, roomTime: TimeInterval? = nil) -> WidgetSnapshot {
        WidgetSnapshot(fallbackName: "A", space: StatusObservation(value: info(sensors), timing: timing(spaceTime)),
            rooms: roomTime.map { StatusObservation(value: [MainframeRoom(id: "lab3d", state: .open, since: nil)], timing: timing($0)) },
            expectsRooms: roomTime != nil, endpoint: endpoint)
    }

    @Test func allSupportedKindsKeepTheirValuesAndMetadata() throws {
        let source = SpaceInfo.Sensors(temperature: sensors.temperature, humidity: sensors.humidity,
            carbonDioxide: sensors.carbonDioxide, barometer: [.init(value: 1000)], doorLocked: [.init(value: false)],
            peopleNowPresent: sensors.peopleNowPresent, totalMemberCount: [.init(value: 100)],
            networkConnections: [.init(value: 5)], beverageSupply: [.init(value: 0)],
            powerConsumption: [.init(value: 100)], powerGeneration: [.init(value: 200)])
        let rows = SpaceSensorPresentation(source).readings
        #expect(rows.count == 11)
        #expect(Set(rows.map(\.kind)) == Set(SpaceSensorKind.allCases))
        let temperature = try #require(rows.first { $0.kind == .temperature })
        #expect(temperature.value == .number(21.5))
        #expect(temperature.unit == "°C")
        #expect(temperature.location == "Lab")
        #expect(temperature.name == "Desk")
        #expect(temperature.description == "Inside")
        #expect(temperature.lastChange == Date(timeIntervalSince1970: 100))
    }

    @Test func summarySelectsOnePerKindAndDoesNotSumVisitorCounters() {
        var source = sensors
        source.peopleNowPresent.append(.init(value: 8, location: "Workshop"))
        source.temperature.append(.init(value: 10, unit: "°C", location: "Outside"))
        let view = SpaceSensorPresentation(source)
        #expect(view.summary.map(\.kind) == [.visitors, .temperature, .humidity, .carbonDioxide])
        #expect(view.summary.map(\.value) == [.number(3), .number(21.5), .number(50), .number(600)])
        #expect(view.readings.count == 6)
    }

    @Test func unitsAreNeverInferredOrConverted() {
        let view = SpaceSensorPresentation(.init(temperature: [.init(value: 68, unit: "°F"), .init(value: 20)]))
        #expect(view.readings.map { $0.valueText(locale: Locale(identifier: "en_US")) } == ["68 °F", "20"])
    }

    @Test func numericFormattingUsesLocaleAndPreservesZeroAndFalse() {
        let view = SpaceSensorPresentation(.init(temperature: sensors.temperature, doorLocked: [.init(value: false)],
                                                 peopleNowPresent: [.init(value: 0)]))
        #expect(view.readings.first?.valueText(locale: Locale(identifier: "en_US")) == "0")
        #expect(view.readings.first { $0.kind == .temperature }?.valueText(locale: Locale(identifier: "de_DE")) == "21,5 °C")
        #expect(view.readings.first { $0.kind == .doorLocked }?.value == .boolean(false))
    }

    @Test func rawMeasurementsAreRoundedForDisplay() {
        let german = Locale(identifier: "de_DE")
        let texts = [21.15358495178445, 44.119776247251586, 613.4, 1013.25, 0.0012345, -0.05999999865889549]
            .map { SpaceSensorReading.Value.number($0).text(locale: german) }
        #expect(texts == ["21,2", "44,1", "613", "1013", "0,0012", "-0,06"])
    }

    @Test func invalidCountsAndNonfiniteMeasurementsAreOmitted() {
        let view = SpaceSensorPresentation(.init(temperature: [.init(value: .nan), .init(value: .infinity), .init(value: -10)],
            peopleNowPresent: [.init(value: -1), .init(value: 1.5), .init(value: 0)],
            totalMemberCount: [.init(value: -1)], networkConnections: [.init(value: 2.5)]))
        #expect(view.readings.map(\.value) == [.number(0), .number(-10)])
    }

    @Test func metadataIsPlainTextAndEmptyFieldsDisappear() throws {
        let view = SpaceSensorPresentation(.init(temperature: [.init(value: 21, unit: " °C\n", location: "\t ",
            name: " Desk\n", description: "Line\u{1B}\tNext")]))
        let row = try #require(view.readings.first)
        #expect(row.unit == "°C")
        #expect(row.location == nil)
        #expect(row.place == "Desk")
        #expect(row.description == "Line  Next")
    }

    @Test func originalChangeTimeIsKeptAndUnusableDatesAreOmitted() {
        let times: [TimeInterval] = [100, .nan, .infinity, -1, 1e300]
        let view = SpaceSensorPresentation(.init(temperature: times.map {
            .init(value: 21, lastChange: Date(timeIntervalSince1970: $0))
        }))
        #expect(view.readings.first?.lastChange == Date(timeIntervalSince1970: 100))
        #expect(view.readings.dropFirst().allSatisfy { $0.lastChange == nil })
    }

    @Test func visitorNamesAndConnectedMachineListsAreNotPresented() throws {
        let document = try JSONDecoder().decode(SpaceInfo.self, from: Data(#"""
            {"space":"A","sensors":{"people_now_present":[{"value":3,"names":["Hidden person"]}],
             "network_connections":[{"value":2,"machines":[{"name":"Hidden machine"}]}]}}
            """#.utf8))
        let view = SpaceSensorPresentation(document.sensors)
        #expect(view.readings.count == 2)
        #expect(view.readings.allSatisfy { $0.name == nil && $0.description == nil })
        #expect(view.summary.first?.value == .number(3))
    }

    @Test func genericSensorJSONIsNotRenderedAsValidatedAppMeasurements() {
        let view = SpaceSensorPresentation(.init(other: ["wind": .array([.object(["value": .number(12)])])]))
        #expect(view.readings.isEmpty)
        #expect(view.summary.isEmpty)
        #expect(view.widget.isEmpty)
    }

    @Test func missingSensorsHaveNoRowsAndReadingIDsAreStable() {
        #expect(SpaceSensorPresentation(SpaceInfo(name: "A").sensors).readings.isEmpty)
        var source = sensors
        source.temperature.append(.init(value: 20))
        let ids = SpaceSensorPresentation(source).readings.map(\.id)
        #expect(ids == SpaceSensorPresentation(source).readings.map(\.id))
        #expect(Set(ids).count == ids.count)
    }

    @Test func widgetsSelectOnlyVisitorsAndTemperature() {
        let rows = SpaceSensorPresentation(sensors).widget
        #expect(rows.map(\.kind) == [.visitors, .temperature])
        #expect(rows.map(\.value) == [3, 21.5])
        #expect(rows.last?.place == "Lab")
    }

    @Test func widgetRevisionIgnoresDescriptionAndValueChangeTime() {
        var changed = sensors
        changed.temperature[0].description = "Other text"
        changed.temperature[0].lastChange = date
        #expect(SpaceSensorPresentation(sensors).widget == SpaceSensorPresentation(changed).widget)
    }

    @Test func widgetRevisionTracksValueUnitAndDisplayedPlace() {
        for index in 0..<3 {
            var changed = sensors
            if index == 0 { changed.temperature[0].value = 22 }
            if index == 1 { changed.temperature[0].unit = "K" }
            if index == 2 { changed.temperature[0].location = "Outside" }
            #expect(SpaceSensorPresentation(sensors).widget != SpaceSensorPresentation(changed).widget)
        }
    }

    @Test func failedOrMissingTimingCannotSupplyWidgetValues() {
        #expect(SpaceSensorPresentation.widget(info: info(sensors), timing: nil, at: date).isEmpty)
        #expect(SpaceSensorPresentation.widget(info: nil, timing: timing(), at: date).isEmpty)
        #expect(SpaceSensorPresentation.widget(info: info(sensors), timing: timing(), failed: true, at: date).isEmpty)
    }

    @Test func unknownFutureAndExpiredEvidenceCannotSupplyWidgetValues() {
        for observed: TimeInterval? in [nil, 1001, 99] {
            #expect(SpaceSensorPresentation.widget(info: info(sensors), timing: timing(observed), at: date).isEmpty)
        }
        let unreachable = ObservationTiming(source: .aggregator, observedAt: date, receivedAt: date, sourceReachable: false)
        #expect(SpaceSensorPresentation.widget(info: info(sensors), timing: unreachable, at: date).isEmpty)
    }

    @Test func widgetTimelineDropsSensorsExactlyAtSpaceExpiryAndKeepsDestination() {
        let entries = widget().entries(from: date)
        #expect(entries.map(\.date) == [date, Date(timeIntervalSince1970: 1100)])
        #expect(entries.map { $0.sensors.count } == [2, 0])
        #expect(entries.allSatisfy { $0.endpoint == endpoint && $0.widgetURL != nil })
        #expect(entries[1].observedAt == Date(timeIntervalSince1970: 900))
    }

    @Test func roomExpiryDoesNotRemoveCurrentSpaceSensors() {
        let entries = widget(spaceTime: 950, roomTime: 900).entries(from: date)
        #expect(entries.map { $0.sensors.count } == [2, 2, 0])
        #expect(entries[1].roomsUnavailable)
        #expect(entries[1].status == .open)
    }

    @Test func recentSensorChangeTimeCannotRefreshStaleDocumentEvidence() {
        var source = sensors
        source.temperature[0].lastChange = Date(timeIntervalSince1970: 9_999_999_999)
        let snapshot = WidgetSnapshot(fallbackName: "A", space: StatusObservation(value: info(source), timing: timing(99)),
                                      rooms: nil, expectsRooms: false)
        #expect(snapshot.entry(at: date).sensors.isEmpty)
        #expect(SpaceSensorPresentation(source).readings.first { $0.kind == .temperature }?.lastChange != nil)
    }

    @Test func currentSensorsCannotInventAnOpeningState() {
        let snapshot = WidgetSnapshot(fallbackName: "A", space: StatusObservation(value: SpaceInfo(name: "A", sensors: sensors), timing: timing()),
                                      rooms: nil, expectsRooms: false)
        #expect(snapshot.entry(at: date).status == .unknown)
        #expect(snapshot.entry(at: date).sensors.count == 2)
    }

    @Test func spaceFailureKeepsValidRoomsWithoutInventingSensorValues() {
        let snapshot = WidgetSnapshot(fallbackName: "A", space: nil,
            rooms: StatusObservation(value: [MainframeRoom(id: "lab3d", state: .open, since: nil)], timing: timing()),
            expectsRooms: true, endpoint: endpoint)
        #expect(snapshot.entry(at: date).sensors.isEmpty)
        #expect(snapshot.entry(at: date).rooms.first?.state == .open)
        #expect(snapshot.entry(at: date).widgetURL != nil)
    }

    @Test func sensorOnlyRefreshRequestsOneWidgetReload() async {
        let f = SensorFixture(); defer { f.close() }
        await f.store.refresh()
        let reloads = f.reloads
        f.temperature = 22
        await f.store.refresh()
        #expect(f.store.status == .open)
        #expect(f.reloads == reloads + 1)
        #expect(f.store.widgetSensorValues.last?.value == 22)
    }

    @Test func changedMetadataAndReceiptWithoutDisplayedChangesDoNotReloadWidgets() async {
        let f = SensorFixture(); defer { f.close() }
        await f.store.refresh()
        let reloads = f.reloads
        f.changed = 101
        f.clock.date = date.addingTimeInterval(10)
        await f.store.refresh()
        #expect(f.reloads == reloads)
        #expect(f.store.lastUpdate == date.addingTimeInterval(10))
    }

    @Test func failedRefreshRetainsHistoricalReadingsButClearsWidgetValues() async {
        let f = SensorFixture(); defer { f.close() }
        await f.store.refresh()
        let observed = f.store.observationTiming?.observedAt
        f.failed = true
        f.clock.date = date.addingTimeInterval(10)
        await f.store.refresh()
        #expect(f.store.widgetSensorValues.isEmpty)
        #expect(f.store.observationTiming?.observedAt == observed)
        #expect(f.store.lastAttempt == date.addingTimeInterval(10))
        #expect(f.store.lastError != nil)
        #expect(f.store.info.map { SpaceSensorPresentation($0.sensors).readings.count } == 2)
    }

    @Test func temporarySensorRefreshDoesNotPersistOrReloadPrimarySelection() async {
        let f = SensorFixture(temporary: true); defer { f.close() }
        await f.store.refresh()
        #expect(f.store.widgetSensorValues.count == 2)
        #expect(f.defaults.string(forKey: "spaceEndpoint") == "https://primary.invalid/api")
        #expect(f.defaults.object(forKey: "mainframePushRoomIDs") == nil)
        #expect(f.reloads == 0)
    }
}
