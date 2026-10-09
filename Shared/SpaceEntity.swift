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

    private static let namesKey = "spaceNames"

    /// The space for an identifier without going to the network: Mainframe is built in,
    /// others are remembered from the last loaded list, anything else shows its host.
    static func known(_ id: String) -> SpaceEntity {
        if id == mainframe.id {
            return .mainframe
        }
        let names = UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String]
        return SpaceEntity(id: id, name: names?[id] ?? URL(string: id)?.host() ?? id, address: nil)
    }

    static func remember(_ spaces: [SpaceEntity]) {
        let names = Dictionary(spaces.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        UserDefaults.standard.set(names, forKey: namesKey)
    }
}

/// Offers the spaces from the directory, searchable by name and address.
struct SpaceQuery: EntityStringQuery {
    /// Answered without the network: the system asks while setting up a widget and
    /// cancels slow answers, which on macOS left widgets without a configuration.
    func entities(for identifiers: [SpaceEntity.ID]) async throws -> [SpaceEntity] {
        identifiers.map(SpaceEntity.known)
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
        let spaces = try await StatusService.configured.directory().map(SpaceEntity.init)
        SpaceEntity.remember(spaces)
        return spaces
    }
}

struct SelectSpaceIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Space"
    static let description = IntentDescription("Shows whether this space is open.")

    @Parameter(title: "Space")
    var space: SpaceEntity?

    init() {}
}
