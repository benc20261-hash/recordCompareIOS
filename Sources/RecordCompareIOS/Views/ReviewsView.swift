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
    @State private var sortOrder: ReviewSortOrder = .newest
    @State private var selectedProduct = "All"
    @State private var selectedTagOrBrand = "All"
    @State private var importPresented = false
    @State private var importError: String?
    @State private var importedReviewsForAssignment: [Review]?

    private var reviewFilters: [String] {
        let values = store.allTags + store.allBrands + store.products.map(\.name)
        var unique = ["All"]
        for value in values where !unique.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
            unique.append(value)
        }
        return unique
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
            let matchesTag = selectedTagOrBrand == "All" ||
                linkedProducts.contains {
                    $0.tags.contains { $0.caseInsensitiveCompare(selectedTagOrBrand) == .orderedSame } ||
                    $0.brand.caseInsensitiveCompare(selectedTagOrBrand) == .orderedSame ||
                    $0.name.caseInsensitiveCompare(selectedTagOrBrand) == .orderedSame
                } ||
                (review.title ?? "").localizedCaseInsensitiveContains(selectedTagOrBrand) ||
                review.body.localizedCaseInsensitiveContains(selectedTagOrBrand)
            guard matchesProduct && matchesTag else { return false }
            guard !query.isEmpty else { return true }
            let searchable = [
                review.title ?? "",
                review.body.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression),
                review.authorName ?? "",
                review.productTitles.joined(separator: " ")
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
            List {
                if !store.reviews.isEmpty {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Search reviews", text: $searchText)
                                .textInputAutocapitalization(.never)
                            if !searchText.isEmpty {
                                Button { searchText = "" } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Clear review search")
                            }
                        }
                    }
                    .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))

                    HStack {
                        Picker("Product", selection: $selectedProduct) {
                            Text("All products").tag("All")
                            ForEach(store.products) { product in
                                Text(product.name).tag(product.id)
                            }
                        }
                        Picker("Tag / Brand", selection: $selectedTagOrBrand) {
                            ForEach(reviewFilters, id: \.self) { value in
                                Text(value).tag(value)
                            }
                        }
                    }
                }

                Section {
                    ForEach(sortedReviews) { review in
                        NavigationLink {
                            ReviewDetailView(review: review) {
                                reviewToEdit = review
                                showingEditor = true
                            }
                        } label: {
                            ReviewRow(review: review)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.reviews.removeAll { $0.id == review.id }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                reviewToEdit = review
                                showingEditor = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.indigo)
                        }
                    }
                } header: {
                    HStack {
                        Text("\(sortedReviews.count) reviews")
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
                                .labelStyle(.titleAndIcon)
                        }
                        .textCase(nil)
                    }
                }
            }
            .overlay {
                if store.reviews.isEmpty {
                    ContentUnavailableView(
                        "No reviews yet",
                        systemImage: "text.bubble",
                        description: Text("Add reviews to keep notes and product research together.")
                    )
                } else if sortedReviews.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Product Reviews")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        importPresented = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import HTML, Markdown, ZIP, or review folder")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        reviewToEdit = nil
                        showingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add review")
                }
            }
            .sheet(isPresented: $showingEditor, onDismiss: { reviewToEdit = nil }) {
                ReviewEditorView(review: reviewToEdit)
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
                allowedContentTypes: [.html, .zip, .folder, UTType(filenameExtension: "md") ?? .plainText],
                allowsMultipleSelection: false
            ) { result in
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

private struct ReviewRow: View {
    let review: Review

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(String(repeating: "★", count: max(0, min(5, review.rating ?? 0))))
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Rating \(review.rating ?? 0) out of 5")
            }
            if !review.productTitles.isEmpty {
                Text(review.productTitles.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.indigo)
                    .lineLimit(1)
            }
            Text(plainText(review.body))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 5)
    }

    private var displayTitle: String {
        guard let title = review.title, !title.isEmpty else { return "Review #\(review.reviewNumber)" }
        return title
    }

    private func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ReviewDetailView: View {
    @EnvironmentObject private var store: ProductStore
    @State private var htmlContentHeight: CGFloat = 180
    @State private var selectedPhotoURL: URL?
    let review: Review
    let onEdit: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(review.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Review #\(review.reviewNumber)")
                    .font(.largeTitle.bold())
                if !review.productTitles.isEmpty {
                    Text(review.productTitles.joined(separator: ", "))
                        .foregroundStyle(.indigo)
                }
                Text("By \(review.authorName ?? "Verified Reviewer") • \(review.rating ?? 0)/5")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let pros = review.pros, !pros.isEmpty {
                    labeledNotes("Pros", items: pros, color: .green)
                }
                if let cons = review.cons, !cons.isEmpty {
                    labeledNotes("Cons", items: cons, color: .orange)
                }
                Divider()
                if review.bodyFormat == "markdown" {
                    ReviewMarkdownView(markdown: store.displayableReviewMarkdown(review.body))
                } else {
                    ReviewHTMLView(
                        html: store.displayableReviewHTML(review.body),
                        baseURL: store.localMediaDirectoryURL,
                        contentHeight: $htmlContentHeight
                    )
                    .frame(height: htmlContentHeight)
                }
                if !review.pictures.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(review.pictures) { picture in
                                if let url = store.localURL(for: picture), let image = UIImage(contentsOfFile: url.path) {
                                    Button {
                                        selectedPhotoURL = url
                                    } label: {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 250, height: 220)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Open review photo \(picture.name)")
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .fullScreenCover(isPresented: Binding(
            get: { selectedPhotoURL != nil },
            set: { if !$0 { selectedPhotoURL = nil } }
        )) {
            if let selectedPhotoURL,
               let image = UIImage(contentsOfFile: selectedPhotoURL.path) {
                ZStack(alignment: .topTrailing) {
                    Color.black.ignoresSafeArea()
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Button {
                        self.selectedPhotoURL = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white)
                            .padding(20)
                    }
                    .accessibilityLabel("Close photo")
                }
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit", action: onEdit)
            }
        }
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
        .sheet(isPresented: $showingEditor) {
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

    private var attributedMarkdown: AttributedString {
        (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }

    var body: some View {
        Text(attributedMarkdown)
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
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var pictures: [MediaAttachment]
    @State private var errorText: String?

    private var isMarkdown: Bool { review?.bodyFormat == "markdown" }

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
            Form {
                Section("Review") {
                    TextField("Title", text: $title)
                    TextField("Author", text: $author)
                    Picker("Rating", selection: $rating) {
                        ForEach(1...5, id: \.self) { value in
                            Text("\(value) stars").tag(value)
                        }
                    }
                    TextField("Pros (one per line)", text: $prosText, axis: .vertical)
                        .lineLimit(2...5)
                    TextField("Cons (one per line)", text: $consText, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Review content") {
                    if isMarkdown {
                        TextEditor(text: $bodyText)
                            .frame(minHeight: 220)
                    } else {
                        ReviewFormattingToolbar { command in
                            editorCommand = "\(command)|\(UUID().uuidString)"
                        }
                        RichReviewEditorWebView(
                            html: Binding(
                                get: { store.displayableReviewHTML(bodyText) },
                                set: { bodyText = $0 }
                            ),
                            command: editorCommand,
                            baseURL: store.localMediaDirectoryURL
                        )
                        .frame(height: 340)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 12, matching: .images) {
                        Label("Insert photos", systemImage: "photo")
                    }
                    if !pictures.isEmpty {
                        Text("\(pictures.count) attached photo\(pictures.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let errorText {
                        Text(errorText).font(.footnote).foregroundStyle(.red)
                    }
                }

                Section("Linked products") {
                    ForEach(store.products) { product in
                        Button {
                            if selectedIDs.contains(product.id) {
                                selectedIDs.remove(product.id)
                            } else {
                                selectedIDs.insert(product.id)
                            }
                        } label: {
                            HStack {
                                Text(product.name)
                                Spacer()
                                if selectedIDs.contains(product.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.indigo)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle(review == nil ? "Add Review" : "Edit Review")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await importPhotos(items) }
            }
        }
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
    @Binding var contentHeight: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(LocalMediaSchemeHandler(directoryURL: baseURL), forURLScheme: "app-media")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        context.coordinator.onHeightChange = { height in
            contentHeight = height
        }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.onHeightChange = { height in
            contentHeight = height
        }
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        view.loadHTMLString(Self.document(html), baseURL: baseURL)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private static func document(_ html: String) -> String {
        let safeHTML = sanitize(html)
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
        <style>body{font-family:-apple-system,sans-serif;font-size:16px;line-height:1.55;color:#172033;margin:12px;overflow-wrap:anywhere}
        img{max-width:100%;height:auto}table{max-width:100%;border-collapse:collapse;display:block;overflow-x:auto}
        td,th{border:1px solid #cbd5e1;padding:6px;vertical-align:top}blockquote{border-left:3px solid #94a3b8;margin-left:0;padding-left:12px;color:#475569}</style>
        </head><body>\(content)</body></html>
        """
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

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?
        var onHeightChange: ((CGFloat) -> Void)?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)") { [weak self] value, _ in
                guard let height = value as? CGFloat, height.isFinite else { return }
                self?.onHeightChange?(max(140, height + 24))
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let scheme = navigationAction.request.url?.scheme?.lowercased()
            decisionHandler(scheme == "file" || scheme == "about" || scheme == nil ? .allow : .cancel)
        }

    }
}

private enum ReviewPhotoImportError: LocalizedError {
    case unreadableImage

    var errorDescription: String? { "The selected photo could not be read." }
}

private struct ReviewFormattingToolbar: View {
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
                command("• List", "unordered")
                command("1. List", "ordered")
                command("Quote", "quote")
                command("Table", "table")
                command("Clear", "clear")
            }
        }
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
        view.loadHTMLString(Self.document(html), baseURL: baseURL)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard let command, command != context.coordinator.lastCommand else { return }
        context.coordinator.lastCommand = command
        let action = String(command.split(separator: "|", maxSplits: 1).first ?? "")
        if action == "image" {
            let parts = command.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count > 1,
                  let data = try? JSONEncoder().encode(String(parts[1])),
                  let encodedURL = String(data: data, encoding: .utf8) else { return }
            view.evaluateJavaScript("document.execCommand('insertImage', false, \(encodedURL));")
            return
        }
        let script: String
        switch action {
        case "bold": script = "document.execCommand('bold')"
        case "italic": script = "document.execCommand('italic')"
        case "underline": script = "document.execCommand('underline')"
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

    private static func document(_ html: String) -> String {
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
        <style>body{font-family:-apple-system,sans-serif;font-size:16px;line-height:1.5;color:#172033;margin:12px}
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
            let scheme = navigationAction.request.url?.scheme?.lowercased()
            decisionHandler(scheme == "file" || scheme == "about" || scheme == nil ? .allow : .cancel)
        }
    }
}
