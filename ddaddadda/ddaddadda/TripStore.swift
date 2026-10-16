import Foundation
import Observation
import MapKit

@MainActor @Observable
final class TripStore {
    private(set) var me: TripMember
    private(set) var myPicks: [PlacePick] = []
    private(set) var remoteStates: [UUID: SharedTripState] = [:]
    let sharing: NearbyTripSession
    @ObservationIgnored private var travelTimeCache: [RouteKey: TimeInterval] = [:]

    init() {
        let storedID = UserDefaults.standard.string(forKey: "memberID").flatMap(UUID.init) ?? UUID()
        UserDefaults.standard.set(storedID.uuidString, forKey: "memberID")
        let defaultName = UserDefaults.standard.string(forKey: "memberName") ?? "나"
        me = TripMember(id: storedID, name: defaultName, colorIndex: Int(storedID.hashValue.magnitude % 4), isConfirmed: false)
        sharing = NearbyTripSession(displayName: defaultName)
        sharing.onStateReceived = { [weak self] state in Task { @MainActor in self?.receive(state) } }
    }

    var allPicks: [PlacePick] { myPicks + remoteStates.values.flatMap(\.picks) }
    var members: [TripMember] { [me] + remoteStates.values.map(\.member).sorted { $0.name < $1.name } }
    var confirmedCount: Int { members.filter(\.isConfirmed).count }

    func add(_ item: MKMapItem) -> Bool {
        guard myPicks.count < 6, !hasPlace(item) else { return false }
        myPicks.append(PlacePick(item: item, owner: me)); publish(); return true
    }
    func remove(_ pick: PlacePick) { myPicks.removeAll { $0.id == pick.id }; me.isConfirmed = false; publish() }
    func hasPlace(_ item: MKMapItem) -> Bool {
        let c = item.placemark.coordinate
        return myPicks.contains { $0.name == item.name && abs($0.latitude - c.latitude) < 0.0001 && abs($0.longitude - c.longitude) < 0.0001 }
    }
    func confirmMine() { me.isConfirmed = true; publish() }
    func rename(_ name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !cleaned.isEmpty else { return }
        me.name = cleaned; UserDefaults.standard.set(cleaned, forKey: "memberName"); sharing.updateDisplayName(cleaned); publish()
    }
    func startSharing() { sharing.start(); publish() }
    func stopSharing() { sharing.stop() }

    func clusters(maxDistanceMeters: Double = 5_500) -> [PlaceCluster] {
        var remaining = allPicks; var result: [PlaceCluster] = []; var index = 1
        while let seed = remaining.first {
            var group = [seed]; remaining.removeFirst(); var changed = true
            while changed {
                changed = false
                let center = Self.center(of: group); let point = CLLocation(latitude: center.latitude, longitude: center.longitude)
                if let candidate = remaining.first(where: { point.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <= maxDistanceMeters }) {
                    group.append(candidate); remaining.removeAll { $0.id == candidate.id }; changed = true
                }
            }
            let center = Self.center(of: group)
            result.append(.init(name: Self.regionName(for: group, index: index), picks: group, center: center)); index += 1
        }
        return result.sorted { $0.picks.count > $1.picks.count }
    }

    func clusters(mode: TravelMode, maxTravelMinutes: Int) async -> [PlaceCluster] {
        var remaining = allPicks
        var result: [PlaceCluster] = []
        var index = 1
        let limit = TimeInterval(maxTravelMinutes * 60)

        while let seed = remaining.first {
            var group = [seed]
            remaining.removeFirst()
            var changed = true
            while changed {
                changed = false
                for candidate in remaining {
                    guard let nearest = group.min(by: { straightDistance($0, candidate) < straightDistance($1, candidate) }) else { continue }
                    if let travelTime = await expectedTravelTime(from: nearest, to: candidate, mode: mode), travelTime <= limit {
                        group.append(candidate)
                        remaining.removeAll { $0.id == candidate.id }
                        changed = true
                        break
                    }
                }
            }
            result.append(.init(name: Self.regionName(for: group, index: index), picks: group, center: Self.center(of: group)))
            index += 1
        }
        return result.sorted { $0.picks.count > $1.picks.count }
    }

    func preferenceProfiles() -> [PreferenceProfile] {
        members.map { member in
            let picks = allPicks.filter { $0.ownerID == member.id }
            let counts = Dictionary(grouping: picks, by: \.category).mapValues(\.count)
            let ranked = counts.keys.sorted {
                if counts[$0, default: 0] == counts[$1, default: 0] { return $0.title < $1.title }
                return counts[$0, default: 0] > counts[$1, default: 0]
            }
            return PreferenceProfile(member: member, categories: ranked)
        }
    }

    func groupingProposals() -> [GroupingProposal] {
        proposals(for: clusters())
    }

    func groupingProposals(mode: TravelMode, maxTravelMinutes: Int) async -> [GroupingProposal] {
        proposals(for: await clusters(mode: mode, maxTravelMinutes: maxTravelMinutes))
    }

    private func proposals(for clusters: [PlaceCluster]) -> [GroupingProposal] {
        clusters.map { cluster in
            let activeMembers = cluster.members
            let categoriesByMember = Dictionary(uniqueKeysWithValues: activeMembers.map { member in
                (member.id, Set(cluster.picks.filter { $0.ownerID == member.id }.map(\.category)))
            })
            var unassigned = activeMembers
            var groups: [ActivityGroup] = []
            var groupIndex = 0

            while let seed = unassigned.first {
                unassigned.removeFirst()
                var grouped = [seed]
                let seedCategories = categoriesByMember[seed.id, default: []]
                let companions = unassigned.filter { member in
                    !seedCategories.intersection(categoriesByMember[member.id, default: []]).isEmpty
                }
                grouped.append(contentsOf: companions)
                unassigned.removeAll { candidate in companions.contains(where: { $0.id == candidate.id }) }
                let memberIDs = Set(grouped.map(\.id))
                let picks = cluster.picks.filter { memberIDs.contains($0.ownerID) }
                let tastes = Array(Set(picks.map(\.category))).map(\.title).sorted().joined(separator: ", ")
                groups.append(ActivityGroup(
                    members: grouped,
                    picks: picks,
                    label: "그룹 \(String(UnicodeScalar(65 + groupIndex)!))",
                    reason: grouped.count > 1 ? "\(tastes) 취향이 겹쳐 함께 즐기기 좋아요." : "\(tastes) 취향을 충분히 즐기도록 별도 그룹으로 제안해요."
                ))
                groupIndex += 1
            }

            let activeIDs = Set(activeMembers.map(\.id))
            for member in members where !activeIDs.contains(member.id) {
                groups.append(ActivityGroup(
                    members: [member], picks: [], label: "자유 선택",
                    reason: "이 지역에 저장한 장소가 없어요. 근처 자유시간을 갖거나 다른 그룹에 합류할지 본인에게 확인해야 해요."
                ))
            }
            return GroupingProposal(cluster: cluster, groups: groups)
        }
    }

    private func expectedTravelTime(from start: PlacePick, to end: PlacePick, mode: TravelMode) async -> TimeInterval? {
        let key = RouteKey(start: start.id, end: end.id, mode: mode)
        if let cached = travelTimeCache[key] { return cached }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end.coordinate))
        request.transportType = mode.transportType
        request.requestsAlternateRoutes = false
        do {
            let response = try await MKDirections(request: request).calculate()
            guard let seconds = response.routes.first?.expectedTravelTime else { return nil }
            travelTimeCache[key] = seconds
            travelTimeCache[RouteKey(start: end.id, end: start.id, mode: mode)] = seconds
            return seconds
        } catch {
            return nil
        }
    }

    private func straightDistance(_ first: PlacePick, _ second: PlacePick) -> CLLocationDistance {
        CLLocation(latitude: first.latitude, longitude: first.longitude)
            .distance(from: CLLocation(latitude: second.latitude, longitude: second.longitude))
    }

    private func publish() { sharing.send(.init(member: me, picks: myPicks)) }
    private func receive(_ state: SharedTripState) { guard state.member.id != me.id else { return }; remoteStates[state.member.id] = state }
    private static func center(of picks: [PlacePick]) -> CLLocationCoordinate2D {
        .init(latitude: picks.map(\.latitude).reduce(0, +) / Double(picks.count), longitude: picks.map(\.longitude).reduce(0, +) / Double(picks.count))
    }
    private static func regionName(for picks: [PlacePick], index: Int) -> String {
        let words = picks.flatMap { $0.address.split(separator: " ").map(String.init) }
        if let common = Dictionary(grouping: words, by: { $0 }).max(by: { $0.value.count < $1.value.count }), common.value.count > 1 { return "\(common.key)권" }
        return "지역 \(index)"
    }
}

private struct RouteKey: Hashable {
    let start: UUID
    let end: UUID
    let mode: TravelMode
}
