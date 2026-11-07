import SwiftUI

struct ReviewsView: View {
    @EnvironmentObject var store: ProductStore
    @State private var showingNewReview = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.reviews.sorted { $0.reviewNumber > $1.reviewNumber }) { review in
                    NavigationLink {
                        ReviewDetailView(review: review)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(review.title?.isEmpty == false ? review.title! : "Review #\(review.reviewNumber)").font(.headline)
                                Spacer()
                                Text(String(repeating: "★", count: max(0, min(5, review.rating ?? 0)))).foregroundStyle(.orange)
                            }
                            Text(review.productTitles.joined(separator: ", ")).font(.subheadline).foregroundStyle(.indigo).lineLimit(1)
                            Text(review.body.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .padding(.vertical, 5)
                    }
                }
                .onDelete { offsets in
                    let sorted = store.reviews.sorted { $0.reviewNumber > $1.reviewNumber }
                    let ids = offsets.map { sorted[$0].id }
                    store.reviews.removeAll { ids.contains($0.id) }
                }
            }
            .overlay {
                if store.reviews.isEmpty { ContentUnavailableView("No reviews yet", systemImage: "text.bubble", description: Text("Add reviews to keep notes and product research together.")) }
            }
            .navigationTitle("Product Reviews")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingNewReview = true } label: { Image(systemName: "plus") } } }
            .sheet(isPresented: $showingNewReview) { ReviewEditorView() }
        }
    }
}

private struct ReviewDetailView: View {
    let review: Review
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(review.title ?? "Review #\(review.reviewNumber)").font(.largeTitle.bold())
                Text(review.productTitles.joined(separator: ", ")).foregroundStyle(.indigo)
                Text("By \(review.authorName ?? "Verified Reviewer") • \(review.rating ?? 0)/5")
                    .font(.subheadline).foregroundStyle(.secondary)
                Divider()
                ReviewHTMLView(html: review.body).frame(minHeight: 300)
            }
            .padding()
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ReviewEditorView: View {
    @EnvironmentObject var store: ProductStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var bodyText = ""
    @State private var author = ""
    @State private var rating = 5
    @State private var selectedIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Review") {
                    TextField("Title", text: $title)
                    TextField("Author", text: $author)
                    Picker("Rating", selection: $rating) { ForEach(1...5, id: \.self) { Text("\($0) stars").tag($0) } }
                    TextField("Notes / review content", text: $bodyText, axis: .vertical).lineLimit(6...15)
                }
                Section("Linked products") {
                    ForEach(store.products) { product in
                        Button {
                            if selectedIDs.contains(product.id) { selectedIDs.remove(product.id) } else { selectedIDs.insert(product.id) }
                        } label: {
                            HStack { Text(product.name); Spacer(); if selectedIDs.contains(product.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.indigo) } }
                        }.foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Add Review")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.saveReview(title: title, body: bodyText, author: author, rating: rating, productIDs: Array(selectedIDs)); dismiss() }
                        .disabled(title.isEmpty && bodyText.isEmpty)
                }
            }
        }
    }
}

private struct ReviewHTMLView: UIViewRepresentable {
    let html: String
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(); view.isEditable = false; view.isScrollEnabled = false; view.backgroundColor = .clear; return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        view.attributedText = try? NSAttributedString(data: Data(html.utf8), options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil)
    }
}
