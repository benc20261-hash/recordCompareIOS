import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import WebKit

struct ReviewsView: View {
    @EnvironmentObject private var store: ProductStore
    @State private var reviewToEdit: Review?
    @State private var showingEditor = false
    @State private var searchText = ""
    @State private var filterSearchText = ""
    @State private var sortOrder: ReviewSortOrder = .newest
    @State private var selectedProduct = "All"
    @State private var selectedFilterValue = "All"
    @State private var filterScope: ReviewFilterScope = .all
    @State private var showingProductPicker = false
    @State private var importPresented = false
    @State private var importKind: ReviewImportKind?
    @State private var importError: String?
    @State private var importedReviewsForAssignment: [Review]?
    @State private var reviewPendingDelete: Review?

    private var reviewFilterOptions: [ReviewFilterOption] {
        let values: [(String, ReviewFilterScope)] = switch filterScope {
        case .all:
            store.allTags.map { ($0, .tag) } +
                store.allBrands.map { ($0, .brand) } +
                store.products.map { ($0.name, .product) }
        case .tag:
            store.allTags.map { ($0, .tag) }
        case .brand:
            store.allBrands.map { ($0, .brand) }
        case .product:
            store.products.map { ($0.name, .product) }
        }
        var seen = Set<String>()
        return values
            .filter { seen.insert($0.0.lowercased()).inserted }
            .map { ReviewFilterOption(title: $0.0, scope: $0.1) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var visibleReviewFilterOptions: [ReviewFilterOption] {
        let query = filterSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return reviewFilterOptions }
        return reviewFilterOptions.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var productReviewCounts: [String: Int] {
        Dictionary(uniqueKeysWithValues: store.products.map { product in
            (product.id, store.reviews.filter {
                $0.productIds.contains(product.id) || $0.productTitles.contains(product.name)
            }.count)
        })
    }

    private var sortedReviews: [Review] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matching = store.reviews.filter { review in
            let linkedProducts = store.products.filter {
                review.productIds.contains($0.id) || review.productTitles.contains($0.name)
            }
            let matchesProduct = selectedProduct == "All" || linkedProducts.contains {
                $0.id == selectedProduct || $0.name == selectedProduct
            }
            let matchesFilter = selectedFilterValue == "All" ||
                linkedProducts.contains {
                    switch filterScope {
                    case .all:
                        return $0.tags.contains { $0.caseInsensitiveCompare(selectedFilterValue) == .orderedSame } ||
                            $0.brand.caseInsensitiveCompare(selectedFilterValue) == .orderedSame ||
                            $0.name.caseInsensitiveCompare(selectedFilterValue) == .orderedSame
                    case .tag:
                        return $0.tags.contains { $0.caseInsensitiveCompare(selectedFilterValue) == .orderedSame }
                    case .brand:
                        return $0.brand.caseInsensitiveCompare(selectedFilterValue) == .orderedSame
                    case .product:
                        return $0.name.caseInsensitiveCompare(selectedFilterValue) == .orderedSame
                    }
                } ||
                (review.title ?? "").localizedCaseInsensitiveContains(selectedFilterValue) ||
                review.body.localizedCaseInsensitiveContains(selectedFilterValue)
            guard matchesProduct && matchesFilter else { return false }
            guard !query.isEmpty else { return true }
            let productSearch = linkedProducts
                .flatMap { [$0.name, $0.brand] + $0.tags }
                .joined(separator: " ")
            let searchable = [
                review.title ?? "",
                review.body.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression),
                review.authorName ?? "",
                review.productTitles.joined(separator: " "),
                productSearch
            ].joined(separator: " ").lowercased()
            return searchable.contains(query)
        }

        switch sortOrder {
        case .newest:
            return matching.sorted { $0.reviewNumber > $1.reviewNumber }
        case .oldest:
            return matching.sorted { $0.reviewNumber < $1.reviewNumber }
        case .highestRated:
            return matching.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    reviewsHeader
                    reviewFilters
                    HStack {
                        Label("\(sortedReviews.count) reviews", systemImage: "text.bubble")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Menu {
                            ForEach(ReviewSortOrder.allCases) { order in
                                Button {
                                    sortOrder = order
                                } label: {
                                    if sortOrder == order {
                                        Label(order.title, systemImage: "checkmark")
                                    } else {
                                        Text(order.title)
                                    }
                                }
                            }
                        } label: {
                            Label(sortOrder.title, systemImage: "arrow.up.arrow.down")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    if sortedReviews.isEmpty {
                        noReviewsState
                    } else {
                        ForEach(sortedReviews) { review in
                            reviewCard(review)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
                .background(PointerDragScrollSupport())
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Reviews")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showingEditor, onDismiss: { reviewToEdit = nil }) {
                ReviewEditorView(review: reviewToEdit)
            }
            .sheet(isPresented: $showingProductPicker) {
                ReviewProductPickerSheet(
                    products: store.products,
                    reviewCounts: productReviewCounts,
                    selectedProductID: selectedProduct == "All" ? nil : selectedProduct
                ) { productID in
                    selectedProduct = productID ?? "All"
                }
            }
            .sheet(isPresented: Binding(
                get: { importedReviewsForAssignment != nil },
                set: { if !$0 { importedReviewsForAssignment = nil } }
            )) {
                if let importedReviewsForAssignment {
                    ReviewImportAssignmentsSheet(
                        reviews: importedReviewsForAssignment,
                        products: store.products
                    ) { selectedIDs, titles, assignments in
                        let importedIDs = Set(importedReviewsForAssignment.map(\.id))
                        store.reviews.removeAll { importedIDs.contains($0.id) && !selectedIDs.contains($0.id) }
                        for (reviewID, title) in titles {
                            if let index = store.reviews.firstIndex(where: { $0.id == reviewID }) {
                                store.reviews[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                        for (reviewID, productIDs) in assignments {
                            if selectedIDs.contains(reviewID) {
                                store.setReviewProducts(reviewID: reviewID, productIDs: productIDs)
                            }
                        }
                        self.importedReviewsForAssignment = nil
                    }
                }
            }
            .fileImporter(
                isPresented: $importPresented,
                allowedContentTypes: importKind?.allowedContentTypes ?? [.html],
                allowsMultipleSelection: false
            ) { result in
                importKind = nil
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        let existingIDs = Set(store.reviews.map(\.id))
                        store.statusMessage = try store.importReviewNotes(from: url)
                        let imported = store.reviews.filter { !existingIDs.contains($0.id) }
                        importedReviewsForAssignment = imported.isEmpty ? nil : imported
                        importError = nil
                    } catch {
                        importError = error.localizedDescription
                    }
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .onChange(of: filterSearchText) { _, query in
                updateFilterScope(for: query)
            }
            .confirmationDialog(
                "Delete this review?",
                isPresented: Binding(
                    get: { reviewPendingDelete != nil },
                    set: { if !$0 { reviewPendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Review", role: .destructive) {
                    if let reviewPendingDelete {
                        store.reviews.removeAll { $0.id == reviewPendingDelete.id }
                    }
                    reviewPendingDelete = nil
                }
                Button("Cancel", role: .cancel) { reviewPendingDelete = nil }
            } message: {
                Text("This review will be removed from this device.")
            }
            .alert("Could not import notes", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private var reviewsHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Community User Reviews")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("Real feedback and product research notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text("\(store.reviews.count) total")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.indigo)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.indigo.opacity(0.1), in: Capsule())
            }
            HStack(spacing: 8) {
                Menu {
                    ForEach(ReviewImportKind.allCases) { kind in
                        Button {
                            beginImport(kind)
                        } label: {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                    }
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Import reviews")

                Button {
                    reviewToEdit = nil
                    showingEditor = true
                } label: {
                    Label("Write a Review", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.indigo)
            }
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.14)))
    }

    private var reviewFilters: some View {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search reviews...", text: $searchText)
                            .textInputAutocapitalization(.never)
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear review search")
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 40)
                    .background(Color(uiColor: .systemGray6), in: RoundedRectangle(cornerRadius: 10))

                    Button {
                        showingProductPicker = true
                    } label: {
                        Label(selectedProductName, systemImage: "shippingbox")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(height: 40)
                            .background(selectedProduct == "All" ? Color(uiColor: .systemGray6) : Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Filter by product: \(selectedProductName)")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(ReviewFilterScope.allCases) { scope in
                            let selected = filterScope == scope
                            Button {
                                filterScope = scope
                                selectedFilterValue = "All"
                            } label: {
                                Text("\(scope.title) \(scope.count(tags: store.allTags.count, brands: store.allBrands.count, products: store.products.count))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(selected ? .white : .primary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(selected ? Color.indigo : Color(uiColor: .systemGray6), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .pointerDragScrolling()
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .foregroundStyle(.secondary)
                    TextField("Filter tags, brands, products", text: $filterSearchText)
                        .textInputAutocapitalization(.never)
                    if !filterSearchText.isEmpty {
                        Button { filterSearchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear product filter search")
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(Color(uiColor: .systemGray6), in: RoundedRectangle(cornerRadius: 10))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        reviewFilterButton(title: "All", scope: .all)
                        ForEach(visibleReviewFilterOptions) { option in
                            reviewFilterButton(title: option.title, scope: option.scope)
                        }
                    }
                }
                .pointerDragScrolling()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.14)))
        }

        @ViewBuilder
        private var noReviewsState: some View {
            VStack(spacing: 10) {
                Image(systemName: store.reviews.isEmpty ? "text.bubble" : "magnifyingglass")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.indigo.opacity(0.7))
                    .padding(15)
                    .background(Color.indigo.opacity(0.08), in: Circle())
                Text(store.reviews.isEmpty ? "No reviews yet" : "No reviews found")
                    .font(.headline)
                Text(store.reviews.isEmpty
                     ? "Import a note or write a review to start your product research library."
                     : "Try changing the search or filters to see more reviews.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                if !store.reviews.isEmpty {
                    Button("Clear search and filters") {
                        searchText = ""
                        filterSearchText = ""
                        selectedProduct = "All"
                        selectedFilterValue = "All"
                        filterScope = .all
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 230)
            .padding(20)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.14)))
        }

        private func reviewCard(_ review: Review) -> some View {
            HStack(alignment: .top, spacing: 12) {
                NavigationLink {
                    ReviewDetailView(review: review) {
                        reviewToEdit = review
                        showingEditor = true
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Label(review.productTitles.first ?? "Unlinked review", systemImage: "shippingbox")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.indigo)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if let rating = review.rating {
                                HStack(spacing: 2) {
                                    ForEach(0..<5, id: \.self) { index in
                                        Image(systemName: index < rating ? "star.fill" : "star")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                        Text(review.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Review #\(review.reviewNumber)")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(plainReviewText(review.body))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            Image(systemName: "person.crop.circle")
                            Text(review.authorName ?? "Verified Reviewer")
                            Text("•")
                            Text("Review #\(review.reviewNumber)")
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    Button {
                        reviewToEdit = review
                        showingEditor = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        reviewPendingDelete = review
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Review actions")
            }
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.gray.opacity(0.14)))
        }

        private func plainReviewText(_ html: String) -> String {
            RichHTMLText.plainText(from: html).trimmingCharacters(in: .whitespacesAndNewlines)
        }

    private var selectedProductName: String {
            guard selectedProduct != "All" else { return "All products" }
            return store.products.first(where: { $0.id == selectedProduct })?.name ?? "All products"
        }

        private func reviewFilterButton(title: String, scope: ReviewFilterScope) -> some View {
            let selected = selectedFilterValue.caseInsensitiveCompare(title) == .orderedSame
            return Button {
                selectedFilterValue = title
                if title != "All" { filterScope = scope }
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

        private func updateFilterScope(for query: String) {
            let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty, filterScope != .all,
                  !reviewFilterOptions.contains(where: { $0.title.localizedCaseInsensitiveContains(query) }) else {
                return
            }
            let nextScope: ReviewFilterScope
            if store.allTags.contains(where: { $0.localizedCaseInsensitiveContains(query) }) {
                nextScope = .tag
            } else if store.allBrands.contains(where: { $0.localizedCaseInsensitiveContains(query) }) {
                nextScope = .brand
            } else if store.products.contains(where: { $0.name.localizedCaseInsensitiveContains(query) }) {
                nextScope = .product
            } else {
                nextScope = .all
            }
            filterScope = nextScope
            selectedFilterValue = "All"
        }

        private func beginImport(_ kind: ReviewImportKind) {
            importKind = kind
            importPresented = true
        }
}

struct PointerDragScrollSupport: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = PointerScrollSupportView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

extension View {
    func pointerDragScrolling() -> some View {
        background(PointerDragScrollSupport())
    }
}

private final class PointerScrollSupportView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            var ancestor = self?.superview
            while let view = ancestor {
                if view is UIScrollView {
                    Self.enablePointerPanning(in: view)
                    return
                }
                ancestor = view.superview
            }
        }
    }

    private static func enablePointerPanning(in view: UIView) {
        if let scrollView = view as? UIScrollView {
            scrollView.panGestureRecognizer.allowedTouchTypes = [
                NSNumber(value: UITouch.TouchType.direct.rawValue),
                NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)
            ]
        }
        view.subviews.forEach(enablePointerPanning)
    }
}

private struct ReviewImportAssignmentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let reviews: [Review]
    let products: [Product]
    let onSave: (Set<String>, [String: String], [String: Set<String>]) -> Void
    @State private var selectedIDs: Set<String>
    @State private var titles: [String: String]
    @State private var assignments: [String: Set<String>]

    init(
        reviews: [Review],
        products: [Product],
        onSave: @escaping (Set<String>, [String: String], [String: Set<String>]) -> Void
    ) {
        self.reviews = reviews
        self.products = products
        self.onSave = onSave
        _selectedIDs = State(initialValue: Set(reviews.map(\.id)))
        _titles = State(initialValue: Dictionary(
            uniqueKeysWithValues: reviews.map { ($0.id, $0.title ?? "") }
        ))
        _assignments = State(initialValue: Dictionary(
            uniqueKeysWithValues: reviews.map { ($0.id, Set($0.productIds)) }
        ))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(reviews) { review in
                    Section(review.title ?? "Review #\(review.reviewNumber)") {
                        Toggle("Include this note", isOn: Binding(
                            get: { selectedIDs.contains(review.id) },
                            set: { include in
                                if include { selectedIDs.insert(review.id) }
                                else { selectedIDs.remove(review.id) }
                            }
                        ))
                        TextField("Review title", text: Binding(
                            get: { titles[review.id, default: ""] },
                            set: { titles[review.id] = $0 }
                        ))
                        Menu {
                            ForEach(products) { product in
                                Button {
                                    var selected = assignments[review.id, default: []]
                                    if selected.contains(product.id) {
                                        selected.remove(product.id)
                                    } else {
                                        selected.insert(product.id)
                                    }
                                    assignments[review.id] = selected
                                } label: {
                                    if assignments[review.id, default: []].contains(product.id) {
                                        Label(product.name, systemImage: "checkmark")
                                    } else {
                                        Text(product.name)
                                    }
                                }
                            }
                        } label: {
                            Label(
                                "\(assignments[review.id, default: []].count) linked product(s)",
                                systemImage: "tag"
                            )
                        }
                        NavigationLink("Preview note") {
                            ReviewDetailView(review: review) {}
                        }
                    }
                }
            }
            .navigationTitle("Imported Reviews")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(selectedIDs, titles, assignments)
                        dismiss()
                    }
                }
            }
        }
    }
}

private enum ReviewSortOrder: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case highestRated

    var id: String { rawValue }
    var title: String {
        switch self {
        case .newest: "Newest first"
        case .oldest: "Oldest first"
        case .highestRated: "Highest rated"
        }
    }
}

private enum ReviewFilterScope: String, CaseIterable, Identifiable {
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

private struct ReviewFilterOption: Identifiable {
    let title: String
    let scope: ReviewFilterScope
    var id: String { "\(scope.rawValue):\(title)" }
}

private enum ReviewImportKind: String, CaseIterable, Identifiable {
    case folder
    case zip
    case html
    case markdown

    var id: String { rawValue }
    var title: String {
        switch self {
        case .folder: "Import HTML review folder"
        case .zip: "Import HTML review ZIP"
        case .html: "Import single HTML note"
        case .markdown: "Import Markdown note"
        }
    }

    var symbol: String {
        switch self {
        case .folder: "folder"
        case .zip: "doc.zipper"
        case .html: "doc.text"
        case .markdown: "text.page"
        }
    }

    var allowedContentTypes: [UTType] {
        switch self {
        case .folder:
            [.folder]
        case .zip:
            [.zip]
        case .html:
            [.html, UTType(filenameExtension: "htm") ?? .html]
        case .markdown:
            [
                UTType(filenameExtension: "md") ?? .plainText,
                UTType(filenameExtension: "markdown") ?? .plainText
            ]
        }
    }
}

private struct ReviewProductPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let products: [Product]
    let reviewCounts: [String: Int]
    let selectedProductID: String?
    let onSelect: (String?) -> Void
    @State private var searchText = ""

    private var filteredProducts: [Product] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return products }
        return products.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
                $0.brand.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onSelect(nil)
                    dismiss()
                } label: {
                    HStack {
                        Label("All products (\(reviewCounts.values.reduce(0, +)) reviews)", systemImage: "shippingbox")
                        Spacer()
                        if selectedProductID == nil { Image(systemName: "checkmark").foregroundStyle(.indigo) }
                    }
                }
                .foregroundStyle(.primary)

                Section("Products") {
                    ForEach(filteredProducts) { product in
                        Button {
                            onSelect(product.id)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(product.name)
                                    Text(product.brand.isEmpty ? "No brand" : product.brand)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(reviewCounts[product.id, default: 0])")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                if selectedProductID == product.id {
                                    Image(systemName: "checkmark").foregroundStyle(.indigo)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search products or brands")
            .navigationTitle("Filter by product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ReviewLinkedProductsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let products: [Product]
    let selectedIDs: Set<String>
    let onSave: (Set<String>) -> Void
    @State private var draftIDs: Set<String>
    @State private var searchText = ""

    init(products: [Product], selectedIDs: Set<String>, onSave: @escaping (Set<String>) -> Void) {
        self.products = products
        self.selectedIDs = selectedIDs
        self.onSave = onSave
        _draftIDs = State(initialValue: selectedIDs)
    }

    private var filteredProducts: [Product] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return products }
        return products.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
                $0.brand.localizedCaseInsensitiveContains(query) ||
                $0.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredProducts) { product in
                    Button {
                        if draftIDs.contains(product.id) {
                            draftIDs.remove(product.id)
                        } else {
                            draftIDs.insert(product.id)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(product.name)
                                    .font(.subheadline.weight(.medium))
                                Text(product.brand.isEmpty ? "No brand" : product.brand)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if draftIDs.contains(product.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.indigo)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .searchable(text: $searchText, prompt: "Search products or brands")
            .navigationTitle("Linked Products (\(draftIDs.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(draftIDs)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ReviewDetailView: View {
    @EnvironmentObject private var store: ProductStore
    @State private var photoViewer: ProductPhotoViewerRequest?
    @State private var zoomPercent = 85
    let review: Review
    let onEdit: () -> Void

    private var viewerHTML: String {
        var sections: [String] = []
        if let pros = review.pros, !pros.isEmpty {
            sections.append(noteSection("Pros", items: pros, className: "review-pros"))
        }
        if let cons = review.cons, !cons.isEmpty {
            sections.append(noteSection("Cons", items: cons, className: "review-cons"))
        }
        sections.append(store.displayableReviewHTML(review.body))

        let photoFigures = review.pictures.compactMap { picture -> String? in
            guard let url = store.localURL(for: picture) else { return nil }
            let filename = url.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? url.lastPathComponent
            let source = picture.url.hasPrefix("app-media://") ? picture.url : "app-media://\(filename)"
            return "<figure><img src=\"\(source)\" alt=\"\(escapeHTML(picture.name))\"><figcaption>\(escapeHTML(picture.name))</figcaption></figure>"
        }
        if !photoFigures.isEmpty {
            sections.append("<h2>Attached photos</h2>" + photoFigures.joined())
        }
        return sections.joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Text(review.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Review #\(review.reviewNumber)")
                    .font(.headline)
                    .lineLimit(2)
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        if !review.productTitles.isEmpty {
                            Label(review.productTitles.joined(separator: ", "), systemImage: "shippingbox")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.indigo)
                                .lineLimit(1)
                        }
                        Text("By \(review.authorName ?? "Verified Reviewer") • \(review.rating ?? 0)/5")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    ReviewZoomControls(percent: $zoomPercent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.white)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.gray.opacity(0.15)).frame(height: 1) }

            if review.bodyFormat == "markdown" {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let pros = review.pros, !pros.isEmpty {
                            labeledNotes("Pros", items: pros, color: .green)
                        }
                        if let cons = review.cons, !cons.isEmpty {
                            labeledNotes("Cons", items: cons, color: .orange)
                        }
                        ReviewMarkdownView(markdown: store.displayableReviewMarkdown(review.body), zoomPercent: zoomPercent)
                        reviewPhotoGrid
                    }
                    .padding()
                    .background(PointerDragScrollSupport())
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                ReviewHTMLView(
                    html: viewerHTML,
                    baseURL: store.localMediaDirectoryURL,
                    zoomPercent: zoomPercent,
                    onImageTap: openHTMLImage
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .fullScreenCover(item: $photoViewer) { request in
            ProductPhotoViewer(images: request.images, initialIndex: request.initialIndex)
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit", action: onEdit)
            }
        }
    }

    private var reviewPhotoGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
            ForEach(review.pictures) { picture in
                if let url = store.localURL(for: picture), let image = UIImage(contentsOfFile: url.path) {
                    Button {
                        presentImage(picture)
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 150)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open review photo \(picture.name)")
                }
            }
        }
    }

    private func noteSection(_ title: String, items: [String], className: String) -> String {
        let list = items.map { "<li>\(escapeHTML($0))</li>" }.joined()
        return "<section class=\"\(className)\"><h3>\(title)</h3><ul>\(list)</ul></section>"
    }

    private func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func openHTMLImage(_ source: String) {
        let filename: String
        if source.hasPrefix("app-media://") {
            let encodedName = String(source.dropFirst("app-media://".count))
            filename = encodedName.removingPercentEncoding ?? encodedName
        } else if let url = URL(string: source) {
            filename = url.lastPathComponent
        } else {
            return
        }
        guard let attachment = review.pictures.first(where: {
            store.localURL(for: $0)?.lastPathComponent == filename
        }) else { return }
        presentImage(attachment)
    }

    private func presentImage(_ attachment: MediaAttachment) {
        let images = review.pictures.compactMap { item -> ProductPhotoViewerItem? in
            guard let url = store.localURL(for: item),
                  let image = UIImage(contentsOfFile: url.path) else { return nil }
            return ProductPhotoViewerItem(id: item.id, name: item.name, image: image)
        }
        guard let index = images.firstIndex(where: { $0.id == attachment.id }) else { return }
        photoViewer = ProductPhotoViewerRequest(images: images, initialIndex: index)
    }

    private func labeledNotes(_ title: String, items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline).foregroundStyle(color)
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: title == "Pros" ? "plus.circle.fill" : "minus.circle.fill")
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProductReviewActionsSheet: View {
    let review: Review
    let startEditing: Bool
    @State private var showingEditor = false

    var body: some View {
        NavigationStack {
            ReviewDetailView(review: review) {
                showingEditor = true
            }
        }
        .fullScreenCover(isPresented: $showingEditor) {
            ReviewEditorView(review: review)
        }
        .onAppear {
            if startEditing {
                showingEditor = true
            }
        }
    }
}

private struct ReviewMarkdownView: View {
    let markdown: String
    let zoomPercent: Int

    private var attributedMarkdown: AttributedString {
        (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }

    var body: some View {
        Text(attributedMarkdown)
            .font(.system(size: 16 * CGFloat(zoomPercent) / 100))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReviewEditorView: View {
    @EnvironmentObject private var store: ProductStore
    @Environment(\.dismiss) private var dismiss

    let review: Review?
    @State private var title: String
    @State private var bodyText: String
    @State private var author: String
    @State private var rating: Int
    @State private var selectedIDs: Set<String>
    @State private var prosText: String
    @State private var consText: String
    @State private var editorCommand: String?
    @State private var zoomPercent = 85
    @State private var showingLinkedProducts = false
    @State private var linkURL = ""
    @State private var showingLinkPrompt = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var pictures: [MediaAttachment]
    @State private var errorText: String?

    private var isMarkdown: Bool { review?.bodyFormat == "markdown" }

    private var selectedProductSummary: String {
        let names = store.products.filter { selectedIDs.contains($0.id) }.map(\.name)
        switch names.count {
        case 0: return "Select product"
        case 1: return names[0]
        default: return "\(names[0]) +\(names.count - 1)"
        }
    }

    init(review: Review?) {
        self.review = review
        _title = State(initialValue: review?.title ?? "")
        _bodyText = State(initialValue: review?.body ?? "")
        _author = State(initialValue: review?.authorName ?? "")
        _rating = State(initialValue: review?.rating ?? 5)
        _selectedIDs = State(initialValue: Set(review?.productIds ?? []))
        _prosText = State(initialValue: review?.pros?.joined(separator: "\n") ?? "")
        _consText = State(initialValue: review?.cons?.joined(separator: "\n") ?? "")
        _pictures = State(initialValue: review?.pictures ?? [])
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                editorHeader
                if isMarkdown {
                    HStack {
                        PhotosPicker(selection: $photoItems, maxSelectionCount: 12, matching: .images) {
                            Label("Insert photo", systemImage: "photo")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Spacer()
                        ReviewZoomControls(percent: $zoomPercent)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                } else {
                    ReviewFormattingToolbar(photoItems: $photoItems, zoomPercent: $zoomPercent) { command in
                        if command == "link" {
                            showingLinkPrompt = true
                        } else {
                            editorCommand = "\(command)|\(UUID().uuidString)"
                        }
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        editorMetadata
                        if isMarkdown {
                            TextEditor(text: $bodyText)
                                .font(.system(size: 16 * CGFloat(zoomPercent) / 100))
                                .frame(height: 420)
                                .padding(4)
                                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.18)))
                        } else {
                            RichReviewEditorWebView(
                                html: Binding(
                                    get: { store.displayableReviewHTML(bodyText) },
                                    set: { bodyText = $0 }
                                ),
                                command: editorCommand,
                                baseURL: store.localMediaDirectoryURL,
                                zoomPercent: zoomPercent
                            )
                            .frame(height: 420)
                            .background(.white, in: RoundedRectangle(cornerRadius: 10))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.18)))
                        }
                        if !pictures.isEmpty {
                            Label("\(pictures.count) attached photo\(pictures.count == 1 ? "" : "s")", systemImage: "photo")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        DisclosureGroup("Pros & Cons") {
                            VStack(spacing: 8) {
                                TextField("Pros (one per line)", text: $prosText, axis: .vertical)
                                    .lineLimit(2...4)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Cons (one per line)", text: $consText, axis: .vertical)
                                    .lineLimit(2...4)
                                    .textFieldStyle(.roundedBorder)
                            }
                            .padding(.top, 6)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.18)))
                        if let errorText {
                            Text(errorText).font(.footnote).foregroundStyle(.red)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: 1100)
                    .frame(maxWidth: .infinity)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .scrollBounceBehavior(.basedOnSize)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingLinkedProducts) {
                ReviewLinkedProductsSheet(products: store.products, selectedIDs: selectedIDs) {
                    selectedIDs = $0
                }
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await importPhotos(items) }
            }
            .onChange(of: zoomPercent) { _, value in
                guard !isMarkdown else { return }
                editorCommand = "zoom|\(value)|\(UUID().uuidString)"
            }
            .alert("Insert link", isPresented: $showingLinkPrompt) {
                TextField("https://", text: $linkURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                Button("Cancel", role: .cancel) { linkURL = "" }
                Button("Insert", action: insertLink)
            } message: {
                Text("Add a link to the selected text.")
            }
        }
    }

    private var editorHeader: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 2) {
                Text(review == nil ? "Write Review" : "Edit Review")
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                Text(selectedProductSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 1) {
                ForEach(1...5, id: \.self) { value in
                    Button { rating = value } label: {
                        Image(systemName: value <= rating ? "star.fill" : "star")
                            .font(.system(size: 13))
                            .foregroundStyle(value <= rating ? .orange : .gray.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(value) stars")
                }
            }

            Button(action: save) {
                Label("Save", systemImage: "square.and.arrow.down.fill")
                    .font(.caption.weight(.bold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 9)
                    .frame(height: 34)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.indigo)
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.white)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.gray.opacity(0.15)).frame(height: 1) }
    }

    private var editorMetadata: some View {
        VStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    linkedProductsButton
                        .frame(minWidth: 106, maxWidth: 140)
                    TextField("Review title", text: $title)
                        .frame(minWidth: 80)
                        .textFieldStyle(.roundedBorder)
                    authorField
                        .frame(minWidth: 100, maxWidth: 160)
                }
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        linkedProductsButton
                        TextField("Review title", text: $title)
                            .textFieldStyle(.roundedBorder)
                    }
                    authorField
                }
            }
            if selectedIDs.count > 1 {
                Text("\(selectedIDs.count) linked products")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.18)))
    }

    private var linkedProductsButton: some View {
        Button {
            showingLinkedProducts = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.indigo)
                Text(selectedProductSummary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(Color(uiColor: .systemGray6), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select linked products")
    }

    private var authorField: some View {
        HStack(spacing: 6) {
            Image(systemName: "person")
                .foregroundStyle(.secondary)
            TextField("Reviewer", text: $author)
                .textInputAutocapitalization(.words)
        }
        .font(.caption)
        .padding(.horizontal, 9)
        .frame(height: 36)
        .background(Color(uiColor: .systemGray6), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
    }

    private func insertLink() {
        let value = linkURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let url = value.contains("://") || value.hasPrefix("mailto:") ? value : "https://\(value)"
        guard let components = URLComponents(string: url),
              ["https", "http", "mailto"].contains(components.scheme?.lowercased() ?? "") else {
            errorText = "Enter a valid HTTP, HTTPS, or email link."
            return
        }
        editorCommand = "link|\(url)|\(UUID().uuidString)"
        linkURL = ""
    }

    private func save() {
        let linkedProducts = store.products.filter { selectedIDs.contains($0.id) }
        let body = isMarkdown ? bodyText : store.normalizeReviewHTMLForStorage(bodyText)
        let reviewPictures = store.reviewAttachments(in: body, preserving: pictures)
        let pros = nonemptyLines(prosText)
        let cons = nonemptyLines(consText)
        if var existing = review, let index = store.reviews.firstIndex(where: { $0.id == existing.id }) {
            existing.title = title
            existing.body = body
            existing.authorName = author.isEmpty ? "Verified Reviewer" : author
            existing.rating = rating
            existing.pros = pros
            existing.cons = cons
            existing.productIds = linkedProducts.map(\.id)
            existing.productTitles = linkedProducts.map(\.name)
            existing.pictures = reviewPictures
            store.reviews[index] = existing
        } else {
            let newReview = Review(
                id: "rev_" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(17)),
                reviewNumber: (store.reviews.map(\.reviewNumber).max() ?? 0) + 1,
                title: title,
                body: body,
                pros: pros,
                cons: cons,
                authorName: author.isEmpty ? "Verified Reviewer" : author,
                rating: rating,
                productIds: linkedProducts.map(\.id),
                productTitles: linkedProducts.map(\.name),
                pictures: reviewPictures,
                createdTime: ISO8601DateFormatter().string(from: Date())
            )
            store.reviews.insert(newReview, at: 0)
        }
        dismiss()
    }

    private func nonemptyLines(_ text: String) -> [String]? {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines
    }

    @MainActor
    private func importPhotos(_ items: [PhotosPickerItem]) async {
        defer { photoItems = [] }
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw ReviewPhotoImportError.unreadableImage
                }
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                let attachment = try store.saveLocalPhoto(data, originalName: "review_\(UUID().uuidString).\(ext)")
                pictures.append(attachment)
                if !isMarkdown, let url = store.localURL(for: attachment) {
                    editorCommand = "image|\(url.absoluteString)|\(UUID().uuidString)"
                } else {
                    let filename = String(attachment.url.dropFirst("app-media://".count))
                    bodyText += "\n![\(attachment.name)](app-media://\(filename))"
                }
            } catch {
                errorText = "Could not import a selected photo: \(error.localizedDescription)"
            }
        }
    }
}

private struct ReviewHTMLView: UIViewRepresentable {
    let html: String
    let baseURL: URL
    let zoomPercent: Int
    let onImageTap: (String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(LocalMediaSchemeHandler(directoryURL: baseURL), forURLScheme: "app-media")
        configuration.userContentController.add(context.coordinator, name: "reviewImage")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isDirectionalLockEnabled = false
        view.scrollView.panGestureRecognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)
        ]
        context.coordinator.zoomPercent = zoomPercent
        context.coordinator.onImageTap = onImageTap
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.onImageTap = onImageTap
        let zoomChanged = context.coordinator.zoomPercent != zoomPercent
        context.coordinator.zoomPercent = zoomPercent
        guard context.coordinator.loadedHTML != html else {
            if zoomChanged { applyZoom(to: view) }
            return
        }
        context.coordinator.loadedHTML = html
        view.loadHTMLString(Self.document(html, zoomPercent: zoomPercent), baseURL: baseURL)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func applyZoom(to view: WKWebView) {
        view.evaluateJavaScript("document.body.style.zoom = '\(zoomPercent)%';")
    }

    private static func document(_ html: String, zoomPercent: Int) -> String {
        let safeHTML = sanitize(html)
        let bodyContent: String
        if let regex = try? NSRegularExpression(pattern: #"(?is)<body[^>]*>(.*?)</body>"#),
           let match = regex.firstMatch(in: safeHTML, range: NSRange(safeHTML.startIndex..., in: safeHTML)),
           let range = Range(match.range(at: 1), in: safeHTML) {
            bodyContent = String(safeHTML[range])
        } else {
            bodyContent = safeHTML
        }
        let content = wrapTables(bodyContent)
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body{min-height:100%;}body{font-family:-apple-system,sans-serif;font-size:16px;line-height:1.55;color:#172033;margin:12px;overflow-wrap:anywhere;zoom:\(zoomPercent)%}
        img{max-width:100%;height:auto;cursor:zoom-in}
        .review-table-scroll{width:100%;max-width:100%;overflow-x:auto;overflow-y:hidden;-webkit-overflow-scrolling:touch;overscroll-behavior-x:contain;cursor:grab}
        .review-table-scroll.dragging{cursor:grabbing}
        table{width:max-content;min-width:100%;max-width:none;border-collapse:collapse;margin:0 0 12px}
        td,th{min-width:90px;max-width:320px;border:1px solid #cbd5e1;padding:7px;vertical-align:top;white-space:normal;overflow-wrap:normal;word-break:normal}
        blockquote{border-left:3px solid #94a3b8;margin-left:0;padding-left:12px;color:#475569}
        .review-pros,.review-cons{border-radius:8px;padding:8px 12px;margin:12px 0}
        .review-pros{background:#f0fdf4;color:#166534}.review-cons{background:#fff7ed;color:#9a3412}
        #review-scrollbar{position:fixed;z-index:2147483647;top:4px;right:0;bottom:4px;width:18px;padding:0 3px;box-sizing:border-box;touch-action:none;user-select:none;-webkit-user-select:none}
        #review-scrollbar[hidden]{display:none}
        #review-scrollbar-thumb{position:absolute;top:0;left:3px;width:12px;min-height:48px;border-radius:8px;background:rgba(83,91,110,.78);border:1px solid rgba(255,255,255,.82);box-sizing:border-box;box-shadow:0 1px 4px rgba(0,0,0,.24);cursor:grab}
        #review-scrollbar.dragging #review-scrollbar-thumb{background:rgba(62,72,98,.96);cursor:grabbing}
        .review-pros h3,.review-cons h3{margin:2px 0 6px;font-size:15px}.review-pros ul,.review-cons ul{margin:0;padding-left:20px}</style>
        </head><body>\(content)
        <div id="review-scrollbar" aria-label="Scroll review content"><div id="review-scrollbar-thumb"></div></div>
        <script>
        document.addEventListener('click',function(event){var image=event.target.closest('img');if(image){window.webkit.messageHandlers.reviewImage.postMessage(image.getAttribute('src')||image.src);}});
        document.querySelectorAll('.review-table-scroll').forEach(function(table){
          var pending=false,dragging=false,startX=0,startY=0,startLeft=0;
          table.addEventListener('pointerdown',function(event){
            if(event.pointerType!=='mouse'||event.button!==0||this.scrollWidth<=this.clientWidth)return;
            pending=true;dragging=false;startX=event.clientX;startY=event.clientY;startLeft=this.scrollLeft;
          });
          table.addEventListener('pointermove',function(event){
            var dx=event.clientX-startX,dy=event.clientY-startY;
            if(pending&&!dragging){
              if(Math.max(Math.abs(dx),Math.abs(dy))<5)return;
              if(Math.abs(dx)<=Math.abs(dy)){pending=false;return;}
              dragging=true;this.classList.add('dragging');this.setPointerCapture(event.pointerId);
            }
            if(dragging){event.preventDefault();this.scrollLeft=startLeft-dx;}
          },{passive:false});
          var endDrag=function(){pending=false;dragging=false;table.classList.remove('dragging');};
          table.addEventListener('pointerup',endDrag);table.addEventListener('pointercancel',endDrag);
        });
        (function(){
          var track=document.getElementById('review-scrollbar'),thumb=document.getElementById('review-scrollbar-thumb');
          var startY=0,startTop=0,thumbTravel=0,scrollRange=0,currentTop=0;
          function update(){
            var viewport=window.innerHeight,content=document.documentElement.scrollHeight;
            scrollRange=Math.max(0,content-viewport);
            var trackHeight=Math.max(0,window.innerHeight-8);
            var thumbHeight=Math.min(trackHeight,Math.max(48,trackHeight*viewport/Math.max(content,1)));
            thumb.style.height=thumbHeight+'px';
            thumbTravel=Math.max(0,trackHeight-thumbHeight);
            currentTop=scrollRange?window.scrollY/scrollRange*thumbTravel:0;
            thumb.style.transform='translateY('+currentTop+'px)';
            track.hidden=scrollRange<=1||thumbTravel<=0;
          }
          function moveThumb(event){
            if(!track.classList.contains('dragging'))return;
            event.preventDefault();
            var top=Math.max(0,Math.min(thumbTravel,startTop+event.clientY-startY));
            window.scrollTo(0,thumbTravel?top/thumbTravel*scrollRange:0);
          }
          thumb.addEventListener('pointerdown',function(event){
            if(event.button!==undefined&&event.button!==0)return;
            update();startY=event.clientY;
            startTop=currentTop;
            track.classList.add('dragging');thumb.setPointerCapture(event.pointerId);event.preventDefault();
          });
          thumb.addEventListener('pointermove',moveThumb);
          function endDrag(){track.classList.remove('dragging');}
          thumb.addEventListener('pointerup',endDrag);thumb.addEventListener('pointercancel',endDrag);
          track.addEventListener('pointerdown',function(event){
            if(event.target===thumb)return;
            update();
            var rect=track.getBoundingClientRect();
            startY=event.clientY;startTop=Math.max(0,Math.min(thumbTravel,event.clientY-rect.top-thumb.offsetHeight/2));
            track.classList.add('dragging');track.setPointerCapture(event.pointerId);
            window.scrollTo(0,thumbTravel?startTop/thumbTravel*scrollRange:0);event.preventDefault();
          });
          track.addEventListener('pointermove',moveThumb);
          track.addEventListener('pointerup',endDrag);track.addEventListener('pointercancel',endDrag);
          window.addEventListener('scroll',update,{passive:true});
          window.addEventListener('resize',update);
          new ResizeObserver(update).observe(document.documentElement);
          update();
        })();
        </script>
        </body></html>
        """
    }

    private static func wrapTables(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?is)<table\b([^>]*)>(.*?)</table\s*>"#) else {
            return html
        }
        return regex.stringByReplacingMatches(
            in: html,
            range: NSRange(html.startIndex..., in: html),
            withTemplate: #"<div class="review-table-scroll" tabindex="0"><table$1>$2</table></div>"#
        )
    }

    private static func sanitize(_ html: String) -> String {
        html
            .replacingOccurrences(of: #"(?is)<script\b[^>]*>.*?</script>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<(iframe|object|embed)\b[^>]*>.*?</\1>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<style\b[^>]*>.*?</style>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<link\b[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\s+on[a-z]+\s*=\s*(["']).*?\1"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)(src|href)\s*=\s*(["'])\s*javascript:[^"']*\2"#, with: "$1=\"#\"", options: .regularExpression)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var loadedHTML: String?
        var zoomPercent = 85
        var onImageTap: ((String) -> Void)?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "reviewImage", let source = message.body as? String else { return }
            onImageTap?(source)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.style.zoom = '\(zoomPercent)%';")
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                decisionHandler(.cancel)
                ExternalLinkOpener.open(url)
                return
            }
            let scheme = navigationAction.request.url?.scheme?.lowercased()
            decisionHandler(scheme == "file" || scheme == "about" || scheme == "app-media" || scheme == nil ? .allow : .cancel)
        }

    }
}

private enum ReviewPhotoImportError: LocalizedError {
    case unreadableImage

    var errorDescription: String? { "The selected photo could not be read." }
}

private struct ReviewZoomControls: View {
    @Binding var percent: Int

    var body: some View {
        HStack(spacing: 12) {
            Button {
                percent = max(50, percent - 10)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(percent <= 50)
            .accessibilityLabel("Zoom out")

            Text("\(percent)%")
                .font(.caption.monospacedDigit().weight(.semibold))
                .frame(minWidth: 42)
                .accessibilityLabel("Zoom \(percent) percent")

            Button {
                percent = min(200, percent + 10)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(percent >= 200)
            .accessibilityLabel("Zoom in")
        }
        .buttonStyle(.borderless)
    }
}

private struct ReviewFormattingToolbar: View {
    @Binding var photoItems: [PhotosPickerItem]
    @Binding var zoomPercent: Int
    let onCommand: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                command("H1", "h1")
                command("H2", "h2")
                command("H3", "h3")
                command("B", "bold")
                command("I", "italic")
                command("U", "underline")
                command("S", "strikethrough")
                command("• List", "unordered")
                command("1. List", "ordered")
                command("Quote", "quote")
                command("Link", "link")
                command("Table", "table")
                command("Clear", "clear")
                PhotosPicker(selection: $photoItems, maxSelectionCount: 12, matching: .images) {
                    Label("Photo", systemImage: "photo")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                ReviewZoomControls(percent: $zoomPercent)
                    .padding(.horizontal, 4)
            }
        }
        .pointerDragScrolling()
    }

    private func command(_ title: String, _ command: String) -> some View {
        Button(title) { onCommand(command) }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }
}

private struct RichReviewEditorWebView: UIViewRepresentable {
    @Binding var html: String
    let command: String?
    let baseURL: URL
    let zoomPercent: Int

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "reviewContent")
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(LocalMediaSchemeHandler(directoryURL: baseURL), forURLScheme: "app-media")
        configuration.userContentController = contentController
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .white
        view.scrollView.backgroundColor = .white
        context.coordinator.loadedSource = html
        view.loadHTMLString(Self.document(html, zoomPercent: zoomPercent), baseURL: baseURL)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard let command, command != context.coordinator.lastCommand else { return }
        context.coordinator.lastCommand = command
        let parts = command.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        let action = String(parts.first ?? "")
        if action == "image" {
            guard parts.count > 1,
                  let data = try? JSONEncoder().encode(String(parts[1])),
                  let encodedURL = String(data: data, encoding: .utf8) else { return }
            view.evaluateJavaScript("document.execCommand('insertImage', false, \(encodedURL));")
            return
        }
        if action == "link" {
            guard parts.count > 1,
                  let data = try? JSONEncoder().encode(String(parts[1])),
                  let encodedURL = String(data: data, encoding: .utf8) else { return }
            view.evaluateJavaScript("document.execCommand('createLink', false, \(encodedURL));")
            return
        }
        if action == "zoom" {
            guard parts.count > 1, let value = Int(parts[1]) else { return }
            let boundedValue = min(200, max(50, value))
            view.evaluateJavaScript("document.body.style.zoom = '\(boundedValue)%';")
            return
        }
        let script: String
        switch action {
        case "bold": script = "document.execCommand('bold')"
        case "italic": script = "document.execCommand('italic')"
        case "underline": script = "document.execCommand('underline')"
        case "strikethrough": script = "document.execCommand('strikeThrough')"
        case "h1", "h2", "h3": script = "document.execCommand('formatBlock', false, '<\(action)>')"
        case "unordered": script = "document.execCommand('insertUnorderedList')"
        case "ordered": script = "document.execCommand('insertOrderedList')"
        case "quote": script = "document.execCommand('formatBlock', false, '<blockquote>')"
        case "table": script = "document.execCommand('insertHTML', false, '<table><tbody><tr><td>&nbsp;</td><td>&nbsp;</td></tr><tr><td>&nbsp;</td><td>&nbsp;</td></tr></tbody></table><p></p>')"
        case "clear": script = "document.execCommand('removeFormat')"
        default: return
        }
        view.evaluateJavaScript(script)
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.parent = self
        return coordinator
    }

    private static func document(_ html: String, zoomPercent: Int) -> String {
        let safeHTML = html
            .replacingOccurrences(of: #"(?is)<script\b[^>]*>.*?</script>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<(iframe|object|embed)\b[^>]*>.*?</\1>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<style\b[^>]*>.*?</style>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<link\b[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\s+on[a-z]+\s*=\s*(["']).*?\1"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)(src|href)\s*=\s*(["'])\s*javascript:[^"']*\2"#, with: "$1=\"#\"", options: .regularExpression)
        let content: String
        if let regex = try? NSRegularExpression(pattern: #"(?is)<body[^>]*>(.*?)</body>"#),
           let match = regex.firstMatch(in: safeHTML, range: NSRange(safeHTML.startIndex..., in: safeHTML)),
           let range = Range(match.range(at: 1), in: safeHTML) {
            content = String(safeHTML[range])
        } else {
            content = safeHTML
        }
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>body{font-family:-apple-system,sans-serif;font-size:16px;line-height:1.5;color:#172033;margin:12px;zoom:\(zoomPercent)%}
        img{max-width:100%;height:auto}table{width:100%;border-collapse:collapse}td,th{border:1px solid #94a3b8;padding:6px}
        blockquote{border-left:3px solid #94a3b8;margin-left:0;padding-left:12px}</style>
        </head><body><div id="editor" contenteditable="true">\(content)</div>
        <script>document.getElementById('editor').addEventListener('input',function(){window.webkit.messageHandlers.reviewContent.postMessage(this.innerHTML);});</script>
        </body></html>
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: RichReviewEditorWebView?
        var loadedSource: String?
        var lastCommand: String?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "reviewContent", let value = message.body as? String else { return }
            parent?.html = value
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                decisionHandler(.cancel)
                ExternalLinkOpener.open(url)
                return
            }
            let scheme = navigationAction.request.url?.scheme?.lowercased()
            decisionHandler(scheme == "file" || scheme == "about" || scheme == "app-media" || scheme == nil ? .allow : .cancel)
        }
    }
}
