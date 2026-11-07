import SwiftUI

struct SmartAddView: View {
    @EnvironmentObject var store: ProductStore
    @State private var productName = ""
    @State private var brand = ""
    @State private var tagsText = ""
    @State private var overview = ""
    @State private var specDrafts: [SpecDraft] = [SpecDraft()]

    var body: some View {
        NavigationStack {
            Form {
                Section("Product") {
                    TextField("Product name", text: $productName)
                    TextField("Brand", text: $brand)
                    TextField("Tags, separated by commas", text: $tagsText)
                    TextField("Overview", text: $overview, axis: .vertical).lineLimit(3...7)
                }
                Section {
                    ForEach($specDrafts) { $spec in
                        VStack(spacing: 8) {
                            TextField("Specification name", text: $spec.name)
                            TextField("Value / details", text: $spec.value, axis: .vertical)
                            TextField("Unit (optional)", text: $spec.unit)
                        }
                    }
                    .onDelete { specDrafts.remove(atOffsets: $0) }
                    Button { specDrafts.append(SpecDraft()) } label: { Label("Add specification", systemImage: "plus.circle") }
                } header: { Text("Specifications") } footer: { Text("Smart Add can prepare a product and its specifications for comparison. Automatic web research is not enabled in this offline version.") }
                Section {
                    Button(action: save) {
                        Label("Add Product", systemImage: "sparkles").frame(maxWidth: .infinity)
                    }
                    .disabled(productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Smart Add Product")
        }
    }

    private func save() {
        let tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let productId = "rec_" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(17))
        let product = Product(id: productId, name: productName.trimmingCharacters(in: .whitespacesAndNewlines), brand: brand, tags: tags, overview: overview, pictures: [], createdTime: ISO8601DateFormatter().string(from: Date()))
        store.upsert(product)
        for (index, draft) in specDrafts.enumerated() where !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.specifications.append(Specification(id: "spec_" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(17)), specName: draft.name, details: draft.value, order: index + 1, productId: productId, productTitle: product.name, unit: draft.unit.isEmpty ? nil : draft.unit, pictures: []))
        }
        productName = ""; brand = ""; tagsText = ""; overview = ""; specDrafts = [SpecDraft()]
        store.statusMessage = "Product and specifications added."
        store.selectedTab = .catalog
    }
}

private struct SpecDraft: Identifiable {
    let id = UUID()
    var name = ""
    var value = ""
    var unit = ""
}
