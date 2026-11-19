import SwiftUI
import UIKit

struct SmartAddView: View {
    @EnvironmentObject private var store: ProductStore
    @State private var slots: [String?] = [nil, nil]
    @State private var didInitializeSlots = false
    @State private var searchText = ""
    @State private var selectedFilterValue = "All"
    @State private var filterScope: SmartAddFilterScope = .all
    @State private var newProductName = ""
    @State private var targetProductID = ""
    @State private var newSpecName = ""
    @State private var newSpecDetails = ""
    @State private var newSpecUnit = ""
    @State private var newSpecIsNumeric = false
    @State private var activeSheet: SmartAddSheetRequest?
    @State private var productToView: Product?
    @State private var photoViewer: ProductPhotoViewerRequest?
    @State private var specToDelete: Specification?
    @State private var confirmResetSlots = false

    private var selectedProducts: [Product] {
        slots.compactMap { id in id.flatMap { value in store.products.first { $0.id == value } } }
    }

    private var matrixSpecNames: [String] {
        orderedSpecificationNames(for: selectedProducts, specifications: store.specifications)
    }

    private var filterOptions: [SmartAddFilterOption] {
        let values: [(String, SmartAddFilterScope)] = switch filterScope {
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
            .map { SmartAddFilterOption(title: $0.0, scope: $0.1) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var visibleFilterOptions: [SmartAddFilterOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return filterOptions }
        return filterOptions.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var pickerCandidates: [Product] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.products.filter { product in
            guard query.isEmpty || searchMatchingText(for: product).localizedCaseInsensitiveContains(query) else {
                return false
            }
            guard selectedFilterValue != "All" else { return true }
            switch filterScope {
            case .all:
                return product.tags.contains { $0.caseInsensitiveCompare(selectedFilterValue) == .orderedSame } ||
                    product.brand.caseInsensitiveCompare(selectedFilterValue) == .orderedSame ||
                    product.name.caseInsensitiveCompare(selectedFilterValue) == .orderedSame
            case .tag:
                return product.tags.contains { $0.caseInsensitiveCompare(selectedFilterValue) == .orderedSame }
            case .brand:
                return product.brand.caseInsensitiveCompare(selectedFilterValue) == .orderedSame
            case .product:
                return product.name.caseInsensitiveCompare(selectedFilterValue) == .orderedSame
            }
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
                .pointerDragScrolling()
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
            .onChange(of: searchText) { _, query in
                updateFilterScope(for: query)
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
                    SpecificationEditorSheet(product: editor.product, specification: editor.specification)
                case .productAttributes(let product):
                    ProductAttributesSheet(product: product)
                case .specOrder(let product):
                    ProductSpecOrderSheet(product: product)
                }
            }
            .sheet(item: $productToView) { product in
                ProductDetailSheet(product: product)
            }
            .fullScreenCover(item: $photoViewer) { request in
                ProductPhotoViewer(images: request.images, initialIndex: request.initialIndex)
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
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search tags, brands, or products", text: $searchText)
                    .textInputAutocapitalization(.never)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Clear product search")
                }
            }
            .padding(11)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(SmartAddFilterScope.allCases) { scope in
                        let selected = filterScope == scope
                        Button {
                            filterScope = scope
                            selectedFilterValue = "All"
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: scope.symbol)
                                    .foregroundStyle(selected ? .white : scope.tint)
                                Text("\(scope.title) (\(scope.count(tags: store.allTags.count, brands: store.allBrands.count, products: store.products.count)))")
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
            .pointerDragScrolling()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterOptionButton(title: "All", scope: .all)
                    ForEach(visibleFilterOptions) { option in
                        filterOptionButton(title: option.title, scope: option.scope)
                    }
                }
                .pointerDragScrolling()
            }
            if pickerCandidates.isEmpty {
                Text("No products match the current search and filter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
                if let product {
                    Button {
                        productToView = product
                    } label: {
                        Label("View product", systemImage: "eye")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("View \(product.name)")
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
                                    let editorSpec = spec ?? Specification(
                                        id: "spec_" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(17)),
                                        specName: name,
                                        details: "",
                                        order: store.specifications
                                            .filter { $0.productId == product.id || $0.productTitle == product.name }
                                            .map(\.order)
                                            .max()
                                            .map { $0 + 1 } ?? 1,
                                        productId: product.id,
                                        productTitle: product.name
                                    )
                                    activeSheet = SmartAddSheetRequest(content: .specEditor(
                                        SpecEditorRequest(product: product, specification: editorSpec)
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
                        Button {
                            presentImage(attachment, from: attachments)
                        } label: {
                            LocalAttachmentThumbnail(url: url, name: attachment.name)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("View image \(attachment.name)")
                    }
                }
                .pointerDragScrolling()
            }
        }
    }

    private func productThumbnail(_ product: Product) -> some View {
        Group {
            if let picture = product.pictures.first, let url = store.localURL(for: picture) {
                Button {
                    presentImage(picture, from: product.pictures)
                } label: {
                    LocalAttachmentThumbnail(url: url, name: product.name)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View photo of \(product.name)")
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

    private func searchMatchingText(for product: Product) -> String {
        let specifications = productSpecifications(for: product)
        return ([product.name, product.brand, product.overview] + product.tags +
            specifications.flatMap { [$0.specName, $0.details, $0.unit ?? ""] }).joined(separator: " ")
    }

    private func filterOptionButton(title: String, scope: SmartAddFilterScope) -> some View {
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
              !filterOptions.contains(where: { $0.title.localizedCaseInsensitiveContains(query) }) else {
            return
        }
        let nextScope: SmartAddFilterScope
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

    private func presentImage(_ attachment: MediaAttachment, from attachments: [MediaAttachment]) {
        let images = attachments.compactMap { item -> ProductPhotoViewerItem? in
            guard let url = store.localURL(for: item),
                  let image = UIImage(contentsOfFile: url.path) else { return nil }
            return ProductPhotoViewerItem(id: item.id, name: item.name, image: image)
        }
        guard let index = images.firstIndex(where: { $0.id == attachment.id }) else { return }
        photoViewer = ProductPhotoViewerRequest(images: images, initialIndex: index)
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
                            Text(spec.details.isEmpty ? "No data" : RichHTMLText.plainText(from: spec.details))
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
    let specification: Specification
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

private enum SmartAddFilterScope: String, CaseIterable, Identifiable {
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

private struct SmartAddFilterOption: Identifiable {
    let title: String
    let scope: SmartAddFilterScope
    var id: String { "\(scope.rawValue):\(title)" }
}

private extension View {
    func cardSurface() -> some View {
        background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.14)))
    }
}
