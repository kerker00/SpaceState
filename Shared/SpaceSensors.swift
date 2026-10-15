import Foundation
import SpaceAPI

enum SpaceSensorKind: String, Sendable, CaseIterable {
    case visitors, temperature, humidity, carbonDioxide, pressure, doorLocked
    case members, networkConnections, beverages, powerConsumption, powerGeneration

    var title: LocalizedStringResource {
        switch self {
        case .visitors: "Visitors"
        case .temperature: "Temperature"
        case .humidity: "Humidity"
        case .carbonDioxide: "CO₂"
        case .pressure: "Pressure"
        case .doorLocked: "Door lock"
        case .members: "Members"
        case .networkConnections: "Network connections"
        case .beverages: "Beverages"
        case .powerConsumption: "Power consumption"
        case .powerGeneration: "Power generation"
        }
    }

    var symbol: String {
        switch self {
        case .visitors, .members: "person.2"
        case .temperature: "thermometer"
        case .humidity: "humidity"
        case .carbonDioxide: "leaf"
        case .pressure: "gauge"
        case .doorLocked: "lock"
        case .networkConnections: "network"
        case .beverages: "mug"
        case .powerConsumption: "bolt"
        case .powerGeneration: "sun.max"
        }
    }
}

struct SpaceSensorReading: Identifiable, Sendable, Equatable {
    enum Value: Sendable, Equatable {
        case number(Double)
        case boolean(Bool)

        func text(locale: Locale) -> String {
            switch self {
            case .number(let value):
                value.formatted(.number.locale(locale).grouping(.never).precision(.significantDigits(1...15)))
            case .boolean(let locked):
                String(localized: locked ? "Locked" : "Unlocked", locale: locale)
            }
        }
    }

    let id: String
    let kind: SpaceSensorKind
    let value: Value
    let unit: String?
    let location: String?
    let name: String?
    let description: String?
    let lastChange: Date?
    var place: String? { location ?? name }

    func valueText(locale: Locale) -> String {
        value.text(locale: locale) + (unit.map { " \($0)" } ?? "")
    }
}

/// Only data actually shown by the widget participates in app-triggered reloads.
struct WidgetSensorReading: Identifiable, Sendable, Equatable {
    let kind: SpaceSensorKind
    let value: Double
    let unit: String?
    let place: String?
    var id: SpaceSensorKind { kind }

    func valueText(locale: Locale) -> String {
        SpaceSensorReading.Value.number(value).text(locale: locale) + (unit.map { " \($0)" } ?? "")
    }
}

/// All supported typed readings for details; one reading per preferred kind for
/// status. Counts are never summed and provider units are never inferred/converted.
struct SpaceSensorPresentation {
    let readings: [SpaceSensorReading]

    init(_ sensors: SpaceInfo.Sensors) {
        func numeric(_ kind: SpaceSensorKind, _ values: [SpaceInfo.Sensor<Double>], count: Bool = false) -> [SpaceSensorReading] {
            values.enumerated().compactMap { index, sensor in
                guard sensor.value.isFinite,
                      !count || (sensor.value >= 0 && sensor.value.rounded() == sensor.value) else { return nil }
                return reading(kind, index: index, sensor: sensor, value: .number(sensor.value))
            }
        }
        readings = numeric(.visitors, sensors.peopleNowPresent, count: true)
            + numeric(.temperature, sensors.temperature)
            + numeric(.humidity, sensors.humidity)
            + numeric(.carbonDioxide, sensors.carbonDioxide)
            + numeric(.pressure, sensors.barometer)
            + sensors.doorLocked.enumerated().map { index, sensor in
                reading(.doorLocked, index: index, sensor: sensor, value: .boolean(sensor.value))
            }
            + numeric(.members, sensors.totalMemberCount, count: true)
            + numeric(.networkConnections, sensors.networkConnections, count: true)
            + numeric(.beverages, sensors.beverageSupply)
            + numeric(.powerConsumption, sensors.powerConsumption)
            + numeric(.powerGeneration, sensors.powerGeneration)
    }

    var summary: [SpaceSensorReading] {
        [SpaceSensorKind.visitors, .temperature, .humidity, .carbonDioxide].compactMap { kind in
            readings.first { $0.kind == kind }
        }
    }

    var widget: [WidgetSensorReading] {
        summary.compactMap { reading in
            guard reading.kind == .visitors || reading.kind == .temperature,
                  case .number(let value) = reading.value else { return nil }
            return WidgetSensorReading(kind: reading.kind, value: value, unit: reading.unit, place: reading.place)
        }
    }

    static func isCurrent(timing: ObservationTiming?, failed: Bool = false, at date: Date) -> Bool {
        !failed && timing?.freshness(at: date) == .current
    }

    static func widget(info: SpaceInfo?, timing: ObservationTiming?, failed: Bool = false, at date: Date) -> [WidgetSensorReading] {
        guard let info, isCurrent(timing: timing, failed: failed, at: date) else { return [] }
        return SpaceSensorPresentation(info.sensors).widget
    }
}

private func reading<T>(_ kind: SpaceSensorKind, index: Int, sensor: SpaceInfo.Sensor<T>,
                        value: SpaceSensorReading.Value) -> SpaceSensorReading {
    SpaceSensorReading(id: "\(kind.rawValue):\(index)", kind: kind, value: value,
        unit: sensorText(sensor.unit), location: sensorText(sensor.location),
        name: sensorText(sensor.name), description: sensorText(sensor.description),
        lastChange: sensor.lastChange.flatMap {
            let seconds = $0.timeIntervalSince1970
            return seconds.isFinite && (0...253_402_300_799).contains(seconds) ? $0 : nil
        })
}

private func sensorText(_ value: String?) -> String? {
    guard let value else { return nil }
    let text = value.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }
        .joined().trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
}
