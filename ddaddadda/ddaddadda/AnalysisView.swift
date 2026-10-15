import SwiftUI
import MapKit

struct AnalysisView: View {
    @Bindable var store: TripStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCluster: UUID?

    private var clusters: [PlaceCluster] { store.clusters() }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    summary
                    if store.members.count == 1 { waitingCard }
                    ForEach(Array(clusters.enumerated()), id: \.element.id) { index, cluster in
                        clusterCard(cluster, number: index + 1)
                    }
                    comparison
                    limits
                }.padding(18)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("우리의 여행 그룹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("닫기") { dismiss() } } }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("각자의 꼭 가고 싶은 곳을\n최대한 지켜서 묶었어요")
                .font(.title2.bold())
            HStack(spacing: 0) {
                metric("\(store.members.count)", "명")
                Divider().frame(height: 34)
                metric("\(store.allPicks.count)", "개 장소")
                Divider().frame(height: 34)
                metric("\(clusters.count)", "개 지역")
            }
            Text("이동 효율보다 구성원별 핵심 방문 희망을 우선해 제안합니다.")
                .font(.footnote).foregroundStyle(.secondary)
        }.cardStyle()
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) { Text(value).font(.title2.bold()); Text(label).font(.caption).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity)
    }

    private var waitingCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.2.wave.2.fill").font(.title2).foregroundStyle(TripTheme.coral)
            VStack(alignment: .leading, spacing: 5) {
                Text("친구의 장소를 기다리고 있어요").font(.headline)
                Text("모두 '친구와 연결하기'를 켜면 이 화면에 지역별 그룹 제안이 자동으로 합쳐져요.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }.cardStyle()
    }

    private func clusterCard(_ cluster: PlaceCluster, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(number)").font(.headline).foregroundStyle(.white).frame(width: 34, height: 34).background(color(number), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(cluster.name).font(.headline)
                    Text("\(cluster.picks.count)개 장소 · \(cluster.members.count)명의 희망").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Map(initialPosition: .region(MKCoordinateRegion(center: cluster.center, latitudinalMeters: 12_000, longitudinalMeters: 12_000)), interactionModes: []) {
                ForEach(cluster.picks) { pick in Marker(pick.name, systemImage: pick.category.symbol, coordinate: pick.coordinate).tint(pick.owner.color) }
            }.frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 16))
            VStack(spacing: 10) {
                ForEach(cluster.picks) { pick in
                    HStack(spacing: 10) {
                        Image(systemName: pick.category.symbol).frame(width: 30, height: 30).background(pick.owner.color.opacity(0.14), in: Circle()).foregroundStyle(pick.owner.color)
                        VStack(alignment: .leading, spacing: 2) { Text(pick.name).font(.subheadline.weight(.semibold)); Text(pick.address).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        Spacer(); Text(pick.owner.name).font(.caption.bold()).foregroundStyle(pick.owner.color)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("제안 그룹", systemImage: "person.3.fill").font(.subheadline.bold())
                Text(groupSuggestion(cluster)).font(.subheadline)
                Text(groupReason(cluster)).font(.footnote).foregroundStyle(.secondary)
            }
        }.cardStyle()
    }

    private var comparison: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("다른 구성 가능성", systemImage: "arrow.triangle.branch").font(.headline)
            Text("모두 함께 다닌다면 서로가 저장한 모든 장소를 자연스럽게 알게 되는 장점이 있지만, 특정 사람의 핵심 경험이 짧아지거나 기다림이 생길 수 있어요.")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("그룹을 나누더라도 공통 관심사가 큰 지역은 함께, 취향이 뚜렷한 지역만 잠시 나누는 방식을 권해요.")
                .font(.subheadline).foregroundStyle(.secondary)
        }.cardStyle()
    }

    private var limits: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("판단의 한계", systemImage: "info.circle").font(.headline)
            Text("저장한 장소만으로는 각자의 동행 의사, 머무르고 싶은 시간, 이동 방식, 식사·예산 제약을 알 수 없어요. 제안을 확정하기 전에 '혼자 다녀도 괜찮은 지', '절대 놓칠 수 없는 한 곳은 어디인 지'를 서로 확인해 주세요.")
                .font(.footnote).foregroundStyle(.secondary)
        }.padding(.horizontal, 4)
    }

    private func groupSuggestion(_ cluster: PlaceCluster) -> String {
        let names = cluster.members.map(\.name).joined(separator: " · ")
        return cluster.members.count == store.members.count ? "\(names) — 모두 함께" : "\(names) — 이 지역에서 잠시 함께"
    }
    private func groupReason(_ cluster: PlaceCluster) -> String {
        let categories = Set(cluster.picks.map(\.category))
        if cluster.members.count > 1 && categories.count > 1 { return "서로 다른 취향의 장소가 가까이 있어, 함께 있으면서도 각자의 핵심 경험을 지킬 수 있는 구성입니다." }
        if cluster.members.count > 1 { return "여러 구성원이 이 지역에 장소를 저장해 공통 관심사가 확인됩니다." }
        return "\(cluster.members.first?.name ?? "구성원")의 핵심 희망이 모인 지역입니다. 다른 사람이 함께할지는 별도로 확인해 주세요."
    }
    private func color(_ index: Int) -> Color { [TripTheme.indigo, TripTheme.teal, TripTheme.coral, TripTheme.amber][(index - 1) % 4] }
}

private extension View {
    func cardStyle() -> some View { self.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous)) }
}
