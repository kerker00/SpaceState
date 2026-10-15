import Foundation
import SpaceAPI
import SpacePushClient
import Testing

@Suite(.serialized)
@MainActor
struct SpaceDetailLinksTests {
    private let endpoint = URL(string: "https://linked.invalid/api?space=one&next=%2Ftwo#part")!
    private let website = URL(string: "https://website.invalid/about")!

    @Test func projectsKeepOrderAndCompleteDestinations() {
        let values = [website, endpoint]
        let rows = SpaceDetailLink.projects(for: values)
        #expect(rows.map(\.value) == values.map(\.absoluteString))
        #expect(rows.map(\.destination) == values.map(Optional.some))
    }

    @Test func unsafeProjectsRemainReadableWithoutActions() {
        let values = ["file:///tmp/a", "javascript:alert(1)", "/relative", "https://u:p@host.invalid/", "https://host.invalid:0/", "https://host.invalid/?x=%0a"].map { URL(string: $0)! }
        let rows = SpaceDetailLink.projects(for: values)
        #expect(rows.count == values.count)
        #expect(rows.allSatisfy { $0.destination == nil })
        #expect(rows.map(\.value) == values.map(\.absoluteString))
    }

    @Test func namedLinksPreservePlainNamesDescriptionsAndURLs() throws {
        let row = try #require(SpaceDetailLink.links(for: [.init(name: " **Tools**\nLab ", description: "A\tB", url: website)]).first)
        #expect(row.name == "**Tools** Lab")
        #expect(row.description == "A B")
        #expect(row.value == website.absoluteString)
        #expect(row.destination == website)
    }

    @Test func emptyMetadataUsesFallbackAndDoesNotCreateEmptyDescriptions() throws {
        let row = try #require(SpaceDetailLink.links(for: [.init(name: "\n  ", description: "\t", url: website)]).first)
        #expect(row.name == nil)
        #expect(row.description == nil)
    }

    @Test func unsupportedNamedLinksHaveNoExternalAction() throws {
        let row = try #require(SpaceDetailLink.links(for: [.init(name: "Local", description: "Read only", url: URL(string: "file:///tmp/a")!)]).first)
        #expect(row.destination == nil)
        #expect(row.name == "Local")
        #expect(row.description == "Read only")
    }

    @Test func duplicateProviderValuesHaveDistinctStableRowIdentities() {
        let input: [SpaceInfo.LinkedSpace] = [.init(endpoint: endpoint, website: website), .init(endpoint: endpoint, website: website)]
        let rows = SpaceLinkedSpace.rows(for: input)
        #expect(Set(rows.map(\.id)).count == 2)
        #expect(rows.map(\.id) == SpaceLinkedSpace.rows(for: input).map(\.id))
        #expect(Set(SpaceDetailLink.projects(for: [website, website]).map(\.id)).count == 2)
        #expect(Set(SpaceDetailLink.links(for: [.init(name: "A", url: website), .init(name: "A", url: website)]).map(\.id)).count == 2)
    }

    @Test func emptyCollectionsAndEmptyLinkedSpacesHaveNoRows() {
        #expect(SpaceDetailLink.projects(for: []).isEmpty)
        #expect(SpaceDetailLink.links(for: []).isEmpty)
        #expect(SpaceLinkedSpace.rows(for: [.init(endpoint: nil, website: nil)]).isEmpty)
    }

    @Test func linkedEndpointAndWebsiteKeepTheirSeparateActions() throws {
        let row = try #require(SpaceLinkedSpace.rows(for: [.init(endpoint: endpoint, website: website)]).first)
        #expect(row.target?.endpoint == endpoint)
        #expect(row.target?.room == nil)
        #expect(row.endpoint?.destination == nil)
        #expect(row.website?.destination == website)
        #expect(row.website?.destination != row.target?.endpoint)
        #expect(row.target.flatMap { SpaceDestination(url: $0.url) } == row.target)
    }

    @Test func websiteOnlySpacesCannotBeMistakenForAPIEndpoints() throws {
        let row = try #require(SpaceLinkedSpace.rows(for: [.init(endpoint: nil, website: website)]).first)
        #expect(row.target == nil)
        #expect(row.endpoint == nil)
        #expect(row.website?.destination == website)
    }

    @Test func invalidLinkedEndpointsRemainReadableWithoutAStatusTarget() throws {
        for value in ["file:///tmp/a", "https://u:p@host.invalid/api", "https://host.invalid:65536/api", "https://host.invalid/api?x=%0a"] {
            let row = try #require(SpaceLinkedSpace.rows(for: [.init(endpoint: URL(string: value)!, website: website)]).first)
            #expect(row.target == nil)
            #expect(row.endpoint?.value == value)
            #expect(row.website?.destination == website)
        }
    }

    @Test func relativeURLsWithBasesCannotBypassActionValidation() throws {
        let relative = try #require(URL(string: "api", relativeTo: website))
        #expect(SpaceDetailLink.projects(for: [relative]).first?.destination == nil)
        let row = try #require(SpaceLinkedSpace.rows(for: [.init(endpoint: relative, website: relative)]).first)
        #expect(row.target == nil)
        #expect(row.website?.destination == nil)
    }

    @Test func localHTTPAndPortEndpointsRetainTheExistingContract() throws {
        let local = try #require(URL(string: "http://localhost:8080/api?space=one"))
        let row = try #require(SpaceLinkedSpace.rows(for: [.init(endpoint: local, website: nil)]).first)
        #expect(row.target?.endpoint == local)
        #expect(SpaceDetailLink.projects(for: [local]).first?.destination == local)
    }

    @Test func linkedReadCannotPersistSelectionSubscriptionsOrReloadPrimaryWidgets() async throws {
        let f = ObservationFixture(proxy: false); defer { f.close() }
        let primary = URL(string: "https://primary.invalid/api")!
        f.defaults.set(primary.absoluteString, forKey: "spaceEndpoint")
        f.defaults.set(["woodworking"], forKey: "mainframePushRoomIDs")
        let navigation = SpaceNavigation { url in
            StatusStore(service: f.responses.service(proxy: false), defaults: f.defaults,
                reloadWidgets: { f.reloads += 1 }, waitForExpiry: { _ in try await f.expiry.sleep() },
                now: { f.responses.clock.date }, selection: .temporary(url))
        }
        defer { navigation.close() }
        let row = try #require(SpaceLinkedSpace.rows(for: [.init(endpoint: endpoint, website: website)]).first)
        navigation.open(try #require(row.target))
        let store = try #require(navigation.destination?.store)
        #expect(f.responses.requests.isEmpty)
        #expect(store.status == .unknown)
        await store.refresh()
        #expect(f.responses.requests == [endpoint])
        #expect(store.status == .open)
        #expect(f.defaults.string(forKey: "spaceEndpoint") == primary.absoluteString)
        #expect(f.defaults.stringArray(forKey: "mainframePushRoomIDs") == ["woodworking"])
        #expect(f.reloads == 0)
        navigation.close()
        #expect(navigation.destination == nil)
    }

    @Test func failedLinkedReadDoesNotReplaceTheSourceSpaceOrItsObservation() async throws {
        let f = ObservationFixture(); defer { f.close() }
        await f.store.refresh()
        let original = f.store.info?.name
        let observation = f.store.observationTiming?.observedAt
        let navigation = SpaceNavigation { url in
            StatusStore(service: f.responses.service(proxy: false), defaults: f.defaults,
                selection: .temporary(url))
        }
        defer { navigation.close() }
        let row = try #require(SpaceLinkedSpace.rows(for: [.init(endpoint: endpoint, website: nil)]).first)
        f.responses.failSpace = true
        navigation.open(try #require(row.target))
        let store = try #require(navigation.destination?.store)
        await store.refresh()
        #expect(store.lastError != nil)
        #expect(store.info == nil)
        #expect(store.status == .unknown)
        #expect(f.store.info?.name == original)
        #expect(f.store.observationTiming?.observedAt == observation)
        #expect(f.store.status == .open)
    }
}
