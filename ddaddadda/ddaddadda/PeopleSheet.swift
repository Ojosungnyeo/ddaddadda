import SwiftUI

struct PeopleSheet: View {
    @Bindable var store: TripStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("근처리 여행 공유", systemImage: "dot.radiowaves.left.and.right")
                            .font(.title2.bold())
                        Text("세 기기에서 동시에 켜면 핀이 하나의 지도에 실시간으로 모여요. 인터넷이 없어도 괜찮아요.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField("내 이름", text: $name).textFieldStyle(.roundedBorder)
                        Button("저장") { store.rename(name) }.buttonStyle(.bordered)
                    }
                    Button { store.sharing.isHosting ? store.stopSharing() : store.startSharing() } label: {
                        HStack {
                            Image(systemName: store.sharing.isHosting ? "stop.circle.fill" : "antenna.radiowaves.left.and.right")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.sharing.isHosting ? "공유 그만하기" : "친구와 연결하기").font(.headline)
                                Text(store.sharing.statusText).font(.caption).opacity(0.8)
                            }
                            Spacer(); Image(systemName: "chevron.right")
                        }.padding().foregroundStyle(.white)
                            .background(store.sharing.isHosting ? Color.secondary : TripTheme.coral, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("여행 구성원").font(.headline)
                        ForEach(store.members) { member in
                            HStack(spacing: 12) {
                                Circle().fill(member.color).frame(width: 38, height: 38)
                                    .overlay(Text(member.initial).font(.headline).foregroundStyle(.white))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name + (member.id == store.me.id ? " (나)" : "")).fontWeight(.semibold)
                                    Text("\(member.id == store.me.id ? store.myPicks.count : store.remoteStates[member.id]?.picks.count ?? 0)개 선택")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Label(member.isConfirmed ? "확정" : "선택 중", systemImage: member.isConfirmed ? "checkmark.circle.fill" : "ellipsis.circle")
                                    .font(.caption.weight(.semibold)).foregroundStyle(member.isConfirmed ? TripTheme.teal : .secondary)
                            }.padding(.vertical, 5)
                        }
                    }
                }.padding(20)
            }
            .navigationTitle("함께 고르기").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
            .onAppear { name = store.me.name }
        }
    }
}
