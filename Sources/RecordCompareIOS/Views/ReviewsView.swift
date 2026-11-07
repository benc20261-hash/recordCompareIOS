import SwiftUI
import UIKit

struct ReviewsView: View {
    @EnvironmentObject private var store: ProductStore
    @State private var reviewToEdit: Review?
    @State private var showingEditor = false
    @State private var searchText = ""
    @State private var sortOrder: ReviewSortOrder = .newest

    private var sortedReviews: [Review] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matching = store.reviews.filter { review in
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
    let review: Review
    let onEdit: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(review.title?.isEmpty == false ? review.title! : "Review #\(review.reviewNumber)")
                    .font(.largeTitle.bold())
                if !review.productTitles.isEmpty {
                    Text(review.productTitles.joined(separator: ", "))
                        .foregroundStyle(.indigo)
                }
                Text("By \(review.authorName ?? "Verified Reviewer") • \(review.rating ?? 0)/5")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Divider()
                ReviewHTMLView(html: review.body)
                    .frame(minHeight: 240)
            }
            .padding()
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit", action: onEdit)
            }
        }
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

    init(review: Review?) {
        self.review = review
        _title = State(initialValue: review?.title ?? "")
        _bodyText = State(initialValue: review?.body ?? "")
        _author = State(initialValue: review?.authorName ?? "")
        _rating = State(initialValue: review?.rating ?? 5)
        _selectedIDs = State(initialValue: Set(review?.productIds ?? []))
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
                    TextField("Notes / review content", text: $bodyText, axis: .vertical)
                        .lineLimit(6...15)
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
        }
    }

    private func save() {
        let linkedProducts = store.products.filter { selectedIDs.contains($0.id) }
        if var existing = review, let index = store.reviews.firstIndex(where: { $0.id == existing.id }) {
            existing.title = title
            existing.body = bodyText
            existing.authorName = author.isEmpty ? "Verified Reviewer" : author
            existing.rating = rating
            existing.productIds = linkedProducts.map(\.id)
            existing.productTitles = linkedProducts.map(\.name)
            store.reviews[index] = existing
        } else {
            let newReview = Review(
                id: "rev_" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(17)),
                reviewNumber: (store.reviews.map(\.reviewNumber).max() ?? 0) + 1,
                title: title,
                body: bodyText,
                authorName: author.isEmpty ? "Verified Reviewer" : author,
                rating: rating,
                productIds: linkedProducts.map(\.id),
                productTitles: linkedProducts.map(\.name),
                pictures: [],
                createdTime: ISO8601DateFormatter().string(from: Date())
            )
            store.reviews.insert(newReview, at: 0)
        }
        dismiss()
    }
}

private struct ReviewHTMLView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let htmlDocument = "<html><head><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"></head><body>\(html)</body></html>"
        view.attributedText = try? NSAttributedString(
            data: Data(htmlDocument.utf8),
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        )
    }
}
