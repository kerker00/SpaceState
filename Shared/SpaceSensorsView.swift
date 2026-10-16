import SpaceAPI
import SwiftUI

struct SpaceSensorsCard: View {
    enum Mode { case summary, details }
    let sensors: SpaceInfo.Sensors
    var timing: ObservationTiming?
    var failed = false
    var mode: Mode = .summary
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.spaceAppearance) private var appearance
    @Environment(\.locale) private var locale

    private var palette: SpacePalette {
        SpacePalette(colorScheme: colorScheme, contrast: contrast, appearance: appearance)
    }

    var body: some View {
        let presentation = SpaceSensorPresentation(sensors)
        let readings = mode == .details ? presentation.readings : presentation.summary
        if !readings.isEmpty {
            SpaceCard(mode == .details ? "Sensors" : "Climate and visitors") {
                let date = Date()
                let dates = [date] + [timing?.expiresAt].compactMap { $0 }.filter { $0 > date }
                TimelineView(.explicit(dates)) { context in
                    let current = SpaceSensorPresentation.isCurrent(timing: timing, failed: failed, at: context.date)
                    VStack(alignment: .leading, spacing: SpaceLayout.cardSpacing) {
                        if !current {
                            Text("Showing last known sensor values")
                                .font(SpaceTypography.label)
                                .foregroundStyle(palette.secondaryText)
                        }
                        ForEach(Array(readings.enumerated()), id: \.element.id) { index, reading in
                            if index > 0 {
                                Rectangle().fill(palette.border).frame(height: 1).accessibilityHidden(true)
                            }
                            row(reading)
                                .foregroundStyle(current ? palette.text : palette.secondaryText)
                        }
                    }
                }
            }
        }
    }

    private func row(_ reading: SpaceSensorReading) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: SpaceLayout.rowSpacing) {
                    title(reading).fixedSize()
                    Spacer(minLength: 0)
                    value(reading).fixedSize()
                }
                VStack(alignment: .leading, spacing: 5) {
                    title(reading)
                    value(reading)
                }
            }
            if mode == .details {
                if let location = reading.location { Text("Location: \(location)") }
                if let name = reading.name { Text("Sensor: \(name)") }
                if let description = reading.description { Text(verbatim: description) }
                if let changed = reading.lastChange {
                    Text("Value changed \(changed, format: .dateTime.year().day().month().hour().minute())")
                }
            } else if let place = reading.place {
                Text(verbatim: place)
                    .font(SpaceTypography.label)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
    }

    private func title(_ reading: SpaceSensorReading) -> some View {
        Label {
            Text(reading.kind.title)
        } icon: {
            Image(systemName: reading.kind.symbol).accessibilityHidden(true)
        }
        .font(SpaceTypography.label)
        .foregroundStyle(palette.secondaryText)
    }

    private func value(_ reading: SpaceSensorReading) -> some View {
        Text(verbatim: reading.valueText(locale: locale))
            .font(SpaceTypography.body.weight(.semibold))
    }
}

#if DEBUG
private enum SensorPreview {
    static var values: SpaceInfo.Sensors {
        .init(temperature: [.init(value: 21.5, unit: "°C", location: "Werkstatt mit einem sehr langen Namen",
                                 name: "Arbeitstisch", description: "Sensor neben der Tür", lastChange: .now.addingTimeInterval(-3600))],
              humidity: [.init(value: 50, unit: "%")], carbonDioxide: [.init(value: 600, unit: "ppm")],
              doorLocked: [.init(value: false)], peopleNowPresent: [.init(value: 3)],
              beverageSupply: [.init(value: 0, unit: "btl", name: "Club-Mate")])
    }
    static var current: ObservationTiming { .init(source: .direct, observedAt: .now, receivedAt: .now) }
}

#Preview("Sensors · DE") {
    SpaceSensorsCard(sensors: SensorPreview.values, timing: SensorPreview.current)
        .environment(\.locale, Locale(identifier: "de"))
        .padding().frame(width: 360)
}

#Preview("Sensor details · EN dark") {
    ScrollView {
        SpaceSensorsCard(sensors: SensorPreview.values, timing: SensorPreview.current, mode: .details)
            .padding()
    }
    .environment(\.locale, Locale(identifier: "en"))
    .preferredColorScheme(.dark).frame(width: 440, height: 700)
}

#Preview("Last known sensors · DE large text") {
    SpaceSensorsCard(sensors: SensorPreview.values, timing: SensorPreview.current, failed: true)
        .environment(\.locale, Locale(identifier: "de"))
        .dynamicTypeSize(.accessibility2)
        .padding().frame(width: 360)
}
#endif
