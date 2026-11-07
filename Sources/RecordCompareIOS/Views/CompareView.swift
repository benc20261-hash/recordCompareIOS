import SwiftUI

struct CompareView: View {
    @EnvironmentObject var store: ProductStore
    @State private var sortByName = false

    private var comparedProducts: [Product] {
        let list = store.products.filter { store.comparedProductIDs.contains($0.id) }
        return sortByName ? list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } : list
    }

    private var specNames: [String] {
        var names: [String] = []
        for product in comparedProducts {
            for spec in store.specifications.filter({ $0.productId == product.id || $0.productTitle == product.name }).sorted(by: { $0.order < $1.order }) {
                if !names.contains(where: { $0.caseInsensitiveCompare(spec.specName) == .orderedSame }) { names.append(spec.specName) }
            }
        }
        return names
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Compare Products").font(.system(size: 23, weight: .bold))
                    Text("Select up to 5 products").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Sort selected by name") { sortByName.toggle() }
                    Button("Clear comparison", role: .destructive) { store.comparedProductIDs.removeAll() }
                } label: { Image(systemName: "line.3.horizontal.decrease").font(.system(size: 18, weight: .semibold)).padding(11).background(Color(uiColor: .systemGray6), in: Circle()) }
            }
            .padding(16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.products) { product in
                        let chosen = store.comparedProductIDs.contains(product.id)
                        Button {
                            if chosen { store.comparedProductIDs.remove(product.id) }
                            else if store.comparedProductIDs.count < 5 { store.comparedProductIDs.insert(product.id) }
                        } label: {
                            HStack(spacing: 7) { Image(systemName: chosen ? "checkmark.circle.fill" : "plus.circle"); Text(product.name).lineLimit(1) }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(chosen ? .white : Color.primary)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(chosen ? Color.indigo : Color(uiColor: .systemGray6), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!chosen && store.comparedProductIDs.count >= 5)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 14)
            }
            if comparedProducts.isEmpty {
                ContentUnavailableView("No products selected", systemImage: "arrow.left.arrow.right", description: Text("Choose products above to compare their specifications."))
            } else {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: 0) {
                            Text("Specification").fontWeight(.bold).frame(width: 135, alignment: .leading).padding(10).background(Color(uiColor: .systemGray6))
                            ForEach(comparedProducts) { product in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(product.brand.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.indigo)
                                    Text(product.name).font(.system(size: 15, weight: .bold)).lineLimit(3)
                                    Button("Remove") { store.comparedProductIDs.remove(product.id) }.font(.caption).tint(.red)
                                }
                                .frame(width: 185, alignment: .leading).padding(10).background(Color(uiColor: .systemGray6))
                            }
                        }
                        ForEach(specNames, id: \.self) { name in
                            HStack(alignment: .top, spacing: 0) {
                                Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).frame(width: 135, alignment: .leading).padding(10)
                                ForEach(comparedProducts) { product in
                                    let spec = store.specifications.first { ($0.productId == product.id || $0.productTitle == product.name) && $0.specName.caseInsensitiveCompare(name) == .orderedSame }
                                    Text(spec.map { [$0.details, $0.unit ?? ""].filter { !$0.isEmpty }.joined(separator: " ") } ?? "—")
                                        .font(.system(size: 13)).frame(width: 185, alignment: .leading).padding(10)
                                }
                            }
                            Divider()
                        }
                    }
                    .padding(12)
                }
            }
            Spacer(minLength: 0)
        }
        .background(.white)
    }
}
