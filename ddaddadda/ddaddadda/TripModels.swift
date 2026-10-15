import SwiftUI
import MapKit

enum TripTheme {
    static let coral = Color(red: 0.96, green: 0.32, blue: 0.30)
    static let teal = Color(red: 0.08, green: 0.61, blue: 0.55)
    static let indigo = Color(red: 0.34, green: 0.29, blue: 0.82)
    static let amber = Color(red: 0.96, green: 0.60, blue: 0.12)
}

struct TripMember: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var colorIndex: Int
    var isConfirmed: Bool
    var initial: String { String(name.prefix(1)) }
    var color: Color { [TripTheme.coral, TripTheme.teal, TripTheme.indigo, TripTheme.amber][colorIndex % 4] }
}

enum PlaceCategory: String, Codable, CaseIterable {
    case food, cafe, culture, nature, shopping, other
    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .cafe: "cup.and.saucer.fill"
        case .culture: "building.columns.fill"
        case .nature: "leaf.fill"
        case .shopping: "bag.fill"
        case .other: "mappin"
        }
    }

    static func infer(from item: MKMapItem) -> PlaceCategory {
        let text = [item.name, item.pointOfInterestCategory?.rawValue].compactMap { $0 }.joined(separator: " ").lowercased()
        if text.contains("restaurant") || text.contains("food") || text.contains("횟집") || text.contains("식당") { return .food }
        if text.contains("cafe") || text.contains("bakery") || text.contains("카페") || text.contains("베이커리") { return .cafe }
        if text.contains("museum") || text.contains("미술관") || text.contains("박물관") { return .culture }
        if text.contains("beach") || text.contains("park") || text.contains("해수욕장") || text.contains("공원") { return .nature }
        if text.contains("store") || text.contains("shop") || text.contains("백화점") { return .shopping }
        return .other
    }
}

struct PlacePick: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let category: PlaceCategory
    let owner: TripMember
    var ownerID: UUID { owner.id }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    init(item: MKMapItem, owner: TripMember) {
        id = UUID(); name = item.name ?? "이름 없는 장소"; address = item.placemark.shortAddress
        latitude = item.placemark.coordinate.latitude; longitude = item.placemark.coordinate.longitude
        category = .infer(from: item); self.owner = owner
    }
}

struct SharedTripState: Codable { let member: TripMember; let picks: [PlacePick] }

struct PlaceCluster: Identifiable {
    let id = UUID(); let name: String; let picks: [PlacePick]; let center: CLLocationCoordinate2D
    var members: [TripMember] {
        var seen = Set<UUID>()
        return picks.compactMap { seen.insert($0.owner.id).inserted ? $0.owner : nil }
    }
}
