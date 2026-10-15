import Foundation
import Observation
import MapKit

@MainActor @Observable
final class TripStore {
    private(set) var me: TripMember
    private(set) var myPicks: [PlacePick] = []
    private(set) var remoteStates: [UUID: SharedTripState] = [:]
    let sharing: NearbyTripSession

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
