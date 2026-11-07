import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var store: ProductStore

    var body: some View {
        VStack(spacing: 0) {
            headerView
            tabButtons
            contentView
        }
        .background(Color(UIColor.systemGray6))
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

                Capsule()
                    .frame(width: 52, height: 28)
                    .foregroundStyle(.blue.opacity(0.15))
                    .overlay(Text("Live").font(.system(size: 12, weight: .semibold)).foregroundStyle(.blue))
            }
            .padding(.horizontal)
            .padding(.top, 12)

            Divider()
        }
    }

    private var tabButtons: some View {
        HStack(spacing: 8) {
            ForEach(ProductStore.Tab.allCases, id: \ .self) { tab in
                Button {
                    store.selectedTab = tab
                } label: {
                    HStack {
                        Image(systemName: tabIcon(for: tab))
                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(store.selectedTab == tab ? .indigo : .primary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .background(store.selectedTab == tab ? Color.indigo.opacity(0.12) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(store.selectedTab == tab ? Color.indigo : Color.gray.opacity(0.35), lineWidth: 1)
                    )
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var contentView: some View {
        Group {
            switch store.selectedTab {
            case .catalog:
                CatalogView()
            case .compare:
                CompareView()
            case .smartAdd:
                SmartAddView()
            case .reviews:
                ReviewsView()
            case .backup:
                DataBackupView()
            }
        }
    }

    private func tabIcon(for tab: ProductStore.Tab) -> String {
        switch tab {
        case .catalog: return "square.grid.2x2.fill"
        case .compare: return "arrow.left.arrow.right"
        case .smartAdd: return "sparkles"
        case .reviews: return "doc.text"
        case .backup: return "archivebox"
        }
    }
}
