import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var store: ProductStore

    var body: some View {
        VStack(spacing: 0) {
            headerView
            TabView(selection: $store.selectedTab) {
                CatalogView()
                    .tabItem { Label("Catalog", systemImage: tabIcon(for: .catalog)) }
                    .tag(ProductStore.Tab.catalog)
                CompareView()
                    .tabItem { Label("Compare", systemImage: tabIcon(for: .compare)) }
                    .tag(ProductStore.Tab.compare)
                SmartAddView()
                    .tabItem { Label("Smart Add", systemImage: tabIcon(for: .smartAdd)) }
                    .tag(ProductStore.Tab.smartAdd)
                ReviewsView()
                    .tabItem { Label("Reviews", systemImage: tabIcon(for: .reviews)) }
                    .tag(ProductStore.Tab.reviews)
                DataBackupView()
                    .tabItem { Label("Backup", systemImage: tabIcon(for: .backup)) }
                    .tag(ProductStore.Tab.backup)
            }
            .toolbarBackground(.white, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .layoutPriority(1)

                Spacer()

                Text("Offline")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.indigo)
                    .fixedSize(horizontal: true, vertical: false)
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
