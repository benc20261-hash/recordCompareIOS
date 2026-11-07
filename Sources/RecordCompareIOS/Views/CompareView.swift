import SwiftUI

struct CompareView: View {
    @EnvironmentObject private var store: ProductStore
    @State private var sortByName = false

    private var selectedProducts: [Product] {
        let selected = store.products.filter { store.comparedProductIDs.contains($0.id) }
        return sortByName
            ? selected.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            : selected
    }

    private var comparisonSpecifications: [String] {
        var names: [String] = []
        for product in selectedProducts {
            let productSpecs = store.specifications
                .filter { $0.productId == product.id || $0.productTitle == product.name }
                .sorted { $0.order < $1.order }
            for specification in productSpecs where !names.contains(where: { $0.caseInsensitiveCompare(specification.specName) == .orderedSame }) {
                names.append(specification.specName)
            }
        }
        return names
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            productPicker

            if selectedProducts.isEmpty {
                ContentUnavailableView(
                    "No products selected",
                    systemImage: "arrow.left.arrow.right",
                    description: Text("Select products above to compare their specifications.")
                )
            } else {
                comparisonMatrix
            }
        }
        .background(Color(uiColor: .systemGray6))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Compare Products")
                    .font(.system(size: 23, weight: .bold))
                Text("Compare up to 5 products")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button {
                    sortByName.toggle()
                } label: {
                    Label(sortByName ? "Keep selection order" : "Sort by product name", systemImage: "arrow.up.arrow.down")
                }
                Button(role: .destructive) {
                    store.comparedProductIDs.removeAll()
                } label: {
                    Label("Clear comparison", systemImage: "trash")
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 18, weight: .semibold))
                    .padding(11)
                    .background(.white, in: Circle())
            }
            .accessibilityLabel("Comparison options")
        }
        .padding(16)
        .background(.white)
    }

    private var productPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(store.products) { product in
                    let isSelected = store.comparedProductIDs.contains(product.id)
                    Button {
                        store.toggleCompare(product.id)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                            Text(product.name).lineLimit(1)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(isSelected ? Color.indigo : Color.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isSelected && store.comparedProductIDs.count >= 5)
                    .opacity(!isSelected && store.comparedProductIDs.count >= 5 ? 0.5 : 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGray6))
    }

    private var comparisonMatrix: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    Text("Specification")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 132, alignment: .leading)
                        .padding(10)
                        .background(Color(uiColor: .systemGray5))

                    ForEach(selectedProducts) { product in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(product.brand.uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.indigo)
                            Text(product.name)
                                .font(.system(size: 15, weight: .bold))
                                .lineLimit(3)
                            Button(role: .destructive) {
                                store.comparedProductIDs.remove(product.id)
                            } label: {
                                Label("Remove", systemImage: "xmark.circle")
                                    .font(.caption)
                            }
                        }
                        .frame(width: 176, alignment: .leading)
                        .padding(10)
                        .background(Color(uiColor: .systemGray5))
                    }
                }

                ForEach(comparisonSpecifications, id: \.self) { name in
                    HStack(alignment: .top, spacing: 0) {
                        Text(name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 132, alignment: .leading)
                            .padding(10)

                        ForEach(selectedProducts) { product in
                            let value = store.specifications.first {
                                ($0.productId == product.id || $0.productTitle == product.name) &&
                                $0.specName.caseInsensitiveCompare(name) == .orderedSame
                            }
                            Text(value.map { [$0.details, $0.unit ?? ""].filter { !$0.isEmpty }.joined(separator: " ") } ?? "—")
                                .font(.system(size: 13))
                                .frame(width: 176, alignment: .leading)
                                .padding(10)
                        }
                    }
                    .background(.white)
                    Rectangle()
                        .fill(Color.gray.opacity(0.18))
                        .frame(height: 1)
                }
            }
            .padding(12)
        }
        .background(.white)
    }
}
