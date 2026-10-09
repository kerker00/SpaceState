import AppIntents
import MainframeStatus
import SpaceAPI
import SpacePushClient

/// A space as a widget setting, identified by its SpaceAPI endpoint.
struct SpaceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Space"
    static let defaultQuery = SpaceQuery()

    static let mainframe = SpaceEntity(
        id: Mainframe.spaceAPIEndpoint.absoluteString, name: "Mainframe", address: "Oldenburg"
    )

    let id: String
    let name: String
    let address: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: address.map { "\($0)" })
    }

    init(id: String, name: String, address: String?) {
        self.id = id
        self.name = name
        self.address = address
    }

    init(_ entry: DirectoryEntry) {
        self.init(id: entry.endpoint.absoluteString, name: entry.info.name, address: entry.info.location?.address)
    }
}

/// Offers the spaces from the directory, searchable by name and address.
struct SpaceQuery: EntityStringQuery {
    func entities(for identifiers: [SpaceEntity.ID]) async throws -> [SpaceEntity] {
        let spaces = try await allSpaces()
        return identifiers.compactMap { id in spaces.first { $0.id == id } }
    }

    func entities(matching query: String) async throws -> [SpaceEntity] {
        try await allSpaces().filter {
            $0.name.localizedStandardContains(query) || ($0.address?.localizedStandardContains(query) ?? false)
        }
    }

    func suggestedEntities() async throws -> [SpaceEntity] {
        try await allSpaces()
    }

    func defaultResult() async -> SpaceEntity? {
        .mainframe
    }

    private func allSpaces() async throws -> [SpaceEntity] {
        try await StatusService.configured.directory().map(SpaceEntity.init)
    }
}

struct SelectSpaceIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Space"
    static let description = IntentDescription("Shows whether this space is open.")

    @Parameter(title: "Space")
    var space: SpaceEntity?

    init() {}
}
