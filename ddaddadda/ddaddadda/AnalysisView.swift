import SwiftUI
import MapKit

struct AnalysisView: View {
    @Bindable var store: TripStore
    @Environment(\.dismiss) private var dismiss

    private var proposals: [GroupingProposal] { store.groupingProposals() }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    intro
                    preferenceSection
                    if store.members.count == 1 { waitingCard }
                    ForEach(Array(proposals.enumerated()), id: \.element.id) { index, proposal in
                        proposalCard(proposal, number: index + 1)
                    }
                    alternatives
                    limits
                    NavigationLink {
                        TimetableView(proposals: proposals)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("2박 3일 그룹 일정 확인").font(.headline)
                                Text("제안된 그룹 블록을 시간표에 넣어보세요").font(.caption).opacity(0.8)
                            }
                            Spacer(); Image(systemName: "arrow.right")
                        }
                        .padding(18).foregroundStyle(.white)
                        .background(TripTheme.indigo, in: RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                    .disabled(proposals.isEmpty)
                }.padding(18)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("취향 기반 그룹 제안")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("닫기") { dismiss() } } }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("거리보다 취향을 먼저 봤어요", systemImage: "heart.text.square.fill")
                .font(.title2.bold()).foregroundStyle(TripTheme.indigo)
            Text("먼저 가까운 장소를 지역으로 묶고, 그 안에서 맛집·카페·문화·자연 취향이 겹치는 사람들을 함께 묶었어요. 같은 지역이어도 원하는 경험이 다르면 잠시 나누어요.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 0) {
                metric("\(store.members.count)", "명")
                Divider().frame(height: 34)
                metric("\(store.allPicks.count)", "개 장소")
                Divider().frame(height: 34)
                metric("\(proposals.filter(\.isSplit).count)", "개 분리 제안")
            }
        }.cardStyle()
    }

    private var preferenceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("우리의 여행 취향").font(.headline)
            ForEach(store.preferenceProfiles()) { profile in
                HStack(spacing: 12) {
                    Circle().fill(profile.member.color).frame(width: 42, height: 42)
                        .overlay(Text(profile.member.initial).font(.headline).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.member.name).font(.subheadline.bold())
                        Text(profile.summary).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(profile.categories.prefix(3), id: \.self) { category in
                            Image(systemName: category.symbol).font(.caption).foregroundStyle(profile.member.color)
                        }
                    }
                }
            }
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
                Text("모두 '친구와 연결하기'를 켜면 취향 비교와 그룹 제안이 자동으로 새로고침돼요.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }.cardStyle()
    }

    private func proposalCard(_ proposal: GroupingProposal, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Text("\(number)").font(.headline).foregroundStyle(.white).frame(width: 34, height: 34).background(sectionColor(number), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(proposal.cluster.name).font(.headline)
                    Text(proposal.isSplit ? "취향 차이로 그룹 분리 제안" : "공통 취향으로 함께 방문 제안")
                        .font(.caption.bold()).foregroundStyle(proposal.isSplit ? TripTheme.coral : TripTheme.teal)
                }
                Spacer()
                Text(proposal.isSplit ? "1:\(max(proposal.groups.count - 1, 1)) 분리" : "함께")
                    .font(.caption.bold()).padding(.horizontal, 9).padding(.vertical, 6)
                    .background((proposal.isSplit ? TripTheme.coral : TripTheme.teal).opacity(0.12), in: Capsule())
            }

            Map(initialPosition: .region(MKCoordinateRegion(center: proposal.cluster.center, latitudinalMeters: 12_000, longitudinalMeters: 12_000)), interactionModes: []) {
                ForEach(proposal.cluster.picks) { pick in Marker(pick.name, systemImage: pick.category.symbol, coordinate: pick.coordinate).tint(pick.owner.color) }
            }.frame(height: 135).clipShape(RoundedRectangle(cornerRadius: 16))

            ForEach(Array(proposal.groups.enumerated()), id: \.element.id) { index, group in
                groupPanel(group, color: groupColor(index))
            }

            if proposal.isSplit {
                Label("분리하는 이유", systemImage: "checkmark.circle.fill").font(.subheadline.bold()).foregroundStyle(TripTheme.indigo)
                Text(splitReason(proposal)).font(.footnote).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 8) {
                Text("대안").font(.caption.bold()).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 4).background(Color.secondary, in: Capsule())
                Text("대기 부담이 없고 서로 취향을 경험해도 괜찮다면 세 명 모두 함께 방문할 수 있어요.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.cardStyle()
    }

    private func groupPanel(_ group: ActivityGroup, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(group.label).font(.caption.bold()).foregroundStyle(.white).padding(.horizontal, 9).padding(.vertical, 5).background(color, in: Capsule())
                Text(group.memberNames).font(.subheadline.bold())
                Spacer()
                Text(group.categorySummary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if group.picks.isEmpty {
                Label(group.title, systemImage: "person.crop.circle.badge.questionmark").font(.subheadline.weight(.semibold))
            } else {
                ForEach(group.picks) { pick in
                    HStack(spacing: 8) {
                        Image(systemName: pick.category.symbol).foregroundStyle(color).frame(width: 24)
                        Text(pick.name).font(.subheadline.weight(.semibold))
                        Spacer(); Text(pick.owner.name).font(.caption.bold()).foregroundStyle(pick.owner.color)
                    }
                }
            }
            Text(group.reason).font(.caption).foregroundStyle(.secondary)
        }.padding(14).background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private var alternatives: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("그룹 제안의 기준", systemImage: "arrow.triangle.branch").font(.headline)
            Text("지역 경계는 크게 벗어나지 않되, 같은 지역에서 무엇을 하고 싶은지가 다르면 나누었어요. 분리 자체가 목적이 아니므로 공통 취향이 있는 구간은 계속 함께 다녀요.")
                .font(.subheadline).foregroundStyle(.secondary)
        }.cardStyle()
    }

    private var limits: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("확정 전 서로 물어보세요", systemImage: "info.circle").font(.headline)
            Text("저장한 장소만으로는 혼자 다니고 싶은지, 다른 사람의 장소에 관심이 없는지, 얼마나 머물고 싶은지를 알 수 없어요. 표시된 '자유 선택'은 반드시 당사자에게 확인해 주세요.")
                .font(.footnote).foregroundStyle(.secondary)
        }.padding(.horizontal, 4)
    }

    private func splitReason(_ proposal: GroupingProposal) -> String {
        let descriptions = proposal.groups.filter { !$0.picks.isEmpty }.map { "\($0.memberNames)는 \($0.categorySummary)" }
        return descriptions.joined(separator: ", ") + "를 우선해요. 거리가 가까워서가 아니라 원하는 경험의 성격이 달라 나누는 제안이에요."
    }
    private func sectionColor(_ index: Int) -> Color { [TripTheme.indigo, TripTheme.teal, TripTheme.coral, TripTheme.amber][(index - 1) % 4] }
    private func groupColor(_ index: Int) -> Color { [TripTheme.indigo, TripTheme.teal, TripTheme.coral, TripTheme.amber][index % 4] }
}

extension View {
    func cardStyle() -> some View {
        padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
