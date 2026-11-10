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

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                filterBar
                ForEach(store.filteredProducts) { product in
                    if tableLayout {
                        ProductTableRow(product: product) { selectedProduct = product }
                    } else {
                        ProductCard(product: product, onOpen: { selectedProduct = product })
                    }
                }
                if store.filteredProducts.isEmpty {
                    ContentUnavailableView.search(text: store.searchText)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGray6))
        .sheet(item: $selectedProduct) { product in ProductDetailSheet(product: product) }
        .sheet(isPresented: $showingNewProduct) { ProductWorkspaceSheet() }
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
                            Text("\(scope.title) (\(scope.count(tags: store.allTags.count, brands: store.allBrands.count, products: store.products.count))")
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
                if selected { Image(systemName: "checkmark") }
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

private enum CatalogFilterScope: String, CaseIterable, Identifiable {
    case all
    case tag
    case brand
    case product

    var id: String { rawValue }
    var title: String { rawValue == "all" ? "All" : rawValue.capitalized }

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
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ProductCard: View {
    @EnvironmentObject var store: ProductStore
    let product: Product
    var onOpen: () -> Void

    private var productSpecs: [Specification] {
        store.specifications.filter { $0.productId == product.id || $0.productTitle == product.name }.sorted { $0.order < $1.order }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(product.brand.isEmpty ? "Other" : product.brand.uppercased())
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7).background(Color(uiColor: .darkGray), in: RoundedRectangle(cornerRadius: 10))
                Spacer()
                Button {
                    store.toggleCompare(product.id)
                    if store.comparedProductIDs.contains(product.id) { store.selectedTab = .compare }
                } label: { Label(store.comparedProductIDs.contains(product.id) ? "Added" : "Compare", systemImage: store.comparedProductIDs.contains(product.id) ? "checkmark" : "plus").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 8) }
                    .buttonStyle(.bordered).tint(.indigo)
            }.padding(14)
            Button(action: onOpen) {
                Group {
                    if let picture = product.pictures.first, let url = store.localURL(for: picture) {
                        Image(uiImage: UIImage(contentsOfFile: url.path) ?? UIImage()).resizable().scaledToFit()
                            .frame(maxWidth: .infinity).frame(height: 230).background(Color(uiColor: .systemGray6))
                    } else {
                        RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: [Color.indigo.opacity(0.12), Color.blue.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(height: 180).overlay(Image(systemName: "shippingbox").font(.system(size: 44)).foregroundStyle(Color.indigo.opacity(0.4)))
                    }
                }
            }.buttonStyle(.plain).padding(.horizontal, 12)
            VStack(alignment: .leading, spacing: 12) {
                HStack { ForEach(product.tags.prefix(4), id: \.self) { tag in Text(tag).font(.system(size: 13)).padding(.horizontal, 10).padding(.vertical, 6).background(Color(uiColor: .systemGray6), in: Capsule()) } }
                Button(action: onOpen) { Text(product.name).font(.system(size: 23, weight: .bold)).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
                if !product.overview.isEmpty {
                    RichHTMLText(html: product.overview, fontSize: 15, textColor: .secondaryLabel)
                }
                if !productSpecs.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(productSpecs.prefix(5)) { spec in
                            HStack(alignment: .top) {
                                Text(spec.specName).foregroundStyle(.secondary)
                                Spacer(minLength: 12)
                                RichHTMLText(
                                    html: [spec.details, spec.unit ?? ""].filter { !$0.isEmpty }.joined(separator: " "),
                                    fontSize: 14,
                                    textColor: .label,
                                    alignment: .right
                                ).lineLimit(2)
                            }.font(.system(size: 14)).padding(.vertical, 8)
                            if spec.id != productSpecs.prefix(5).last?.id { Divider() }
                        }
                    }.padding(.horizontal, 12).background(Color(uiColor: .systemGray6).opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
                }
            }.padding(16)
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.gray.opacity(0.15), lineWidth: 1))
    }
}

private struct ProductDetailSheet: View {
    @EnvironmentObject private var store: ProductStore
    @Environment(\.dismiss) private var dismiss
    let product: Product
    @State private var editingProduct = false
    @State private var editingSpecification: SpecificationEditorRequest?
    @State private var specificationToDelete: Specification?
    @State private var confirmingProductDelete = false
    @State private var selectedImage: UIImage?

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
            .fullScreenCover(isPresented: Binding(
                get: { selectedImage != nil },
                set: { if !$0 { selectedImage = nil } }
            )) {
                if let selectedImage {
                    ZStack(alignment: .topTrailing) {
                        Color.black.ignoresSafeArea()
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Button {
                            self.selectedImage = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(.white)
                                .padding(20)
                        }
                        .accessibilityLabel("Close image")
                    }
                }
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
                    selectedImage = image
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
                Text(specification.specName.isEmpty ? "Untitled specification" : specification.specName)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                if let unit = specification.unit, !unit.isEmpty {
                    Text(unit)
                        .font(.caption2.monospaced().weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(uiColor: .systemGray5), in: RoundedRectangle(cornerRadius: 5))
                }
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
                RichHTMLText(html: specification.details, fontSize: 14, textColor: .label)
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
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(review.title?.isEmpty == false ? review.title! : "Review #\(review.reviewNumber)")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                            Spacer(minLength: 6)
                            Text(String(repeating: "★", count: max(0, min(5, review.rating ?? 0))))
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        if let author = review.authorName, !author.isEmpty {
                            Text(author)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !review.body.isEmpty {
                            RichHTMLText(html: review.body, fontSize: 13, textColor: .label)
                                .lineLimit(5)
                        }
                        if !review.pictures.isEmpty {
                            attachmentStrip(review.pictures, height: 104)
                        }
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

    private func attachmentStrip(_ attachments: [MediaAttachment], height: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    if let url = store.localURL(for: attachment),
                       let image = UIImage(contentsOfFile: url.path) {
                        Button {
                            selectedImage = image
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

private struct SpecificationEditorSheet: View {
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
                                                Image(uiImage: image)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 88, height: 78)
                                                    .clipped()
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                            }
                                            Button("Remove", role: .destructive) {
                                                pictures.removeAll { $0.id == picture.id }
                                            }
                                            .font(.caption2)
                                        }
                                    }
                                }
                            }
                        }
                        if let errorText {
                            Text(errorText).font(.footnote).foregroundStyle(.red)
                        }
                    }
                    .detailCard()
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGray6))
            .navigationTitle(specification.specName.isEmpty ? "Add Specification" : "Edit Specification")
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
                tool("B", command: "bold", bold: true)
                tool("I", command: "italic", italic: true)
                tool("U", command: "underline", underline: true)
                tool("• List", command: "unordered")
                tool("1. List", command: "ordered")
                tool("Link", command: "link")
                tool("Clear", command: "clear")
            }
        }
    }

    private func tool(
        _ title: String,
        command: String,
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false
    ) -> some View {
        Button {
            onCommand(command)
        } label: {
            Text(title)
                .font(.subheadline.weight(bold ? .heavy : .semibold))
                .italic(italic)
                .underline(underline)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel(title == "B" ? "Bold" : title == "I" ? "Italic" : title == "U" ? "Underline" : title)
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
            .replacingOccurrences(of: #"(?i)\s+on[a-z]+\s*=\s*(["']).*?\1"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)(href|src)\s*=\s*(["'])\s*javascript:[^"']*\2"#, with: "$1=\"#\"", options: .regularExpression)
        let content: String
        if let match = try? NSRegularExpression(pattern: #"(?is)<body[^>]*>(.*?)</body>"#)
            .firstMatch(in: safe, range: NSRange(safe.startIndex..., in: safe)),
           let range = Range(match.range(at: 1), in: safe) {
            content = String(safe[range])
        } else {
            content = safe
        }
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>body{font-family:-apple-system,sans-serif;font-size:16px;line-height:1.45;color:#172033;margin:8px;min-height:145px;outline:none;overflow-wrap:anywhere}ul,ol{padding-left:24px}a{color:#4f46e5}</style>
        </head><body contenteditable="true">\(content)<script>document.body.addEventListener('input',()=>window.webkit.messageHandlers.specificationContent.postMessage(document.body.innerHTML));</script></body></html>
        """
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
                    @State private var name: String
                    @State private var brand: String
                    @State private var tagsText: String
                    @State private var overview: String
                    @State private var pictures: [MediaAttachment]
                    @State private var specifications: [Specification]
                    @State private var photoItems: [PhotosPickerItem] = []
                    @State private var errorText: String?

                    private let quickUnits = ["g", "kg", "inch", "cm", "mm", "year", "month", "mAh", "Hz", "$", "GB"]

                    init(product: Product? = nil) {
                        self.product = product
                        _name = State(initialValue: product?.name ?? "")
                        _brand = State(initialValue: product?.brand ?? "")
                        _tagsText = State(initialValue: product?.tags.joined(separator: ", ") ?? "")
                        _overview = State(initialValue: product?.overview ?? "")
                        _pictures = State(initialValue: product?.pictures ?? [])
                        _specifications = State(initialValue: [])
                    }

                    var body: some View {
                        NavigationStack {
                            Form {
                                Section("Product") {
                                    TextField("Product name", text: $name)
                                    TextField("Brand", text: $brand)
                                    TextField("Tags, separated by commas", text: $tagsText)
                                    if !store.allTags.isEmpty {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack {
                                                ForEach(store.allTags, id: \.self) { tag in
                                                    Button(tag) { appendTag(tag) }
                                                        .buttonStyle(.bordered)
                                                }
                                            }

                                        }
                                    }
                                    TextField("Overview", text: $overview, axis: .vertical)
                                        .lineLimit(3...8)
                                }

                                Section("Product photos") {
                                    PhotosPicker(selection: $photoItems, maxSelectionCount: 12, matching: .images) {
                                        Label("Add photos", systemImage: "photo.badge.plus")
                                    }
                                    .onChange(of: photoItems) { _, items in
                                        guard !items.isEmpty else { return }
                                        Task { await addPhotos(items) }
                                    }
                                    if !pictures.isEmpty {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 12) {
                                                ForEach(pictures) { picture in
                                                    VStack(spacing: 4) {
                                                        if let url = store.localURL(for: picture), let image = UIImage(contentsOfFile: url.path) {
                                                            Image(uiImage: image)
                                                                .resizable()
                                                                .scaledToFill()
                                                                .frame(width: 92, height: 92)
                                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                                        } else {
                                                            Image(systemName: "photo")
                                                                .frame(width: 92, height: 92)
                                                                .background(Color(uiColor: .systemGray5), in: RoundedRectangle(cornerRadius: 10))
                                                        }
                                                        Button("Remove", role: .destructive) {
                                                            pictures.removeAll { $0.id == picture.id }
                                                        }
                                                        .font(.caption)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Section {
                                    ForEach($specifications) { $specification in
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                TextField("Specification name", text: $specification.specName)
                                                TextField("Unit", text: Binding(
                                                    get: { specification.unit ?? "" },
                                                    set: { specification.unit = $0.isEmpty ? nil : $0 }
                                                ))
                                                .frame(width: 80)
                                            }
                                            TextField("Value / details", text: $specification.details, axis: .vertical)
                                                .lineLimit(1...4)
                                            ScrollView(.horizontal, showsIndicators: false) {
                                                HStack {
                                                    ForEach(quickUnits, id: \.self) { unit in
                                                        Button(unit) { specification.unit = unit }
                                                            .buttonStyle(.bordered)
                                                            .tint(specification.unit == unit ? .indigo : .gray)
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    .onDelete { specifications.remove(atOffsets: $0); renumberSpecifications() }
                                    .onMove { specifications.move(fromOffsets: $0, toOffset: $1); renumberSpecifications() }

                                    Button {
                                        specifications.append(Specification(
                                            id: "spec_" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(17)),
                                            specName: "",
                                            details: "",
                                            order: specifications.count + 1,
                                            productId: product?.id ?? "",
                                            productTitle: name,
                                            pictures: []
                                        ))
                                    } label: {
                                        Label("Add specification", systemImage: "plus.circle")
                                    }
                                } header: {
                                    Text("Specifications")
                                } footer: {
                                    Text("Drag rows to reorder specifications. Swipe left to remove one.")
                                }

                                if let errorText {
                                    Section {
                                        Text(errorText).foregroundStyle(.red)
                                    }
                                }
                            }
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
                                ToolbarItem(placement: .bottomBar) {
                                    EditButton()
                                }
                            }
                            .onAppear {
                                if let product {
                                    specifications = store.specifications
                                        .filter { $0.productId == product.id || $0.productTitle == product.name }
                                        .sorted { $0.order < $1.order }
                                }
                            }
                        }
                    }

                    private func appendTag(_ tag: String) {
                        var tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        guard !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else { return }
                        tags.append(tag)
                        tagsText = tags.joined(separator: ", ")
                    }

                    @MainActor
                    private func addPhotos(_ items: [PhotosPickerItem]) async {
                        defer { photoItems = [] }
                        for item in items {
                            do {
                                guard let data = try await item.loadTransferable(type: Data.self) else {
                                    throw PhotoImportError.unreadableImage
                                }
                                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                                let attachment = try store.saveLocalPhoto(data, originalName: "photo_\(UUID().uuidString).\(ext)")
                                pictures.append(attachment)
                            } catch {
                                errorText = "Could not import a selected photo: \(error.localizedDescription)"
                            }
                        }
                    }

                    private func renumberSpecifications() {
                        for index in specifications.indices {
                            specifications[index].order = index + 1
                        }
                    }

                    private func save() {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let tags = tagsText.split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        let savedProduct = Product(
                            id: product?.id ?? "rec_" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(17)),
                            name: trimmedName,
                            brand: brand.trimmingCharacters(in: .whitespacesAndNewlines),
                            tags: tags.reduce(into: [String]()) { unique, tag in
                                if !unique.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                                    unique.append(tag)
                                }
                            },
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
    private let columns = [GridItem(.adaptive(minimum: 76), alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 7) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.indigo.opacity(0.1), in: Capsule())
                    .foregroundStyle(.indigo)
            }
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
