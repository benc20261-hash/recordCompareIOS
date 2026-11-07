import SwiftUI

struct CatalogView: View {
    @EnvironmentObject var store: ProductStore

    var body: some View {
        VStack(spacing: 16) {
            filterBar

            ScrollView {
                VStack(spacing: 18) {
                    ForEach(store.filteredProducts) { product in
                        ProductCard(product: product)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.gray)
                TextField("Search products", text: $store.searchText)
                    .font(.system(size: 18))
                Button {
                    store.selectedTag = "All"
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
            .padding(14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal)

            HStack(spacing: 10) {
                ForEach(["All"] + store.allTags.prefix(8), id: \ .self) { tag in
                    let selected = (store.selectedTag ?? "All") == tag
                    Button {
                        store.selectedTag = tag
                    } label: {
                        Text(tag)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(selected ? .white : .primary)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity)
                            .background(selected ? Color.indigo : Color.gray.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct ProductCard: View {
    let product: Product

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(colors: [.gray.opacity(0.2), .gray.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 220)

                Text(product.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(14)
            }

            HStack {
                Text(product.brand)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.gray.opacity(0.12))
                    .clipShape(Capsule())

                Spacer()

                if product.tags.count > 0 {
                    ForEach(product.tags.prefix(2), id: \ .self) { tag in
                        Text(tag)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.indigo.opacity(0.12))
                            .foregroundStyle(.indigo)
                            .clipShape(Capsule())
                    }
                }
            }

            Text(product.overview)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Divider()

            HStack {
                Text("Specifications")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Compare") { }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
