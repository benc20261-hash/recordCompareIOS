import SwiftUI

struct CatalogView: View {
    @EnvironmentObject var store: ProductStore

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(store.filteredProducts) { product in
                        ProductCard(product: product)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .background(Color(uiColor: .systemGray6))
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Filter products by product", systemImage: "tag")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.indigo)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search products", text: $store.searchText)
                if !store.searchText.isEmpty {
                    Button { store.searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                }
            }
            .padding(12)
            .background(Color(uiColor: .systemGray6), in: RoundedRectangle(cornerRadius: 12))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    tagButton("All", count: store.products.count)
                    ForEach(store.allTags, id: \.self) { tag in tagButton(tag) }
                }
            }
        }
        .padding(16)
        .background(.white)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.gray.opacity(0.12)).frame(height: 1) }
    }

    private func tagButton(_ tag: String, count: Int? = nil) -> some View {
        let selected = (store.selectedTag ?? "All") == tag
        return Button { store.selectedTag = tag } label: {
            HStack(spacing: 6) {
                if selected { Image(systemName: "checkmark") }
                Text(tag)
                if let count { Text("(\(count))").foregroundStyle(selected ? .white.opacity(0.75) : .secondary) }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(selected ? .white : Color.primary)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(selected ? Color.indigo : Color(uiColor: .systemGray6), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct ProductCard: View {
    @EnvironmentObject var store: ProductStore
    let product: Product

    private var productSpecs: [Specification] {
        store.specifications.filter { $0.productId == product.id || $0.productTitle == product.name }.sorted { $0.order < $1.order }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(product.brand.isEmpty ? "Other" : product.brand.uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color(uiColor: .darkGray), in: RoundedRectangle(cornerRadius: 10))
                Spacer()
                Button {
                    store.toggleCompare(product.id)
                    store.selectedTab = .compare
                } label: {
                    Label(store.comparedProductIDs.contains(product.id) ? "Added" : "Compare", systemImage: store.comparedProductIDs.contains(product.id) ? "checkmark" : "plus")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .tint(.indigo)
            }
            .padding(14)

            if let picture = product.pictures.first, let url = store.localURL(for: picture) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Rectangle().fill(Color(uiColor: .systemGray5)).overlay(ProgressView())
                }
                .frame(maxWidth: .infinity)
                .frame(height: 230)
                .clipped()
                .padding(.horizontal, 12)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [Color.indigo.opacity(0.12), Color.blue.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 180)
                    .overlay(Image(systemName: "shippingbox").font(.system(size: 44)).foregroundStyle(Color.indigo.opacity(0.4)))
                    .padding(.horizontal, 12)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack { ForEach(product.tags.prefix(4), id: \.self) { tag in Text(tag).font(.system(size: 13)).padding(.horizontal, 10).padding(.vertical, 6).background(Color(uiColor: .systemGray6), in: RoundedRectangle(cornerRadius: 8)) } }
                Text(product.name).font(.system(size: 23, weight: .bold))
                if !product.overview.isEmpty { Text(product.overview).font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(3) }
                if !productSpecs.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(productSpecs.prefix(5)) { spec in
                            HStack(alignment: .top) {
                                Text(spec.specName).foregroundStyle(.secondary)
                                Spacer(minLength: 12)
                                Text([spec.details, spec.unit ?? ""].filter { !$0.isEmpty }.joined(separator: " ")).fontWeight(.semibold).multilineTextAlignment(.trailing).lineLimit(2)
                            }
                            .font(.system(size: 14))
                            .padding(.vertical, 8)
                            if spec.id != productSpecs.prefix(5).last?.id { Divider() }
                        }
                    }
                    .padding(.horizontal, 12)
                    .background(Color(uiColor: .systemGray6).opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(16)
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.gray.opacity(0.15), lineWidth: 1))
    }
}
