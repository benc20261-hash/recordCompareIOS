import SwiftUI
import PhotosUI
import UIKit
import WebKit

struct CatalogView: View {
    @EnvironmentObject var store: ProductStore
    @State private var selectedProduct: Product?
    @State private var showingNewProduct = false
    @State private var tableLayout = false
    @State private var filterScope: CatalogFilterScope = .all
    @State private var trayConfirmation: SelectionTrayConfirmation?

    private var filterOptions: [CatalogFilterOption] {
        let all = store.allTags.map { CatalogFilterOption(title: $0, scope: .tag) } +
            store.allBrands.map { CatalogFilterOption(title: $0, scope: .brand) } +
            store.products.map { CatalogFilterOption(title: $0.name, scope: .product) }
        let options = filterScope == .all ? all : all.filter { $0.scope == filterScope }
        var seen = Set<String>()
        return options
            .filter { seen.insert($0.title.lowercased()).inserted }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var activeFilterValue: String {
        if let tag = store.selectedTag, tag != "All" { return tag }
        return store.selectedBrand == "All" ? "All" : store.selectedBrand
    }

    private var visibleFilterOptions: [CatalogFilterOption] {
        let query = store.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return filterOptions }
        return filterOptions.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var selectedComparisonProducts: [Product] {
        store.comparedProductOrder.compactMap { id in
            store.products.first { $0.id == id }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                filterBar
                ForEach(store.filteredProducts) { product in
                    if tableLayout {
                        ProductTableRow(product: product) { selectedProduct = product }
                            .padding(.horizontal, 12)
                    } else {
                        ProductCard(product: product, onOpen: { selectedProduct = product })
                            .padding(.horizontal, 12)
                    }
                }
                if store.filteredProducts.isEmpty {
                    ContentUnavailableView.search(text: store.searchText)
                        .padding(.horizontal, 16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .pointerDragScrolling()
        }
        .background(Color(uiColor: .systemGray6))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !selectedComparisonProducts.isEmpty {
                selectionTray
            }
        }
        .confirmationDialog(
            trayConfirmation?.title ?? "",
            isPresented: Binding(
                get: { trayConfirmation != nil },
                set: { if !$0 { trayConfirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let trayConfirmation {
                Button(trayConfirmation.confirmationTitle, role: .destructive) {
                    switch trayConfirmation {
                    case .remove(let id, _):
                        store.removeComparedProduct(id)
                    case .clear:
                        store.clearComparison()
                    }
                    self.trayConfirmation = nil
                }
            }
            Button("Cancel", role: .cancel) {
                trayConfirmation = nil
            }
        } message: {
            if let trayConfirmation {
                Text(trayConfirmation.message)
            }
        }
        .sheet(item: $selectedProduct) { product in ProductDetailSheet(product: product) }
        .sheet(isPresented: $showingNewProduct) { ProductWorkspaceSheet() }
    }

    private var selectionTray: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Label("\(selectedComparisonProducts.count) Selected", systemImage: "arrow.left.arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1), in: Capsule())
                    .fixedSize()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(selectedComparisonProducts) { product in
                            HStack(spacing: 6) {
                                selectionThumbnail(product)
                                Text(product.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                    .foregroundStyle(.white)
                                Button {
                                    trayConfirmation = .remove(id: product.id, name: product.name)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .frame(width: 20, height: 24)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(product.name) from comparison")
                            }
                            .padding(.leading, 5)
                            .padding(.trailing, 3)
                            .padding(.vertical, 4)
                            .background(Color(red: 0.12, green: 0.16, blue: 0.23), in: Capsule())
                            .overlay(Capsule().stroke(Color(red: 0.2, green: 0.25, blue: 0.33), lineWidth: 1))
                        }
                    }
                }
                .pointerDragScrolling()
            }

            HStack(spacing: 8) {
                Button(role: .destructive) {
                    trayConfirmation = .clear(names: selectedComparisonProducts.map(\.name))
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.97, green: 0.44, blue: 0.45))
                        .frame(width: 38, height: 38)
                        .background(Color(red: 0.12, green: 0.16, blue: 0.23), in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear selected products")

                Spacer(minLength: 0)

                Button {
                    store.selectedTab = .smartAdd
                } label: {
                    Label("Smart Add", systemImage: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                }
                .buttonStyle(.bordered)
                .tint(Color(red: 0.99, green: 0.82, blue: 0.33))

                Button {
                    store.selectedTab = .compare
                } label: {
                    Label("Compare Now", systemImage: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(selectedComparisonProducts.count < 2)
            }
        }
        .padding(12)
        .background(
            Color(red: 0.08, green: 0.11, blue: 0.2),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.indigo.opacity(0.3), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func selectionThumbnail(_ product: Product) -> some View {
        if let picture = product.pictures.first,
           let url = store.localURL(for: picture),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            Image(systemName: "shippingbox")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Filter products by tag / brand / product", systemImage: "tag")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(Color.indigo)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    showingNewProduct = true
                } label: {
                    Image(systemName: "plus")
                        .font(.headline)
                        .padding(9)
                        .background(Color.indigo.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("Add product")
                Menu {
                    ForEach(ProductStore.CatalogSort.allCases) { sort in
                        Button {
                            store.catalogSort = sort
                        } label: {
                            if store.catalogSort == sort {
                                Label(sort.title, systemImage: "checkmark")
                            } else {
                                Text(sort.title)
                            }
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                        .labelStyle(.iconOnly)
                        .padding(9)
                        .background(Color(uiColor: .systemGray6), in: Circle())
                }
                .accessibilityLabel("Sort products")
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search tags, brands, or products", text: $store.searchText)
                if !store.searchText.isEmpty { Button { store.searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) } }
            }.padding(12).background(Color(uiColor: .systemGray6), in: RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 12) {
                Button {
                    store.selectedTab = .smartAdd
                } label: {
                    Label("Smart Add Product", systemImage: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .accessibilityIdentifier("catalog-smart-add")

                Picker("Catalog view", selection: $tableLayout) {
                    Text("Grid").tag(false)
                    Text("Table").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 142)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(CatalogFilterScope.allCases) { scope in
                        let selected = filterScope == scope
                        Button {
                            filterScope = scope
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: scope.symbol)
                                    .foregroundStyle(selected ? .white : scope.tint)
                                Text("\(scope.title) (\(scope.count(tags: store.allTags.count, brands: store.allBrands.count, products: store.products.count))")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(selected ? .white : .primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(selected ? Color.indigo : Color(uiColor: .systemGray6), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterOptionButton(title: "All", scope: .all)
                    ForEach(visibleFilterOptions) { option in
                        filterOptionButton(title: option.title, scope: option.scope)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).background(.white)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.gray.opacity(0.12)).frame(height: 1) }
    }

    private func filterOptionButton(title: String, scope: CatalogFilterScope) -> some View {
        let selected = activeFilterValue.caseInsensitiveCompare(title) == .orderedSame
        return Button {
            store.selectedTag = "All"
            store.selectedBrand = "All"
            guard title != "All" else { return }
            switch scope {
            case .brand:
                store.selectedBrand = title
            case .tag, .product, .all:
                store.selectedTag = title
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: scope.symbol)
                    .foregroundStyle(selected ? .white : scope.tint)
                Text(title)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(selected ? .white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selected ? Color.indigo : Color(uiColor: .systemGray6), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private enum SelectionTrayConfirmation {
    case remove(id: String, name: String)
    case clear(names: [String])

    var title: String {
        switch self {
        case .remove:
            return "Remove from Comparison?"
        case .clear:
            return "Clear Comparison?"
        }
    }

    var confirmationTitle: String {
        switch self {
        case .remove:
            return "Remove"
        case .clear:
            return "Clear all"
        }
    }

    var message: String {
        switch self {
        case .remove(_, let name):
            return "Are you sure you want to remove \"\(name)\" from comparison?"
        case .clear(let names):
            let products = names.map { "\"\($0)\"" }.joined(separator: ", ")
            let noun = names.count == 1 ? "product" : "products"
            return "Are you sure you want to remove all \(names.count) \(noun) (\(products)) from comparison?"
        }
    }
}

private enum CatalogFilterScope: String, CaseIterable, Identifiable {
    case all
    case tag
    case brand
    case product

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .tag: "Tags"
        case .brand: "Brands"
        case .product: "Product"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2.fill"
        case .tag: "tag.fill"
        case .brand: "building.2.fill"
        case .product: "shippingbox.fill"
        }
    }

    var tint: Color {
        switch self {
        case .all: .indigo
        case .tag: .blue
        case .brand: .orange
        case .product: .green
        }
    }

    func count(tags: Int, brands: Int, products: Int) -> Int {
        switch self {
        case .all: tags + brands + products
        case .tag: tags
        case .brand: brands
        case .product: products
        }
    }
}

private struct CatalogFilterOption: Identifiable {
    let title: String
    let scope: CatalogFilterScope
    var id: String { "\(scope.rawValue):\(title)" }
}

private struct ProductTableRow: View {
    @EnvironmentObject private var store: ProductStore
    let product: Product
    let onOpen: () -> Void

    private var specifications: [Specification] {
        store.specifications
            .filter { $0.productId == product.id || $0.productTitle == product.name }
            .sorted { $0.order < $1.order }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(product.brand.isEmpty ? "Other" : product.brand.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.indigo)
                Text(product.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(product.tags.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 128, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(specifications.prefix(2)) { specification in
                    HStack {
                        Text(specification.specName)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        RichHTMLText(
                            html: [specification.details, specification.unit ?? ""].filter { !$0.isEmpty }.joined(separator: " "),
                            fontSize: 13,
                            textColor: .label,
                            alignment: .right
                        )
                        .lineLimit(1)
                    }
                    .font(.caption)
                }
            }
            Spacer(minLength: 0)
            Button(action: onOpen) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.indigo)
            }
            .accessibilityLabel("View \(product.name)")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        .shadow(color: .black.opacity(0.045), radius: 5, x: 0, y: 2)
    }
}

struct ProductCard: View {
    @EnvironmentObject var store: ProductStore
    let product: Product
    var onOpen: () -> Void

    private var productSpecs: [Specification] {
        store.specifications
            .filter { $0.productId == product.id || $0.productTitle == product.name }
            .sorted { $0.order < $1.order }
    }

    private var reviewCount: Int {
        store.reviews.filter {
            $0.productIds.contains(product.id) ||
                $0.productTitles.contains {
                    $0.caseInsensitiveCompare(product.name) == .orderedSame
                }
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(product.brand.isEmpty ? "GENERIC" : product.brand.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color(uiColor: .darkGray), in: RoundedRectangle(cornerRadius: 7))
                Spacer()
                Button {
                    store.toggleCompare(product.id)
                } label: {
                    Label(
                        store.comparedProductIDs.contains(product.id) ? "Added" : "Compare",
                        systemImage: store.comparedProductIDs.contains(product.id) ? "checkmark" : "plus"
                    )
                    .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .tint(.indigo)
                .accessibilityLabel(store.comparedProductIDs.contains(product.id) ? "Remove from comparison" : "Compare \(product.name)")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 11) {
                if !product.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(product.tags.prefix(5), id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(Color(uiColor: .systemGray6), in: Capsule())
                            }
                        }
                    }
                }

                Button(action: onOpen) {
                    Text(product.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)

                Button(action: onOpen) {
                    productImage
                }
                .buttonStyle(.plain)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if !productSpecs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(productSpecs.prefix(3)) { spec in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 5) {
                                    Text(spec.specName)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                                    if let unit = spec.unit, !unit.isEmpty {
                                        Text(unit)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                    }
                                }
                                RichHTMLText(
                                    html: spec.details,
                                    fontSize: 13,
                                    textColor: .label,
                                    alignment: .left
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(9)
                            .background(Color(uiColor: .systemGray6).opacity(0.75), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 4) {
                    Text("\(reviewCount) \(reviewCount == 1 ? "review" : "reviews")")
                    Text("·")
                    Text("\(productSpecs.count) specs")
                    Spacer(minLength: 4)
                    Button(action: onOpen) {
                        HStack(spacing: 4) {
                            Text("Details")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Details for \(product.name)")
                }
                .font(.system(size: 11))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .padding(.top, 2)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.gray.opacity(0.24), lineWidth: 1))
        .shadow(color: .black.opacity(0.055), radius: 7, x: 0, y: 3)
    }

    @ViewBuilder
    private var productImage: some View {
        if let picture = product.pictures.first,
           let url = store.localURL(for: picture),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .background(Color(uiColor: .systemGray6))
                .accessibilityLabel("\(product.name) product photo")
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(
                    colors: [Color.indigo.opacity(0.12), Color.blue.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(height: 145)
                .overlay {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.indigo.opacity(0.4))
                }
                .accessibilityLabel("\(product.name) placeholder image")
        }
    }
}

struct ProductDetailSheet: View {
    @EnvironmentObject private var store: ProductStore
    @Environment(\.dismiss) private var dismiss
    let product: Product
    @State private var editingProduct = false
    @State private var editingSpecification: SpecificationEditorRequest?
    @State private var specificationToDelete: Specification?
    @State private var confirmingProductDelete = false
    @State private var photoViewer: ProductPhotoViewerRequest?
    @State private var selectedReview: ProductReviewRequest?

    init(product: Product) {
        self.product = product
    }

    private var currentProduct: Product {
        store.products.first(where: { $0.id == product.id }) ?? product
    }

    private var specifications: [Specification] {
        store.specifications
            .filter { $0.productId == product.id || $0.productTitle == currentProduct.name }
            .sorted { $0.order < $1.order }
    }

    private var linkedReviews: [Review] {
        store.reviews.filter {
            $0.productIds.contains(product.id) ||
                $0.productTitles.contains {
                    $0.caseInsensitiveCompare(currentProduct.name) == .orderedSame
                }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    actionBar
                    productGallery
                    productInformation
                    if !currentProduct.overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionHeading("Overview", icon: "text.alignleft")
                            RichHTMLText(html: currentProduct.overview, fontSize: 15, textColor: .label)
                        }
                        .detailCard()
                    }
                    specificationsSection
                    reviewsSection
                }
                .padding(16)
                .pointerDragScrolling()
            }
            .background(Color(uiColor: .systemGray6))
            .navigationTitle(currentProduct.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $editingProduct) {
                ProductWorkspaceSheet(product: currentProduct)
            }
            .sheet(item: $editingSpecification) { request in
                SpecificationEditorSheet(product: currentProduct, specification: request.specification)
            }
            .alert("Delete specification?", isPresented: Binding(
                get: { specificationToDelete != nil },
                set: { if !$0 { specificationToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let specificationToDelete {
                        store.deleteInlineSpec(
                            productID: currentProduct.id,
                            specName: specificationToDelete.specName
                        )
                    }
                    specificationToDelete = nil
                }
                Button("Cancel", role: .cancel) { specificationToDelete = nil }
            } message: {
                Text("Delete “\(specificationToDelete?.specName ?? "this specification")”?")
            }
            .confirmationDialog(
                "Delete \(currentProduct.name)?",
                isPresented: $confirmingProductDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Product", role: .destructive) {
                    store.deleteProduct(currentProduct.id)
                    dismiss()
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This also removes its specifications and clears its product links from reviews.")
            }
            .fullScreenCover(item: $photoViewer) { request in
                ProductPhotoViewer(images: request.images, initialIndex: request.initialIndex)
            }
            .sheet(item: $selectedReview) { request in
                ProductReviewActionsSheet(review: request.review, startEditing: request.startEditing)
            }
        }
        .presentationDetents([.large])
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                store.selectedTab = .reviews
                dismiss()
            } label: {
                Label("Review", systemImage: "text.bubble")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                editingProduct = true
            } label: {
                Label("Edit", systemImage: "pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                confirmingProductDelete = true
            } label: {
                Image(systemName: "trash")
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Delete product")
        }
    }

    private var productGallery: some View {
        VStack(spacing: 10) {
            if let picture = currentProduct.pictures.first,
               let url = store.localURL(for: picture),
               let image = UIImage(contentsOfFile: url.path) {
                Button {
                    presentImage(picture, from: currentProduct.pictures)
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 238)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View full-screen product photo \(picture.name)")
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.indigo.opacity(0.08))
                    .frame(height: 180)
                    .overlay {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 50))
                            .foregroundStyle(.indigo.opacity(0.45))
                    }
            }

            if currentProduct.pictures.count > 1 {
                attachmentStrip(currentProduct.pictures, height: 68)
            }
        }
        .padding(12)
        .detailCard()
    }

    private var productInformation: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Product Information", icon: "info.circle")
            Text(currentProduct.name)
                .font(.title2.bold())
                .foregroundStyle(.primary)
            Label(currentProduct.brand.isEmpty ? "No brand" : currentProduct.brand, systemImage: "tag")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.indigo)

            if !currentProduct.tags.isEmpty {
                FlexibleTagList(tags: currentProduct.tags)
            }

            HStack(spacing: 10) {
                Label("\(specifications.count) specifications", systemImage: "list.bullet.rectangle")
                Spacer(minLength: 0)
                Label("\(linkedReviews.count) reviews", systemImage: "text.bubble")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)

            if let createdTime = currentProduct.createdTime, !createdTime.isEmpty {
                Label("Created \(formattedDate(createdTime))", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .detailCard()
    }

    private var specificationsSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("FLEXIBLE DATA")
                        .font(.caption2.weight(.heavy))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                    Text("Specifications")
                        .font(.title3.bold())
                }
                Spacer()
                Text("\(specifications.count)")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color(uiColor: .systemGray6), in: Capsule())
            }

            ForEach(Array(specifications.enumerated()), id: \.element.id) { index, specification in
                specificationCard(specification, index: index)
            }

            Button {
                let newSpecification = Specification(
                    id: "spec_" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(17)),
                    specName: "",
                    details: "",
                    order: specifications.count + 1,
                    productId: currentProduct.id,
                    productTitle: currentProduct.name,
                    pictures: []
                )
                editingSpecification = SpecificationEditorRequest(specification: newSpecification)
            } label: {
                Label("Add specification", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
        }
        .detailCard()
    }

    private func specificationCard(_ specification: Specification, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("\(index + 1)")
                    .font(.caption.weight(.bold))
                    .frame(width: 25, height: 25)
                    .background(Color(uiColor: .systemGray5), in: RoundedRectangle(cornerRadius: 7))
                Text(specification.specName.isEmpty ? "Specification" : specification.specName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 2)
                Button {
                    editingSpecification = SpecificationEditorRequest(specification: specification)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Edit \(specification.specName)")
                Button(role: .destructive) {
                    specificationToDelete = specification
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete \(specification.specName)")
            }

            if specification.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("No details added")
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    RichHTMLText(
                        html: specification.details,
                        fontSize: 15,
                        textColor: .label,
                        alignment: .left
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                    if let unit = specification.unit, !unit.isEmpty {
                        Text(unit)
                            .font(.caption.monospaced().weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !specification.pictures.isEmpty {
                attachmentStrip(specification.pictures, height: 86)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                sectionHeading("Customer Reviews", icon: "text.bubble")
                Spacer()
                Text("\(linkedReviews.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            if linkedReviews.isEmpty {
                Text("No reviews linked to this product.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(linkedReviews) { review in
                    HStack(alignment: .top, spacing: 10) {
                        if let firstPicture = review.pictures.first,
                           let url = store.localURL(for: firstPicture),
                           let image = UIImage(contentsOfFile: url.path) {
                            Button {
                                presentImage(firstPicture, from: review.pictures)
                            } label: {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 9))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("View review photo \(firstPicture.name)")
                        } else {
                            Image(systemName: "text.bubble")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 64, height: 64)
                                .background(Color(uiColor: .systemGray5), in: RoundedRectangle(cornerRadius: 9))
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(review.title?.isEmpty == false ? review.title! : "Review #\(review.reviewNumber)")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 2)
                                Text(String(repeating: "★", count: max(0, min(5, review.rating ?? 0))))
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .fixedSize()
                            }
                            Text(review.authorName?.isEmpty == false ? review.authorName! : "Verified Reviewer")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if !review.body.isEmpty {
                                Text(reviewExcerpt(review.body))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if review.pictures.count > 1 {
                                attachmentStrip(
                                    Array(review.pictures.dropFirst()),
                                    height: 42,
                                    viewerAttachments: review.pictures
                                )
                            }
                            HStack(spacing: 7) {
                            Button {
                                selectedReview = ProductReviewRequest(review: review, startEditing: false)
                            } label: {
                                Label("View", systemImage: "eye")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button {
                                selectedReview = ProductReviewRequest(review: review, startEditing: true)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.indigo)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }

            if !linkedReviews.isEmpty {
                Button {
                    store.selectedTab = .reviews
                    dismiss()
                } label: {
                    Label("Open all reviews", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
        }
        .detailCard()
    }

    private func reviewExcerpt(_ html: String) -> String {
        let withBreaks = html
            .replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</(p|div|li|h[1-6])>"#, with: " ", options: .regularExpression)
        let text = withBreaks.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        return text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func attachmentStrip(
        _ attachments: [MediaAttachment],
        height: CGFloat,
        viewerAttachments: [MediaAttachment]? = nil
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    if let url = store.localURL(for: attachment),
                       let image = UIImage(contentsOfFile: url.path) {
                        Button {
                            presentImage(attachment, from: viewerAttachments ?? attachments)
                        } label: {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: height * 1.18, height: height)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open image \(attachment.name)")
                    }
                }
            }
        }
    }

    private func presentImage(_ attachment: MediaAttachment, from attachments: [MediaAttachment]) {
        let images = attachments.compactMap { item -> ProductPhotoViewerItem? in
            guard let url = store.localURL(for: item),
                  let image = UIImage(contentsOfFile: url.path) else { return nil }
            return ProductPhotoViewerItem(id: item.id, name: item.name, image: image)
        }
        guard let index = images.firstIndex(where: { $0.id == attachment.id }) else { return }
        photoViewer = ProductPhotoViewerRequest(images: images, initialIndex: index)
    }

    private func sectionHeading(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(.indigo)
    }

    private func formattedDate(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        var date = formatter.date(from: value)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = formatter.date(from: value)
        }
        return date?.formatted(date: .abbreviated, time: .omitted) ?? value
    }
}

private struct SpecificationEditorRequest: Identifiable {
    let id = UUID()
    let specification: Specification
}

private struct ProductReviewRequest: Identifiable {
    let id: String
    let review: Review
    let startEditing: Bool

    init(review: Review, startEditing: Bool) {
        id = review.id
        self.review = review
        self.startEditing = startEditing
    }
}

struct ProductPhotoViewerItem: Identifiable {
    let id: String
    let name: String
    let image: UIImage
}

struct ProductPhotoViewerRequest: Identifiable {
    let id = UUID()
    let images: [ProductPhotoViewerItem]
    let initialIndex: Int
}

struct ProductPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let images: [ProductPhotoViewerItem]
    @State private var selectedIndex: Int
    @State private var zoomPercent = 100

    init(images: [ProductPhotoViewerItem], initialIndex: Int) {
        self.images = images
        _selectedIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $selectedIndex) {
                ForEach(Array(images.enumerated()), id: \.element.id) { index, item in
                    ZoomableProductPhoto(
                        image: item.image,
                        zoomPercent: Binding(
                            get: { selectedIndex == index ? zoomPercent : 100 },
                            set: { if selectedIndex == index { zoomPercent = $0 } }
                        )
                    )
                        .tag(index)
                        .ignoresSafeArea()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
            .background(.black)

            HStack {
                Text(images.indices.contains(selectedIndex) ? images[selectedIndex].name : "")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                if images.count > 1 {
                    Text("\(selectedIndex + 1) / \(images.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                }
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white)
                        .padding(.leading, 10)
                }
                .accessibilityLabel("Close image viewer")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            VStack {
                Spacer()
                HStack(spacing: 18) {
                    Button {
                        zoomPercent = max(100, zoomPercent - 25)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .disabled(zoomPercent <= 100)
                    .accessibilityLabel("Zoom out")

                    Text("\(zoomPercent)%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .frame(minWidth: 48)
                        .accessibilityLabel("Zoom \(zoomPercent) percent")

                    Button {
                        zoomPercent = min(500, zoomPercent + 25)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .disabled(zoomPercent >= 500)
                    .accessibilityLabel("Zoom in")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.black.opacity(0.65), in: Capsule())
                .padding(.bottom, 28)
            }
        }
        .statusBarHidden()
        .onChange(of: selectedIndex) { _, _ in zoomPercent = 100 }
    }
}

struct ZoomableProductPhoto: UIViewRepresentable {
    let image: UIImage
    @Binding var zoomPercent: Int

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.bouncesZoom = true
        scrollView.panGestureRecognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)
        ]
        scrollView.backgroundColor = .black
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        imageView.addGestureRecognizer(doubleTap)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        guard let imageView = context.coordinator.imageView else { return }
        context.coordinator.zoomPercent = $zoomPercent
        imageView.image = image
        let requestedScale = min(5, max(1, CGFloat(zoomPercent) / 100))
        if abs(scrollView.zoomScale - requestedScale) > 0.01 {
            scrollView.setZoomScale(requestedScale, animated: true)
        }
        if scrollView.zoomScale == scrollView.minimumZoomScale {
            imageView.frame = scrollView.bounds
            scrollView.contentSize = scrollView.bounds.size
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        var zoomPercent: Binding<Int>?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            zoomPercent?.wrappedValue = Int((scrollView.zoomScale * 100).rounded())
            guard let imageView else { return }
            let horizontalInset = max(0, (scrollView.bounds.width - imageView.frame.width) / 2)
            let verticalInset = max(0, (scrollView.bounds.height - imageView.frame.height) / 2)
            scrollView.contentInset = UIEdgeInsets(
                top: verticalInset,
                left: horizontalInset,
                bottom: verticalInset,
                right: horizontalInset
            )
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view?.superview as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                scrollView.setZoomScale(2.5, animated: true)
            }
        }
    }
}

struct SpecificationEditorSheet: View {
    @EnvironmentObject private var store: ProductStore
    @Environment(\.dismiss) private var dismiss
    let product: Product
    let specification: Specification
    @State private var name: String
    @State private var details: String
    @State private var unit: String
    @State private var numericMode: Bool?
    @State private var pictures: [MediaAttachment]
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var editorCommand: String?
    @State private var showingLinkPrompt = false
    @State private var linkURL = ""
    @State private var errorText: String?
    @State private var photoViewer: ProductPhotoViewerRequest?

    private let quickUnits = ["g", "kg", "inch", "cm", "mm", "year", "month", "mAh", "Hz", "$", "GB"]

    init(product: Product, specification: Specification) {
        self.product = product
        self.specification = specification
        _name = State(initialValue: specification.specName)
        _details = State(initialValue: specification.details)
        _unit = State(initialValue: specification.unit ?? "")
        _numericMode = State(initialValue: specification.isNumeric)
        _pictures = State(initialValue: specification.pictures)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("SPECIFICATION")
                            .font(.caption.weight(.heavy))
                            .tracking(1)
                            .foregroundStyle(.secondary)
                        TextField("Specification name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.words)
                    }
                    .detailCard()

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Unit (optional)").font(.headline)
                            Spacer()
                            Button("Clear") { unit = "" }
                                .font(.caption.weight(.semibold))
                                .disabled(unit.isEmpty)
                        }
                        TextField("g, inch, cm, year, mAh...", text: $unit)
                            .textFieldStyle(.roundedBorder)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 7) {
                                Text("Quick unit")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(quickUnits, id: \.self) { quickUnit in
                                    Button(quickUnit) { unit = quickUnit }
                                        .font(.caption.weight(.semibold))
                                        .buttonStyle(.bordered)
                                        .tint(unit.caseInsensitiveCompare(quickUnit) == .orderedSame ? .indigo : .gray)
                                }
                            }
                        }
                    }
                    .detailCard()

                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("Specification details").font(.headline)
                            Spacer()
                            Text("Formatted text").font(.caption).foregroundStyle(.secondary)
                        }
                        SpecificationFormattingToolbar { command in
                            if command == "link" {
                                showingLinkPrompt = true
                            } else {
                                editorCommand = "\(command)|\(UUID().uuidString)"
                            }
                        }
                        SpecificationRichTextEditor(html: $details, command: editorCommand)
                            .frame(height: 190)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Text("Formatted text is saved with the product and rendered in Catalog and Compare.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .detailCard()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Comparison mode").font(.headline)
                        Picker("Comparison mode", selection: $numericMode) {
                            Text("Auto").tag(Optional<Bool>.none)
                            Text("Number (#)").tag(Optional(true))
                            Text("Text (Aa)").tag(Optional(false))
                        }
                        .pickerStyle(.segmented)
                        Text(modeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .detailCard()

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Specification pictures").font(.headline)
                            Spacer()
                            PhotosPicker(selection: $photoItems, maxSelectionCount: 12, matching: .images) {
                                Label("Add", systemImage: "photo.badge.plus")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                        if pictures.isEmpty {
                            Text("No pictures attached")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 9) {
                                    ForEach(pictures) { picture in
                                        VStack(spacing: 5) {
                                            if let url = store.localURL(for: picture),
                                               let image = UIImage(contentsOfFile: url.path) {
                                                Button {
                                                    presentImage(picture)
                                                } label: {
                                                    Image(uiImage: image)
                                                        .resizable()
                                                        .scaledToFill()
                                                        .frame(width: 88, height: 78)
                                                        .clipped()
                                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                                }
                                                .buttonStyle(.plain)
                                                .accessibilityLabel("Open specification photo \(picture.name)")
                                            }
                                            Button("Remove", role: .destructive) {
                                                pictures.removeAll { $0.id == picture.id }
                                            }
                                            .font(.caption2)
                                        }
                                    }
                                }
                                .pointerDragScrolling()
                            }
                        }
                        if let errorText {
                            Text(errorText).font(.footnote).foregroundStyle(.red)
                        }
                    }
                    .detailCard()
                }
                .padding(16)
                .pointerDragScrolling()
            }
            .background(Color(uiColor: .systemGray6))
            .navigationTitle(specification.specName.isEmpty ? "Add Specification" : "Edit Specification")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $photoViewer) { request in
                ProductPhotoViewer(images: request.images, initialIndex: request.initialIndex)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Insert link", isPresented: $showingLinkPrompt) {
                TextField("https://example.com", text: $linkURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Insert") {
                    guard let url = URL(string: linkURL),
                          ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") else {
                        errorText = "Enter a valid http, https, or mailto link."
                        return
                    }
                    editorCommand = "link|\(url.absoluteString)|\(UUID().uuidString)"
                }
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await importPhotos(items) }
            }
        }
    }

    private var modeDescription: String {
        switch numericMode {
        case true: "Use numeric parsing for comparison and best-value calculations."
        case false: "Treat this specification as descriptive text."
        case nil: "Automatically detect numeric values when comparing products."
        }
    }

    private func save() {
        var saved = specification
        saved.specName = name
        saved.details = details
        saved.unit = unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : unit
        saved.isNumeric = numericMode
        saved.pictures = pictures
        saved.productId = product.id
        saved.productTitle = product.name
        store.saveSpecification(saved)
        dismiss()
    }

    private func presentImage(_ attachment: MediaAttachment) {
        let images = pictures.compactMap { picture -> ProductPhotoViewerItem? in
            guard let url = store.localURL(for: picture),
                  let image = UIImage(contentsOfFile: url.path) else { return nil }
            return ProductPhotoViewerItem(id: picture.id, name: picture.name, image: image)
        }
        guard let index = images.firstIndex(where: { $0.id == attachment.id }) else { return }
        photoViewer = ProductPhotoViewerRequest(images: images, initialIndex: index)
    }

    @MainActor
    private func importPhotos(_ items: [PhotosPickerItem]) async {
        defer { photoItems = [] }
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw ProductDetailPhotoImportError.unreadableImage
                }
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                let attachment = try store.saveLocalPhoto(data, originalName: "spec_\(UUID().uuidString).\(ext)")
                pictures.append(attachment)
            } catch {
                errorText = "Could not import a selected photo: \(error.localizedDescription)"
            }
        }
    }
}

private struct SpecificationFormattingToolbar: View {
    let onCommand: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                tool("B", accessibility: "Bold", command: "bold", bold: true)
                tool("/", accessibility: "Italic", command: "italic", italic: true)
                tool("U", accessibility: "Underline", command: "underline", underline: true)
                tool("•", accessibility: "Bulleted list", command: "unordered")
                tool("1.", accessibility: "Numbered list", command: "ordered")
                tool("link", accessibility: "Insert link", command: "link", systemImage: "link")
                tool("clear", accessibility: "Clear formatting", command: "clear", systemImage: "textformat")
            }
        }
        .pointerDragScrolling()
    }

    private func tool(
        _ title: String,
        accessibility: String,
        command: String,
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        systemImage: String? = nil
    ) -> some View {
        Button {
            onCommand(command)
        } label: {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                } else {
                    Text(title)
                        .font(.system(size: 14, weight: bold ? .heavy : .semibold))
                        .italic(italic)
                        .underline(underline)
                }
            }
            .foregroundStyle(Color(uiColor: .label))
            .frame(width: 32, height: 30)
            .background(Color(uiColor: .systemGray6), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(uiColor: .systemGray4), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }
}

private struct SpecificationRichTextEditor: UIViewRepresentable {
    @Binding var html: String
    let command: String?

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "specificationContent")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .white
        webView.scrollView.backgroundColor = .white
        context.coordinator.parent = self
        context.coordinator.load(html, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.loadedHTML != html {
            context.coordinator.load(html, in: webView)
        }
        guard let command, command != context.coordinator.lastCommand else { return }
        context.coordinator.lastCommand = command
        let parts = command.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard let action = parts.first.map(String.init) else { return }
        let value = parts.count > 1 ? String(parts[1]) : ""
        guard let encodedValue = try? JSONEncoder().encode(value),
              let jsValue = String(data: encodedValue, encoding: .utf8) else { return }
        let script: String
        switch action {
        case "bold": script = "document.execCommand('bold')"
        case "italic": script = "document.execCommand('italic')"
        case "underline": script = "document.execCommand('underline')"
        case "unordered": script = "document.execCommand('insertUnorderedList')"
        case "ordered": script = "document.execCommand('insertOrderedList')"
        case "link": script = "document.execCommand('createLink', false, \(jsValue))"
        case "clear": script = "document.execCommand('removeFormat')"
        default: return
        }
        webView.evaluateJavaScript(script)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private static func document(_ html: String) -> String {
        let safe = html
            .replacingOccurrences(of: #"(?is)<script\b[^>]*>.*?</script>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</?script\b[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<(iframe|object|embed)\b[^>]*>.*?</\1>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\s+on[a-z]+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\s+srcdoc\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)"#, with: "", options: .regularExpression)
        let safeHTML = Self.removingUnsafeURLAttributes(from: safe)
        let content: String
        if let match = try? NSRegularExpression(pattern: #"(?is)<body[^>]*>(.*?)</body>"#)
            .firstMatch(in: safeHTML, range: NSRange(safeHTML.startIndex..., in: safeHTML)),
           let range = Range(match.range(at: 1), in: safeHTML) {
            content = String(safeHTML[range])
        } else {
            content = safeHTML
        }
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>body{font-family:-apple-system,sans-serif;font-size:16px;line-height:1.45;color:#172033;margin:8px;min-height:145px;outline:none;overflow-wrap:anywhere}ul,ol{padding-left:24px}a{color:#4f46e5}</style>
        </head><body contenteditable="true">\(content)<script>document.body.addEventListener('input',()=>window.webkit.messageHandlers.specificationContent.postMessage(document.body.innerHTML));</script></body></html>
        """
    }

    private static func removingUnsafeURLAttributes(from html: String) -> String {
        let pattern = #"(?i)\s+(href|src|xlink:href)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return html }
        let source = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return html }
        let result = NSMutableString(string: html)
        for match in matches.reversed() {
            let target = (2...4).compactMap { group -> String? in
                guard match.range(at: group).location != NSNotFound else { return nil }
                return source.substring(with: match.range(at: group))
            }.first ?? ""
            let decoded = RichHTMLText.decodeHTMLEntities(target)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let scheme = URL(string: decoded)?.scheme?.lowercased()
            if ["javascript", "vbscript", "data"].contains(scheme ?? "") {
                result.replaceCharacters(in: match.range, with: "")
            }
        }
        return result as String
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: SpecificationRichTextEditor?
        var loadedHTML: String?
        var lastCommand: String?

        func load(_ html: String, in webView: WKWebView) {
            loadedHTML = html
            webView.loadHTMLString(Self.document(html), baseURL: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "specificationContent", let value = message.body as? String else { return }
            loadedHTML = value
            parent?.html = value
        }

        private static func document(_ html: String) -> String {
            SpecificationRichTextEditor.document(html)
        }
    }
}

private enum ProductDetailPhotoImportError: LocalizedError {
    case unreadableImage

    var errorDescription: String? { "The selected photo could not be read." }
}

private struct ProductWorkspaceSheet: View {
    @EnvironmentObject private var store: ProductStore
    @Environment(\.dismiss) private var dismiss

    let product: Product?
    private let productID: String
    @State private var name: String
    @State private var brand: String
    @State private var brandSearchText = ""
    @State private var selectedTags: Set<String>
    @State private var tagSearchText = ""
    @State private var newTagText = ""
    @State private var overview: String
    @State private var overviewCommand: String?
    @State private var editorCommands: [String: String] = [:]
    @State private var showingLinkPrompt = false
    @State private var linkURL = ""
    @State private var linkTargetSpecID: String?
    @State private var pictures: [MediaAttachment]
    @State private var specifications: [Specification]
    @State private var expandedSpecificationIDs: Set<String> = []
    @State private var photoViewer: ProductPhotoViewerRequest?
    @State private var errorText: String?

    private let quickUnits = ["g", "kg", "inch", "cm", "mm", "year", "month", "mAh", "Hz", "$", "GB"]

    init(product: Product? = nil) {
        self.product = product
        let id = product?.id ?? "rec_" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(17))
        productID = id
        _name = State(initialValue: product?.name ?? "")
        _brand = State(initialValue: product?.brand ?? "")
        _selectedTags = State(initialValue: Set(product?.tags ?? []))
        _overview = State(initialValue: product?.overview ?? "")
        _pictures = State(initialValue: product?.pictures ?? [])
        if product == nil {
            _specifications = State(initialValue: [
                Specification(
                    id: "spec_" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(17)),
                    specName: "New specification",
                    details: "",
                    order: 1,
                    productId: id,
                    productTitle: "",
                    pictures: []
                )
            ])
        } else {
            _specifications = State(initialValue: [])
        }
    }

    private var filteredBrands: [String] {
        let query = brandSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let values = store.allBrands.filter {
            query.isEmpty || $0.localizedCaseInsensitiveContains(query)
        }
        return Array(values.prefix(12))
    }

    private var filteredTags: [String] {
        let query = tagSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.allTags.filter { tag in
            !selectedTags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) &&
                (query.isEmpty || tag.localizedCaseInsensitiveContains(query))
        }.prefix(16).map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    identitySection
                    overviewSection
                    productPhotosSection
                    specificationsSection
                    if let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .detailCard()
                    }
                }
                .padding(16)
                .pointerDragScrolling()
            }
            .background(Color(uiColor: .systemGray6))
            .navigationTitle(product == nil ? "Add Product" : "Edit Product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                guard let product else { return }
                specifications = store.specifications
                    .filter { $0.productId == product.id || $0.productTitle == product.name }
                    .sorted { $0.order < $1.order }
                renumberSpecifications()
            }
            .fullScreenCover(item: $photoViewer) { request in
                ProductPhotoViewer(images: request.images, initialIndex: request.initialIndex)
            }
            .alert("Insert link", isPresented: $showingLinkPrompt) {
                TextField("https://example.com", text: $linkURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Insert") {
                    guard let url = URL(string: linkURL),
                          ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") else {
                        errorText = "Enter a valid http, https, or mailto link."
                        return
                    }
                    let nonce = UUID().uuidString
                    if let linkTargetSpecID {
                        editorCommands[linkTargetSpecID] = "link|\(url.absoluteString)|\(nonce)"
                    } else {
                        overviewCommand = "link|\(url.absoluteString)|\(nonce)"
                    }
                    linkURL = ""
                    self.linkTargetSpecID = nil
                }
                Button("Cancel", role: .cancel) {
                    linkTargetSpecID = nil
                }
            }
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Product Identity", subtitle: "Name, brand, and tags")
            TextField("Product name", text: $name)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .accessibilityLabel("Product name")

            VStack(alignment: .leading, spacing: 8) {
                TextField("Search previous brands or enter a brand", text: $brandSearchText)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                    .accessibilityLabel("Search brands")
                TextField("Brand", text: $brand)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                if !filteredBrands.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(filteredBrands, id: \.self) { previousBrand in
                                Button(previousBrand) {
                                    brand = previousBrand
                                    brandSearchText = previousBrand
                                }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                                .tint(brand.caseInsensitiveCompare(previousBrand) == .orderedSame ? .indigo : .gray)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Search or add a tag", text: $tagSearchText)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .onSubmit(addSearchedTag)
                    Button("Add") { addSearchedTag() }
                        .buttonStyle(.borderedProminent)
                        .disabled(tagSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if !selectedTags.isEmpty {
                    FlexibleTagList(tags: selectedTags.sorted()) { tag in
                        selectedTags.remove(tag)
                    }
                    Button("Clear tags", role: .destructive) {
                        selectedTags.removeAll()
                    }
                    .font(.caption)
                }
                if !filteredTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(filteredTags, id: \.self) { tag in
                                Button {
                                    addTag(tag)
                                    tagSearchText = ""
                                } label: {
                                    Label(tag, systemImage: "plus")
                                        .font(.caption.weight(.medium))
                                }
                                .buttonStyle(.bordered)
                                .tint(.indigo)
                            }
                        }
                    }
                }
            }
        }
        .detailCard()
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle("Product Overview", subtitle: "Formatted HTML content")
            SpecificationFormattingToolbar { command in
                if command == "link" {
                    linkTargetSpecID = nil
                    showingLinkPrompt = true
                } else {
                    overviewCommand = "\(command)|\(UUID().uuidString)"
                }
            }
            SpecificationRichTextEditor(html: $overview, command: overviewCommand)
                .frame(height: 145)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .detailCard()
    }

    private var productPhotosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("Product Photos", subtitle: "Choose photos stored on this device")
                Spacer()
                LocalPhotoPickerButton(title: "Add", systemImage: "photo.badge.plus") { items in
                    Task { await importPhotos(items, for: nil) }
                }
            }
            if pictures.isEmpty {
                Text("No product photos added")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                attachmentEditorStrip(pictures, onOpen: presentImage) { picture in
                    pictures.removeAll { $0.id == picture.id }
                }
            }
        }
        .detailCard()
    }

    private var specificationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                sectionTitle("Specifications", subtitle: "\(specifications.count) ordered specifications")
                Spacer()
                Menu {
                    Button("Name A–Z") { sortSpecifications(ascending: true) }
                    Button("Name Z–A") { sortSpecifications(ascending: false) }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                        .font(.caption.weight(.semibold))
                }
            }

            ForEach(Array($specifications.enumerated()), id: \.element.id) { index, $specification in
                specificationEditorCard($specification, index: index)
            }

            Button(action: addSpecification) {
                Label("Add specification", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.bordered)
        }
        .detailCard()
    }

    private func specificationEditorCard(_ specification: Binding<Specification>, index: Int) -> some View {
        let specID = specification.wrappedValue.id
        return VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    toggleSpecification(specID)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: expandedSpecificationIDs.contains(specID) ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 22)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(specification.wrappedValue.specName.isEmpty ? "New specification" : specification.wrappedValue.specName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("SPEC \(index + 1) · \(specification.wrappedValue.unit ?? "No unit")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(expandedSpecificationIDs.contains(specID) ? "Collapse" : "Expand") specification \(specification.wrappedValue.specName)")

                HStack(spacing: 7) {
                    Spacer(minLength: 0)
                    Button {
                        moveSpecification(at: index, offset: -1)
                    } label: {
                        Label("Up", systemImage: "arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(index == 0)
                    .accessibilityLabel("Move specification up")
                    Button {
                        moveSpecification(at: index, offset: 1)
                    } label: {
                        Label("Down", systemImage: "arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(index == specifications.count - 1)
                    .accessibilityLabel("Move specification down")
                    Button(role: .destructive) {
                        specifications.removeAll { $0.id == specID }
                        renumberSpecifications()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Delete specification")
                }
            }

            if expandedSpecificationIDs.contains(specID) {
                TextField("Specification name", text: specification.specName)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    TextField("Unit (optional)", text: Binding(
                        get: { specification.wrappedValue.unit ?? "" },
                        set: { specification.wrappedValue.unit = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    LocalPhotoPickerButton(title: "", systemImage: "photo.badge.plus") { items in
                        Task { await importPhotos(items, for: specID) }
                    }
                    .frame(width: 42)
                    .accessibilityLabel("Add pictures to specification")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(quickUnits, id: \.self) { unit in
                            Button(unit) { specification.wrappedValue.unit = unit }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(specification.wrappedValue.unit == unit ? .indigo : .gray)
                        }
                    }
                }

                Picker("Detection mode", selection: specification.isNumeric) {
                    Text("Auto").tag(Optional<Bool>.none)
                    Text("Number").tag(Optional(true))
                    Text("Text").tag(Optional(false))
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Specification details")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("WYSIWYG HTML")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                SpecificationFormattingToolbar { command in
                    if command == "link" {
                        linkTargetSpecID = specID
                        showingLinkPrompt = true
                    } else {
                        editorCommands[specID] = "\(command)|\(UUID().uuidString)"
                    }
                }
                SpecificationRichTextEditor(
                    html: specification.details,
                    command: editorCommands[specID]
                )
                .frame(height: 125)
                .clipShape(RoundedRectangle(cornerRadius: 9))

                if !specification.wrappedValue.pictures.isEmpty {
                    attachmentEditorStrip(
                        specification.wrappedValue.pictures,
                        onOpen: presentImage
                    ) { picture in
                        specification.wrappedValue.pictures.removeAll { $0.id == picture.id }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemGray6).opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func attachmentEditorStrip(
        _ attachments: [MediaAttachment],
        onOpen: @escaping (MediaAttachment, [MediaAttachment]) -> Void,
        remove: @escaping (MediaAttachment) -> Void
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(attachments) { picture in
                    VStack(spacing: 4) {
                        if let url = store.localURL(for: picture),
                           let image = UIImage(contentsOfFile: url.path) {
                            Button {
                                onOpen(picture, attachments)
                            } label: {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 82, height: 72)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("View photo \(picture.name)")
                        } else {
                            Image(systemName: "photo")
                                .frame(width: 82, height: 72)
                                .background(Color(uiColor: .systemGray5), in: RoundedRectangle(cornerRadius: 8))
                        }
                        Button("Remove", role: .destructive) { remove(picture) }
                            .font(.caption2)
                    }
                }
            }
        }
    }

    private func toggleSpecification(_ id: String) {
        if expandedSpecificationIDs.contains(id) {
            expandedSpecificationIDs.remove(id)
        } else {
            expandedSpecificationIDs.insert(id)
        }
    }

    private func presentImage(_ attachment: MediaAttachment, _ attachments: [MediaAttachment]) {
        let images = attachments.compactMap { item -> ProductPhotoViewerItem? in
            guard let url = store.localURL(for: item),
                  let image = UIImage(contentsOfFile: url.path) else { return nil }
            return ProductPhotoViewerItem(id: item.id, name: item.name, image: image)
        }
        guard let index = images.firstIndex(where: { $0.id == attachment.id }) else { return }
        photoViewer = ProductPhotoViewerRequest(images: images, initialIndex: index)
    }

    private func addSearchedTag() {
        let value = tagSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        addTag(value)
        tagSearchText = ""
    }

    private func addTag(_ tag: String) {
        guard !selectedTags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else { return }
        selectedTags.insert(tag)
    }

    private func addSpecification() {
        specifications.append(Specification(
            id: "spec_" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(17)),
            specName: "New specification",
            details: "",
            order: specifications.count + 1,
            productId: productID,
            productTitle: name,
            pictures: []
        ))
        renumberSpecifications()
    }

    private func moveSpecification(at index: Int, offset: Int) {
        let destination = index + offset
        guard specifications.indices.contains(index), specifications.indices.contains(destination) else { return }
        specifications.swapAt(index, destination)
        renumberSpecifications()
    }

    private func sortSpecifications(ascending: Bool) {
        specifications.sort {
            let result = $0.specName.localizedCaseInsensitiveCompare($1.specName)
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
        renumberSpecifications()
    }

    @MainActor
    private func importPhotos(_ items: [PhotosPickerItem], for targetSpecID: String?) async {
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw PhotoImportError.unreadableImage
                }
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                let attachment = try store.saveLocalPhoto(
                    data,
                    originalName: "\(targetSpecID == nil ? "product" : "spec")_\(UUID().uuidString).\(ext)"
                )
                if let targetSpecID,
                   let index = specifications.firstIndex(where: { $0.id == targetSpecID }) {
                    specifications[index].pictures.append(attachment)
                } else {
                    pictures.append(attachment)
                }
            } catch {
                errorText = "Could not import a selected photo: \(error.localizedDescription)"
            }
        }
    }

    private func renumberSpecifications() {
        for index in specifications.indices {
            specifications[index].order = index + 1
            specifications[index].productId = productID
            specifications[index].productTitle = name
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = selectedTags.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        renumberSpecifications()
        let savedProduct = Product(
            id: productID,
            name: trimmedName,
            brand: brand.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: tags,
            overview: overview,
            pictures: pictures,
            createdTime: product?.createdTime ?? ISO8601DateFormatter().string(from: Date())
        )
        store.saveProduct(savedProduct, specifications: specifications)
        store.statusMessage = product == nil ? "Product added." : "Product updated."
        dismiss()
    }

    private enum PhotoImportError: LocalizedError {
        case unreadableImage
        var errorDescription: String? { "The selected photo could not be read." }
    }
}

private struct FlexibleTagList: View {
    let tags: [String]
    var onRemove: ((String) -> Void)?
    private let columns = [GridItem(.adaptive(minimum: 76), alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 7) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 5) {
                    Text(tag)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    if let onRemove {
                        Button {
                            onRemove(tag)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove tag \(tag)")
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.indigo.opacity(0.1), in: Capsule())
                .foregroundStyle(.indigo)
            }
        }
    }
}

private struct LocalPhotoPickerButton: View {
    let title: String
    let systemImage: String
    let onSelection: ([PhotosPickerItem]) -> Void
    @State private var selection: [PhotosPickerItem] = []

    var body: some View {
        PhotosPicker(selection: $selection, maxSelectionCount: 12, matching: .images) {
            Group {
                if title.isEmpty {
                    Image(systemName: systemImage)
                        .font(.headline)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(uiColor: .systemGray6), in: RoundedRectangle(cornerRadius: 9))
                } else {
                    Label(title, systemImage: systemImage)
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .onChange(of: selection) { _, items in
            guard !items.isEmpty else { return }
            onSelection(items)
            selection = []
        }
    }
}

private extension View {
    func detailCard() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.gray.opacity(0.12), lineWidth: 1)
            }
    }
}
