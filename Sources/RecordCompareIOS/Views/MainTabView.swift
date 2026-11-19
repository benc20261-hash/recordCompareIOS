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
                ProductCompareMark(size: 32)

                Text("ProductCompare")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(Color(red: 15 / 255.0, green: 23 / 255.0, blue: 42 / 255.0))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .layoutPriority(1)

                Spacer()

                Text("Offline")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ProductCompareBrand.purple)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(ProductCompareBrand.purple.opacity(0.1), in: Capsule())
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

    private enum ProductCompareBrand {
        static let purple = Color(red: 79 / 255.0, green: 70 / 255.0, blue: 229 / 255.0)
    }

    private struct ProductCompareMark: View {
        let size: CGFloat

        var body: some View {
            Canvas { context, canvasSize in
                func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                    CGPoint(x: x * canvasSize.width, y: y * canvasSize.height)
                }

                var scale = Path()
                scale.move(to: point(0.5, 0.18))
                scale.addLine(to: point(0.5, 0.8))
                scale.move(to: point(0.28, 0.32))
                scale.addLine(to: point(0.72, 0.32))
                scale.move(to: point(0.32, 0.32))
                scale.addLine(to: point(0.38, 0.56))
                scale.move(to: point(0.68, 0.32))
                scale.addLine(to: point(0.62, 0.56))
                scale.move(to: point(0.34, 0.82))
                scale.addLine(to: point(0.66, 0.82))

                var leftPan = Path()
                leftPan.move(to: point(0.22, 0.56))
                leftPan.addLine(to: point(0.42, 0.56))
                leftPan.addLine(to: point(0.38, 0.67))
                leftPan.addLine(to: point(0.26, 0.67))
                leftPan.closeSubpath()

                var rightPan = Path()
                rightPan.move(to: point(0.58, 0.56))
                rightPan.addLine(to: point(0.78, 0.56))
                rightPan.addLine(to: point(0.74, 0.67))
                rightPan.addLine(to: point(0.62, 0.67))
                rightPan.closeSubpath()

                let style = StrokeStyle(
                    lineWidth: canvasSize.width * 0.065,
                    lineCap: .round,
                    lineJoin: .round
                )
                context.stroke(scale, with: .color(.white), style: style)
                context.stroke(leftPan, with: .color(.white), style: style)
                context.stroke(rightPan, with: .color(.white), style: style)
            }
            .frame(width: size, height: size)
                .background(ProductCompareBrand.purple)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}
