import PhotosUI
import SwiftUI
import UIKit

struct SmartAddView: View {
    @EnvironmentObject private var store: ProductStore
    @State private var slots: [String?] = [nil, nil]
    @State private var didInitializeSlots = false
    @State private var searchText = ""
    @State private var selectedFilter = "All"
    @State private var newProductName = ""
    @State private var targetProductID = ""
    @State private var newSpecName = ""
    @State private var newSpecDetails = ""
    @State private var newSpecUnit = ""
    @State private var newSpecIsNumeric = false
    @State private var activeSheet: SmartAddSheetRequest?
    @State private var specToDelete: Specification?
    @State private var confirmResetSlots = false

    private var selectedProducts: [Product] {
        slots.compactMap { id in id.flatMap { value in store.products.first { $0.id == value } } }
    }

    private var matrixSpecNames: [String] {
        orderedSpecificationNames(for: selectedProducts, specifications: store.specifications)
    }

    private var filterOptions: [String] {
        var values = ["All"]
        for value in store.allTags + store.allBrands + store.products.map(\.name)
        where !values.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
            values.append(value)
        }
        return values
    }

    private var pickerCandidates: [Product] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.products.filter { product in
            let matchesFilter = selectedFilter == "All" ||
                product.tags.contains { $0.caseInsensitiveCompare(selectedFilter) == .orderedSame } ||
                product.brand.caseInsensitiveCompare(selectedFilter) == .orderedSame ||
                product.name.caseInsensitiveCompare(selectedFilter) == .orderedSame
            let specs = productSpecifications(for: product)
            let searchable = ([product.name, product.brand, product.overview] + product.tags +
                specs.flatMap { [$0.specName, $0.details] }).joined(separator: " ")
            return matchesFilter && (query.isEmpty || searchable.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    workspaceHeader
                    productFilter
                    slotControls
                    ForEach(Array(slots.enumerated()), id: \.offset) { index, productID in
                        slotCard(index: index, productID: productID)
                    }
                    if !selectedProducts.isEmpty {
                        quickCreateProduct
                        quickAddSpecification
                        selectedProductsSection
                        brandAndTagsSection
                        specificationsMatrix
                    } else {
                        ContentUnavailableView(
                            "No products selected in slots yet",
                            systemImage: "tray",
                            description: Text("Select products into the slots above to manage and compare their specifications.")
                        )
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGray6))
            .navigationTitle("Smart Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Catalog") { store.selectedTab = .catalog }
                }
            }
            .onAppear {
                if !didInitializeSlots {
                    syncSlotsFromStore(useDefaults: true)
                    didInitializeSlots = true
                    if store.comparedProductOrder.isEmpty {
                        syncStoreOrder()
                    }
                }
            }
            .onChange(of: store.comparedProductOrder) { _, _ in
                if didInitializeSlots { syncSlotsFromStore(useDefaults: false) }
            }
            .sheet(item: $activeSheet) { request in
                switch request.content {
                case .picker(let target):
                    ProductSlotPickerSheet(
                        products: pickerCandidates,
                        specifications: store.specifications,
                        selectedID: target.currentID,
                        onSelect: { product in select(product, at: target.index) }
                    )
                case .specEditor(let editor):
                    SmartSpecEditorSheet(product: editor.product, spec: editor.spec, specName: editor.specName)
                case .productAttributes(let product):
                    ProductAttributesSheet(product: product)
                case .specOrder(let product):
                    ProductSpecOrderSheet(product: product)
                }
            }
            .alert("Delete specification?", isPresented: Binding(
                get: { specToDelete != nil },
                set: { if !$0 { specToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let specToDelete {
                        store.deleteInlineSpec(productID: specToDelete.productId, specName: specToDelete.specName)
                    }
                    specToDelete = nil
                }
                Button("Cancel", role: .cancel) { specToDelete = nil }
            } message: {
                Text("Delete “\(specToDelete?.specName ?? "this specification")” from \(specToDelete?.productTitle ?? "this product")?")
            }
            .confirmationDialog("Reset all comparison slots?", isPresented: $confirmResetSlots, titleVisibility: .visible) {
                Button("Reset Slots", role: .destructive) {
                    slots = [nil, nil]
                    syncStoreOrder()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes all selected products from the comparison workspace.")
            }
        }
    }

    private var workspaceHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SMART ADD & SPECIFICATION WORKSPACE")
                .font(.caption.weight(.heavy))
                .tracking(1.1)
                .foregroundStyle(.secondary)
            Text("Choose products to compare & manage specs")
                .font(.title3.bold())
            Text("Select catalog products in ordered slots, then complete or edit their comparison details offline.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Label("\(selectedProducts.count) selected", systemImage: "checkmark.circle.fill")
                Spacer()
                Text("\(matrixSpecNames.count) specification fields")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.indigo)
            .padding(10)
            .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(16)
        .cardSurface()
    }

    private var productFilter: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Filter products by tag / brand / product")
                .font(.subheadline.weight(.semibold))
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search products, brands, tags, or specs", text: $searchText)
                    .textInputAutocapitalization(.never)
            }
            .padding(11)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            Picker("Filter", selection: $selectedFilter) {
                ForEach(filterOptions, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
        }
        .padding(14)
        .cardSurface()
    }

    private var slotControls: some View {
        HStack {
            if !selectedProducts.isEmpty {
                Button("Reset") { confirmResetSlots = true }
                    .buttonStyle(.bordered)
                    .tint(.red)
            }
            if slots.count > 2 {
                Button(role: .destructive) {
                    slots.removeLast()
                    syncStoreOrder()
                } label: {
                    Label("Remove last", systemImage: "minus.circle")
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            Button {
                guard slots.count < 5 else {
                    store.statusMessage = "You can compare up to 5 products."
                    return
                }
                slots.append(nil)
                activeSheet = SmartAddSheetRequest(content: .picker(SlotPickerRequest(index: slots.count - 1, currentID: nil)))
            } label: {
                Label("Add product slot", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .disabled(slots.count >= 5)
        }
    }

    @ViewBuilder
    private func slotCard(index: Int, productID: String?) -> some View {
        let product = productID.flatMap { id in store.products.first { $0.id == id } }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Slot \(index + 1) of \(slots.count)")
                    .font(.subheadline.weight(.bold))
                Spacer()
                if product != nil {
                    Button("Change") {
                        activeSheet = SmartAddSheetRequest(content: .picker(SlotPickerRequest(index: index, currentID: productID)))
                    }
                    Button {
                        clearSlot(at: index)
                    } label: {
                        Image(systemName: slots.count > 2 ? "trash" : "xmark")
                    }
                    .tint(.red)
                    .accessibilityLabel("Remove or clear slot \(index + 1)")
                }
            }
            if let product {
                HStack(spacing: 12) {
                    productThumbnail(product)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(product.name).font(.headline)
                        Text("\(product.brand.isEmpty ? "No brand" : product.brand) • \(productSpecifications(for: product).count) specifications")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button {
                        moveSelectedProduct(from: index, to: index - 1)
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .disabled(index == 0)
                    Button {
                        moveSelectedProduct(from: index, to: index + 1)
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .disabled(index >= selectedProducts.count - 1)
                }
            } else {
                Button {
                    activeSheet = SmartAddSheetRequest(content: .picker(SlotPickerRequest(index: index, currentID: nil)))
                } label: {
                    Label("Search and select a product", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .cardSurface()
    }

    private var quickCreateProduct: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New product name").font(.headline)
            TextField("Enter product name", text: $newProductName)
                .textFieldStyle(.roundedBorder)
            Text("\(matrixSpecNames.count) blank specifications will be copied from the comparison matrix.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                let oldCount = store.comparedProductOrder.count
                store.createAndCompare(name: newProductName, inheritedSpecNames: matrixSpecNames)
                guard store.comparedProductOrder.count > oldCount else { return }
                let newID = store.comparedProductOrder.last
                if let emptyIndex = slots.firstIndex(where: { $0 == nil }), let newID {
                    slots[emptyIndex] = newID
                } else if let newID, slots.count < 5 {
                    slots.append(newID)
                }
                newProductName = ""
            } label: {
                Label("Create and compare", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(newProductName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.comparedProductOrder.count >= 5)
        }
        .padding(14)
        .cardSurface()
    }

    private var quickAddSpecification: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add specification").font(.headline)
            Picker("Product", selection: $targetProductID) {
                ForEach(selectedProducts) { product in
                    Text(product.name).tag(product.id)
                }
            }
            .pickerStyle(.menu)
            TextField("Specification name", text: $newSpecName)
                .textFieldStyle(.roundedBorder)
            TextField("Optional value", text: $newSpecDetails)
                .textFieldStyle(.roundedBorder)
            TextField("Unit (optional)", text: $newSpecUnit)
                .textFieldStyle(.roundedBorder)
            Toggle("Numeric comparison", isOn: $newSpecIsNumeric)
            Button {
                guard !targetProductID.isEmpty else { return }
                store.updateInlineSpec(
                    productID: targetProductID,
                    specName: newSpecName,
                    details: newSpecDetails,
                    pictures: [],
                    unit: newSpecUnit,
                    isNumeric: newSpecIsNumeric
                )
                newSpecName = ""
                newSpecDetails = ""
                newSpecUnit = ""
                newSpecIsNumeric = false
            } label: {
                Label("Add specification to product", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(targetProductID.isEmpty || newSpecName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(14)
        .cardSurface()
        .onAppear {
            if targetProductID.isEmpty { targetProductID = selectedProducts.first?.id ?? "" }
        }
        .onChange(of: selectedProducts.map(\.id)) { _, ids in
            if !ids.contains(targetProductID) { targetProductID = ids.first ?? "" }
        }
    }

    private var selectedProductsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Selected products").font(.headline)
            ForEach(selectedProducts) { product in
                HStack(spacing: 10) {
                    productThumbnail(product)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(product.name).font(.subheadline.weight(.semibold))
                        Text(product.brand.isEmpty ? "Generic" : product.brand)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button("Edit") { activeSheet = SmartAddSheetRequest(content: .productAttributes(product)) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Specs") { activeSheet = SmartAddSheetRequest(content: .specOrder(product)) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                if product.id != selectedProducts.last?.id { Divider() }
            }
        }
        .padding(14)
        .cardSurface()
    }

    private var brandAndTagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Brand and tags").font(.headline)
            ForEach(selectedProducts) { product in
                VStack(alignment: .leading, spacing: 6) {
                    Text(product.name.uppercased()).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    HStack {
                        Text(product.brand.isEmpty ? "No brand" : product.brand)
                        Spacer()
                        Button("Edit") { activeSheet = SmartAddSheetRequest(content: .productAttributes(product)) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    if !product.tags.isEmpty {
                        Text(product.tags.joined(separator: " • "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if product.id != selectedProducts.last?.id { Divider() }
            }
        }
        .padding(14)
        .cardSurface()
    }

    private var specificationsMatrix: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("All details and specifications").font(.headline)
            Text("\(matrixSpecNames.count) fields shown across \(selectedProducts.count) products")
                .font(.caption)
                .foregroundStyle(.secondary)
            if matrixSpecNames.isEmpty {
                Text("No specifications yet. Add one above to begin the comparison matrix.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(matrixSpecNames, id: \.self) { name in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(name).font(.subheadline.weight(.bold))
                        Spacer()
                        if valuesDiffer(for: name) {
                            Text("DIFFERENT")
                                .font(.caption2.weight(.heavy))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Color.yellow.opacity(0.3), in: Capsule())
                        }
                    }
                    ForEach(selectedProducts) { product in
                        let spec = specification(for: product, name: name)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(product.name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    activeSheet = SmartAddSheetRequest(content: .specEditor(
                                        SpecEditorRequest(product: product, specName: name, spec: spec)
                                    ))
                                } label: {
                                    Label(spec == nil ? "Add data" : "Edit", systemImage: spec == nil ? "plus" : "pencil")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                if let spec {
                                    Button(role: .destructive) { specToDelete = spec } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Delete \(name) from \(product.name)")
                                }
                            }
                            if let spec, !spec.details.isEmpty || spec.unit != nil {
                                RichHTMLText(
                                    html: [spec.details, spec.unit ?? ""].filter { !$0.isEmpty }.joined(separator: " "),
                                    fontSize: 14,
                                    textColor: .label
                                )
                            } else {
                                Text("No data").italic().foregroundStyle(.tertiary)
                            }
                            if let spec, !spec.pictures.isEmpty {
                                attachmentGallery(spec.pictures)
                            }
                        }
                        .padding(10)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.15)))
            }
        }
        .padding(14)
        .cardSurface()
    }

    private func attachmentGallery(_ attachments: [MediaAttachment]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    if let url = store.localURL(for: attachment) {
                        LocalAttachmentThumbnail(url: url, name: attachment.name)
                    }
                }
            }
        }
    }

    private func productThumbnail(_ product: Product) -> some View {
        Group {
            if let picture = product.pictures.first, let url = store.localURL(for: picture) {
                LocalAttachmentThumbnail(url: url, name: product.name)
            } else {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.indigo)
                    .frame(width: 42, height: 42)
                    .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func productSpecifications(for product: Product) -> [Specification] {
        store.specifications
            .filter { specificationBelongs($0, to: product) }
            .sorted { $0.order < $1.order }
    }

    private func specification(for product: Product, name: String) -> Specification? {
        productSpecifications(for: product).first {
            specificationNameKey($0.specName) == specificationNameKey(name)
        }
    }

    private func valuesDiffer(for name: String) -> Bool {
        Set(selectedProducts.map {
            specification(for: $0, name: name)?.details.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        }).count > 1
    }

    private func syncSlotsFromStore(useDefaults: Bool) {
        let selected = store.comparedProductOrder.filter { id in store.products.contains(where: { $0.id == id }) }
        if selected.isEmpty {
            let defaults = useDefaults ? store.products.prefix(2).map(\.id) : []
            slots = defaults.map(Optional.some)
            while slots.count < 2 { slots.append(nil) }
        } else {
            slots = selected.map(Optional.some)
            if slots.count == 1 { slots.append(nil) }
        }
        while slots.count > 5 { slots.removeLast() }
        if targetProductID.isEmpty || !selectedProducts.contains(where: { $0.id == targetProductID }) {
            targetProductID = selectedProducts.first?.id ?? ""
        }
    }

    private func syncStoreOrder() {
        store.setComparedProductOrder(slots.compactMap { $0 })
    }

    private func moveSelectedProduct(from source: Int, to destination: Int) {
        syncStoreOrder()
        store.moveComparedProduct(from: source, to: destination)
        syncSlotsFromStore(useDefaults: false)
    }

    private func select(_ product: Product, at index: Int) {
        guard !slots.enumerated().contains(where: { $0.offset != index && $0.element == product.id }) else {
            store.statusMessage = "A product can only occupy one comparison slot."
            activeSheet = nil
            return
        }
        guard slots.indices.contains(index) else { activeSheet = nil; return }
        slots[index] = product.id
        normalizeSlots()
        syncStoreOrder()
        activeSheet = nil
    }

    private func clearSlot(at index: Int) {
        guard slots.indices.contains(index) else { return }
        if slots.count > 2 {
            slots.remove(at: index)
        } else {
            slots[index] = nil
        }
        normalizeSlots()
        syncStoreOrder()
    }

    private func normalizeSlots() {
        let selected = slots.compactMap { $0 }
        slots = selected.map(Optional.some)
        while slots.count < 2 { slots.append(nil) }
        while slots.count > 5 { slots.removeLast() }
    }
}

private struct ProductSlotPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let products: [Product]
    let specifications: [Specification]
    let selectedID: String?
    let onSelect: (Product) -> Void
    @State private var query = ""

    private var filteredProducts: [Product] {
        guard !query.isEmpty else { return products }
        return products.filter { product in
            let specs = specifications.filter { $0.productId == product.id || $0.productTitle == product.name }
            let searchable = ([product.name, product.brand, product.overview] + product.tags +
                specs.flatMap { [$0.specName, $0.details] }).joined(separator: " ")
            return searchable.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredProducts) { product in
                Button {
                    onSelect(product)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(product.name).font(.headline)
                            Text(([product.brand] + product.tags).filter { !$0.isEmpty }.joined(separator: " • "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if product.id == selectedID { Image(systemName: "checkmark").foregroundStyle(.indigo) }
                    }
                }
                .foregroundStyle(.primary)
            }
            .searchable(text: $query, prompt: "Search catalog")
            .navigationTitle("Select product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct SmartSpecEditorSheet: View {
    @EnvironmentObject private var store: ProductStore
    @Environment(\.dismiss) private var dismiss
    let product: Product
    let spec: Specification?
    let specName: String
    @State private var details: String
    @State private var unit: String
    @State private var isNumeric: Bool
    @State private var pictures: [MediaAttachment]
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var errorText: String?

    init(product: Product, spec: Specification?, specName: String) {
        self.product = product
        self.spec = spec
        self.specName = specName
        _details = State(initialValue: spec?.details ?? "")
        _unit = State(initialValue: spec?.unit ?? "")
        _isNumeric = State(initialValue: spec?.isNumeric ?? !(spec?.unit?.isEmpty ?? true))
        _pictures = State(initialValue: spec?.pictures ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Specification") {
                    Text(specName).font(.headline)
                    TextField("Details / value", text: $details, axis: .vertical)
                        .lineLimit(2...8)
                    TextField("Unit (optional)", text: $unit)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(["g", "kg", "inch", "cm", "mm", "year", "month", "mAh", "Hz", "$", "GB"], id: \.self) { value in
                                Button(value) { unit = value }
                                    .buttonStyle(.bordered)
                                    .tint(unit.caseInsensitiveCompare(value) == .orderedSame ? .indigo : .gray)
                            }
                        }
                    }
                    Toggle("Numeric comparison", isOn: $isNumeric)
                    Text("When enabled, Compare can show numeric bars and choose higher/lower as the preferred value.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Specification photos") {
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 12, matching: .images) {
                        Label("Add photos", systemImage: "photo")
                    }
                    if !pictures.isEmpty {
                        Text("\(pictures.count) photo\(pictures.count == 1 ? "" : "s") attached")
                            .foregroundStyle(.secondary)
                    }
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
            }
            .navigationTitle(spec == nil ? "Add data" : "Edit specification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateInlineSpec(
                            productID: product.id,
                            specName: specName,
                            details: details,
                            pictures: pictures,
                            unit: unit,
                            isNumeric: isNumeric
                        )
                        dismiss()
                    }
                }
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await importPhotos(items) }
            }
        }
    }

    @MainActor
    private func importPhotos(_ items: [PhotosPickerItem]) async {
        defer { photoItems = [] }
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw PhotoImportError.unreadableImage
                }
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                let photo = try store.saveLocalPhoto(data, originalName: "spec_\(UUID().uuidString).\(ext)")
                pictures.append(photo)
            } catch {
                errorText = "Could not import a selected photo: \(error.localizedDescription)"
            }
        }
    }
}

private struct ProductAttributesSheet: View {
    @EnvironmentObject private var store: ProductStore
    @Environment(\.dismiss) private var dismiss
    let product: Product
    @State private var brand: String
    @State private var tags: String

    init(product: Product) {
        self.product = product
        _brand = State(initialValue: product.brand)
        _tags = State(initialValue: product.tags.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(product.name) {
                    TextField("Brand", text: $brand)
                    TextField("Tags, separated by commas", text: $tags, axis: .vertical)
                }
            }
            .navigationTitle("Edit product details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateProductBrand(product.id, brand: brand)
                        let uniqueTags = tags.split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .reduce(into: [String]()) { result, tag in
                                if !result.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                                    result.append(tag)
                                }
                            }
                        store.updateProductTags(product.id, tags: uniqueTags)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ProductSpecOrderSheet: View {
    @EnvironmentObject private var store: ProductStore
    @Environment(\.dismiss) private var dismiss
    let product: Product

    private var specs: [Specification] {
        store.specifications.filter { $0.productId == product.id }.sorted { $0.order < $1.order }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(specs.enumerated()), id: \.element.id) { index, spec in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(spec.specName).font(.headline)
                            RichHTMLText(html: spec.details.isEmpty ? "No data" : spec.details, fontSize: 14, textColor: .label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button {
                            store.moveProductSpec(productID: product.id, specID: spec.id, offset: -1)
                        } label: { Image(systemName: "arrow.up") }
                        .disabled(index == 0)
                        Button {
                            store.moveProductSpec(productID: product.id, specID: spec.id, offset: 1)
                        } label: { Image(systemName: "arrow.down") }
                        .disabled(index == specs.count - 1)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .navigationTitle("\(product.name) specs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

private struct LocalAttachmentThumbnail: View {
    let url: URL
    let name: String

    var body: some View {
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 52)
                .clipped()
                .accessibilityLabel(name)
        } else {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 52)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
    }
}

private struct SlotPickerRequest: Identifiable {
    let id = UUID()
    let index: Int
    let currentID: String?
}

private struct SpecEditorRequest: Identifiable {
    let id = UUID()
    let product: Product
    let specName: String
    let spec: Specification?
}

private struct SmartAddSheetRequest: Identifiable {
    let id = UUID()
    let content: Content

    enum Content {
        case picker(SlotPickerRequest)
        case specEditor(SpecEditorRequest)
        case productAttributes(Product)
        case specOrder(Product)
    }
}

private extension View {
    func cardSurface() -> some View {
        background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.14)))
    }
}

private enum PhotoImportError: LocalizedError {
    case unreadableImage
    var errorDescription: String? { "The selected photo could not be read." }
}
