import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var store: ProductStore

    var body: some View {
        VStack(spacing: 0) {
            headerView
            tabButtons
            contentView
        }
        .background(Color(uiColor: .systemGray6))
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "scale.3d")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Color.indigo)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Text("ProductCompare")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(.primary)

                Spacer()

                Text("Live")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.indigo)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.indigo.opacity(0.1), in: Capsule())
            }
            .padding(.horizontal)
            .padding(.top, 12)

            Divider()
        }
        .background(.white)
    }

    private var tabButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ProductStore.Tab.allCases, id: \.self) { tab in
                    Button {
                        store.selectedTab = tab
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tabIcon(for: tab))
                            Text(tab.rawValue)
                                .lineLimit(1)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(store.selectedTab == tab ? .white : Color.primary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 15)
                        .background(store.selectedTab == tab ? Color.indigo : Color(uiColor: .systemGray6), in: Capsule())
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(.white)
    }

    @ViewBuilder private var contentView: some View {
        switch store.selectedTab {
        case .catalog: CatalogView()
        case .compare: CompareView()
        case .smartAdd: SmartAddView()
        case .reviews: ReviewsView()
        case .backup: DataBackupView()
        }
    }

    private func tabIcon(for tab: ProductStore.Tab) -> String {
        switch tab {
        case .catalog: "square.grid.2x2.fill"
        case .compare: "arrow.left.arrow.right"
        case .smartAdd: "sparkles"
        case .reviews: "doc.text"
        case .backup: "archivebox"
        }
    }
}
