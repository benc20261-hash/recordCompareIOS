import SwiftUI
import UIKit

struct CompareView: View {
    @EnvironmentObject private var store: ProductStore
    @State private var sortByName = false
    @State private var numericOverrides: [String: Bool] = [:]
    @State private var bestValueModes: [String: BestValueMode] = [:]
    @State private var productSearch = ""
    @State private var productFilter = "All"
    @State private var selectedComparisonImage: UIImage?
    @State private var selectedReview: Review?
    @State private var confirmClearComparison = false
    @State private var comparisonSlots: [String?] = [nil, nil]
    @State private var slotPickerRequest: CompareSlotPickerRequest?
    @State private var didInitializeSlots = false

    private var selectedProducts: [Product] {
        let selected = store.comparedProductOrder.compactMap { id in
            store.products.first { $0.id == id }
        }
        return sortByName
            ? selected.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            : selected
    }

    private var comparisonSpecifications: [String] {
        orderedSpecificationNames(for: selectedProducts, specifications: store.specifications)
    }

    private var productFilterOptions: [String] {
        var options = ["All"]
        for value in store.allTags + store.allBrands + store.products.map(\.name)
        where !options.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
            options.append(value)
        }
        return options
    }

    private var pickerProducts: [Product] {
        store.products.filter { product in
            let matchesFilter = productFilter == "All" ||
                product.tags.contains { $0.caseInsensitiveCompare(productFilter) == .orderedSame } ||
                product.brand.caseInsensitiveCompare(productFilter) == .orderedSame ||
                product.name.caseInsensitiveCompare(productFilter) == .orderedSame
            let specs = store.specifications.filter { $0.productId == product.id || $0.productTitle == product.name }
            let searchable = ([product.name, product.brand, product.overview] + product.tags +
                specs.flatMap { [$0.specName, $0.details] }).joined(separator: " ")
            return matchesFilter && (productSearch.isEmpty || searchable.localizedCaseInsensitiveContains(productSearch))
        }
    }

    private var comparisonFieldSummary: (shown: Int, different: Int) {
        let propertyValues = [
            selectedProducts.map(\.brand),
            selectedProducts.map { $0.tags.joined(separator: ", ") },
            selectedProducts.map(\.overview),
            selectedProducts.map { $0.pictures.count.description },
            selectedProducts.map { product in
                store.reviews.filter {
                    $0.productIds.contains(product.id) ||
                        $0.productTitles.contains { $0.caseInsensitiveCompare(product.name) == .orderedSame }
                }.count.description
            }
        ]
        var different = propertyValues.filter { Set($0).count > 1 }.count
        for name in comparisonSpecifications {
            let values = selectedProducts.map {
                specification(for: $0, named: name)?.details.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            }
            if Set(values).count > 1 { different += 1 }
        }
        return (5 + comparisonSpecifications.count, different)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
            header
            productPicker

            if selectedProducts.isEmpty {
                ContentUnavailableView(
                    "No products selected",
                    systemImage: "arrow.left.arrow.right",
                    description: Text("Select products above to compare their specifications.")
                )
            } else {
                comparisonMatrixContent
            }
            }
        }
        .background(Color(uiColor: .systemGray6))
        .fullScreenCover(isPresented: Binding(
            get: { selectedComparisonImage != nil },
            set: { if !$0 { selectedComparisonImage = nil } }
        )) {
            if let selectedComparisonImage {
                ZStack(alignment: .topTrailing) {
                    Color.black.ignoresSafeArea()
                    Image(uiImage: selectedComparisonImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Button {
                        self.selectedComparisonImage = nil
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
        .confirmationDialog("Clear all comparison products?", isPresented: $confirmClearComparison, titleVisibility: .visible) {
            Button("Clear comparison", role: .destructive) {
                store.clearComparison()
                comparisonSlots = [nil, nil]
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every selected product from the comparison.")
        }
        .sheet(item: $slotPickerRequest) { request in
            CompareSlotPickerSheet(
                products: pickerProducts,
                selectedIDs: store.comparedProductIDs,
                onSelect: { product in
                    assign(product, to: request.index)
                    slotPickerRequest = nil
                }
            )
        }
        .sheet(item: $selectedReview) { review in
            ProductReviewActionsSheet(review: review, startEditing: false)
        }
        .onAppear {
            if !didInitializeSlots {
                syncSlotsFromStore()
                didInitializeSlots = true
            }
        }
        .onChange(of: store.comparedProductOrder) { _, _ in
            if didInitializeSlots, comparisonSlots.compactMap({ $0 }) != store.comparedProductOrder {
                syncSlotsFromStore()
            }
        }
    }

    private struct CompareSlotPickerRequest: Identifiable {
        let index: Int
        var id: Int { index }
    }

    private struct CompareSlotPickerSheet: View {
        @Environment(\.dismiss) private var dismiss
        let products: [Product]
        let selectedIDs: Set<String>
        let onSelect: (Product) -> Void
        @State private var searchText = ""

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
                List(filteredProducts) { product in
                    Button {
                        onSelect(product)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(product.name).font(.body.weight(.semibold))
                                Text([product.brand, product.tags.joined(separator: " • ")]
                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedIDs.contains(product.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.indigo)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .searchable(text: $searchText, prompt: "Search name, tag, or brand")
                .navigationTitle("Choose product")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Compare Products")
                    .font(.system(size: 23, weight: .bold))
                Text("Compare up to 5 products")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button {
                    sortByName.toggle()
                } label: {
                    Label(sortByName ? "Keep selection order" : "Sort by product name", systemImage: "arrow.up.arrow.down")
                }
                Button(role: .destructive) {
                    confirmClearComparison = true
                } label: {
                    Label("Clear comparison", systemImage: "trash")
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 18, weight: .semibold))
                    .padding(11)
                    .background(.white, in: Circle())
            }
            .accessibilityLabel("Comparison options")
        }
        .padding(16)
        .background(.white)
    }

    private var productPicker: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search products, brands, tags, or specs", text: $productSearch)
                    .textInputAutocapitalization(.never)
            }
            .padding(10)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
            Picker("Filter", selection: $productFilter) {
                ForEach(productFilterOptions, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            HStack {
                Text("Comparison slots")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    guard comparisonSlots.count < 5 else {
                        store.statusMessage = "You can compare up to 5 products."
                        return
                    }
                    comparisonSlots.append(nil)
                } label: {
                    Label("Add record", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
                .disabled(comparisonSlots.count >= 5)
                if !store.comparedProductOrder.isEmpty {
                    Button("Clear all", role: .destructive) {
                        confirmClearComparison = true
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            ForEach(comparisonSlots.indices, id: \.self) { index in
                comparisonSlotCard(at: index)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(pickerProducts) { product in
                        let isSelected = store.comparedProductIDs.contains(product.id)
                        Button {
                            store.toggleCompare(product.id)
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                                Text(product.name).lineLimit(1)
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : Color.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(isSelected ? Color.indigo : Color.white, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!isSelected && store.comparedProductIDs.count >= 5)
                        .opacity(!isSelected && store.comparedProductIDs.count >= 5 ? 0.5 : 1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(uiColor: .systemGray6))
    }

    @ViewBuilder
    private func comparisonSlotCard(at index: Int) -> some View {
        let productID = comparisonSlots[index]
        let product = productID.flatMap { id in store.products.first { $0.id == id } }
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("RECORD \(index + 1)")
                    .font(.caption.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer()
                if let product,
                   let orderIndex = selectedProducts.firstIndex(where: { $0.id == product.id }) {
                    Button {
                        moveComparisonProduct(at: orderIndex, offset: -1)
                    } label: {
                        Image(systemName: "arrow.up")
                            .frame(width: 30, height: 30)
                            .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(orderIndex == 0)
                    .accessibilityLabel("Move \(product.name) up")
                    Button {
                        moveComparisonProduct(at: orderIndex, offset: 1)
                    } label: {
                        Image(systemName: "arrow.down")
                            .frame(width: 30, height: 30)
                            .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(orderIndex == selectedProducts.count - 1)
                    .accessibilityLabel("Move \(product.name) down")
                }
            }
            if let product {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(product.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                        Text(product.brand.isEmpty ? "No brand" : product.brand)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button("Change") { slotPickerRequest = CompareSlotPickerRequest(index: index) }
                        .font(.caption.weight(.semibold))
                    Button {
                        removeSlot(at: index)
                    } label: {
                        Image(systemName: comparisonSlots.count > 2 ? "trash" : "xmark")
                    }
                    .tint(.red)
                    .accessibilityLabel("Remove record \(index + 1)")
                }
            } else {
                Button("Choose product") { slotPickerRequest = CompareSlotPickerRequest(index: index) }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.16), lineWidth: 1))
    }

    private func syncSlotsFromStore() {
        comparisonSlots = store.comparedProductOrder.map(Optional.some)
        while comparisonSlots.count < 2 { comparisonSlots.append(nil) }
        while comparisonSlots.count > 5 { comparisonSlots.removeLast() }
    }

    private func assign(_ product: Product, to index: Int) {
        guard comparisonSlots.indices.contains(index) else { return }
        guard !comparisonSlots.enumerated().contains(where: { $0.offset != index && $0.element == product.id }) else {
            store.statusMessage = "A product can only occupy one comparison slot."
            return
        }
        comparisonSlots[index] = product.id
        store.setComparedProductOrder(comparisonSlots.compactMap { $0 })
    }

    private func removeSlot(at index: Int) {
        guard comparisonSlots.indices.contains(index) else { return }
        if comparisonSlots.count > 2 {
            comparisonSlots.remove(at: index)
        } else {
            comparisonSlots[index] = nil
        }
        store.setComparedProductOrder(comparisonSlots.compactMap { $0 })
    }

    private func moveComparisonProduct(at index: Int, offset: Int) {
        let visibleOrder = selectedProducts.map(\.id)
        let destination = index + offset
        guard visibleOrder.indices.contains(index), visibleOrder.indices.contains(destination) else { return }
        var reordered = visibleOrder
        reordered.swapAt(index, destination)
        sortByName = false
        store.setComparedProductOrder(reordered)
        syncSlotsFromStore()
    }

    private var comparisonMatrixContent: some View {
        LazyVStack(spacing: 12) {
            productSummaryCard
            HStack {
                Text("\(comparisonFieldSummary.shown) fields shown")
                Spacer()
                Text("\(comparisonFieldSummary.different) differ")
                    .fontWeight(.semibold)
                    .foregroundStyle(comparisonFieldSummary.different == 0 ? Color.secondary : Color.orange)
            }
            .font(.caption)
            .padding(12)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            comparisonPropertyCard("Brand", value: { $0.brand.isEmpty ? "—" : $0.brand })
            comparisonPropertyCard("Tags", value: { $0.tags.isEmpty ? "—" : $0.tags.joined(separator: ", ") })
            comparisonPropertyCard("Overview", value: { $0.overview })
            comparisonPicturesCard
            comparisonReviewsCard
            ForEach(comparisonSpecifications, id: \.self) { name in
                comparisonRow(name)
            }
        }
        .padding(14)
    }

    private var productSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Products", systemImage: "shippingbox")
                .font(.headline)
                .foregroundStyle(.indigo)
            ForEach(selectedProducts.indices, id: \.self) { index in
                let product = selectedProducts[index]
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.indigo)
                        .frame(width: 26, height: 26)
                        .background(Color.indigo.opacity(0.1), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.name).font(.subheadline.weight(.semibold))
                        Text(product.brand.isEmpty ? "Other" : product.brand)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Button(role: .destructive) {
                        store.removeComparedProduct(product.id)
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .accessibilityLabel("Remove \(product.name) from comparison")
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.gray.opacity(0.14), lineWidth: 1))
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.16), lineWidth: 1))
    }

    private func comparisonPropertyCard(
        _ title: String,
        value: @escaping (Product) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: propertySymbol(for: title))
                .font(.headline)
                .foregroundStyle(.indigo)
            ForEach(selectedProducts) { product in
                VStack(alignment: .leading, spacing: 7) {
                    Text(product.name)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    let content = value(product)
                    if title == "Overview" && !content.isEmpty {
                        RichHTMLText(html: content, fontSize: 14, textColor: .label, alignment: .left)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(content.isEmpty ? "—" : content)
                            .font(.system(size: 14, weight: title == "Brand" ? .semibold : .regular))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .systemGray6), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.12), lineWidth: 1)
                }
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.14), lineWidth: 1))
    }

    private func propertySymbol(for title: String) -> String {
        switch title {
        case "Brand": return "tag"
        case "Tags": return "number"
        default: return "text.alignleft"
        }
    }

    private var comparisonPicturesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Pictures", systemImage: "photo")
                .font(.headline)
                .foregroundStyle(.indigo)
            ForEach(selectedProducts) { product in
                VStack(alignment: .leading, spacing: 6) {
                    Text(product.name.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    photoStrip(product.pictures)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.gray.opacity(0.14), lineWidth: 1))
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.16), lineWidth: 1))
    }

    private var comparisonReviewsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("User reviews", systemImage: "text.bubble")
                .font(.headline)
                .foregroundStyle(.indigo)
            ForEach(selectedProducts) { product in
                let linkedReviews = store.reviews.filter {
                    $0.productIds.contains(product.id) ||
                        $0.productTitles.contains { $0.caseInsensitiveCompare(product.name) == .orderedSame }
                }
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.name.uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text("\(linkedReviews.count) review\(linkedReviews.count == 1 ? "" : "s") available")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    Spacer(minLength: 4)
                    if let review = linkedReviews.first {
                        Button {
                            selectedReview = review
                        } label: {
                            Label("Read review", systemImage: "text.bubble")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.gray.opacity(0.14), lineWidth: 1))
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.16), lineWidth: 1))
    }

    @ViewBuilder
    private func photoStrip(_ attachments: [MediaAttachment], imageHeight: CGFloat = 140) -> some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { attachment in
                        if let url = store.localURL(for: attachment),
                           let image = UIImage(contentsOfFile: url.path) {
                            Button {
                                selectedComparisonImage = image
                            } label: {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 200, maxHeight: imageHeight)
                                    .clipShape(RoundedRectangle(cornerRadius: 9))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open photo \(attachment.name)")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func comparisonRow(_ name: String) -> some View {
        let specs = selectedProducts.map { specification(for: $0, named: name) }
        let parsed = specs.map { parseNumericValue($0, forceNumeric: numericOverrides[name] == true) }
        let numericCount = parsed.compactMap { $0 }.count
        let hasExplicitNumeric = specs.contains { $0?.isNumeric == true }
        let hasExplicitText = specs.contains { $0?.isNumeric == false }
        let autoNumeric = hasExplicitNumeric || (!hasExplicitText && numericCount >= 2)
        let numeric = numericOverrides[name] ?? autoNumeric
        let mode = bestValueModes[name] ?? .higher
        let normalizedValues = parsed.compactMap { $0 }
        let units = Set(normalizedValues.map { $0.unit.lowercased() })
        let valuesAreComparable = numeric && numericCount >= 2 && units.count <= 1
        let bestValue = valuesAreComparable
            ? (mode == .higher
                ? normalizedValues.map(\.value).max()
                : normalizedValues.map(\.value).min())
            : nil
        let distinctValues = specs.map { $0?.details.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "" }
        let differs = Set(distinctValues).count > 1

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    if differs {
                        Text("DIFFERENT")
                            .font(.system(size: 10, weight: .heavy))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.yellow.opacity(0.35), in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Button {
                        numericOverrides[name] = !numeric
                    } label: {
                        Text(numeric ? "# Numeric" : "Aa Text")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Spacer(minLength: 0)
                    if valuesAreComparable {
                        Picker("Best value", selection: Binding(
                            get: { bestValueModes[name] ?? .higher },
                            set: { bestValueModes[name] = $0 }
                        )) {
                            Text("Higher").tag(BestValueMode.higher)
                            Text("Lower").tag(BestValueMode.lower)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                    }
                }
            }
            .padding(10)
            .background(
                differs ? Color.yellow.opacity(0.2) : Color(uiColor: .systemGray6),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(selectedProducts.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedProducts[index].name.uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        comparisonValueCell(
                            specs[index],
                            parsed: parsed[index],
                            bestValue: bestValue,
                            showBars: valuesAreComparable,
                            isBest: bestValue != nil && parsed[index]?.value == bestValue
                        )
                        if let specification = specs[index], !specification.pictures.isEmpty {
                            photoStrip(specification.pictures, imageHeight: 100)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.gray.opacity(0.14), lineWidth: 1))
                }
            }
        }
        .padding(14)
        .background(differs ? Color.yellow.opacity(0.1) : Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(differs ? Color.yellow.opacity(0.45) : Color.gray.opacity(0.16)))
    }

    @ViewBuilder
    private func comparisonValueCell(
        _ specValue: Specification?,
        parsed: ParsedNumericValue?,
        bestValue: Double?,
        showBars: Bool,
        isBest: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let explicitUnit = specValue?.unit?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayUnit = explicitUnit?.isEmpty == false ? explicitUnit : parsed?.unit
            RichHTMLText(
                html: comparisonValueHTML(specValue, unit: displayUnit),
                fontSize: 14,
                textColor: isBest ? .systemIndigo : .label,
                alignment: .left
            )
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if showBars, let parsed, bestValue != nil {
                let allValues = selectedProducts.compactMap {
                    specification(for: $0, named: specValue?.specName ?? "")
                        .flatMap { parseNumericValue($0)?.value }
                }
                let range = (allValues.max() ?? 1) - (allValues.min() ?? 0)
                let fraction = range == 0 ? 1 : (parsed.value - (allValues.min() ?? 0)) / range
                let adjusted = bestValueModes[specValue?.specName ?? ""] == .lower ? 1 - fraction : fraction
                GeometryReader { proxy in
                    Capsule()
                        .fill(isBest ? Color.green : Color.indigo.opacity(0.35))
                        .frame(width: max(4, proxy.size.width * min(1, max(0, adjusted))))
                }
                .frame(height: 5)
                if isBest {
                    Label("Best", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private func comparisonValueHTML(_ specification: Specification?, unit: String?) -> String {
        guard let specification else { return "—" }
        let details = specification.details.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !details.isEmpty else { return "—" }
        let cleanUnit = unit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !cleanUnit.isEmpty, !detailsContainUnit(details, unit: cleanUnit) else { return details }
        return details + " " + RichHTMLText.unitBadgeMarker(for: cleanUnit)
    }

    private func detailsContainUnit(_ details: String, unit: String) -> Bool {
        let plainText = details
            .replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
        let escapedUnit = NSRegularExpression.escapedPattern(for: unit)
        let pattern = "(^|\\s|\\d)\(escapedUnit)(s|\\b|$)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return plainText.localizedCaseInsensitiveContains(unit)
        }
        return regex.firstMatch(in: plainText, range: NSRange(plainText.startIndex..., in: plainText)) != nil
    }

    private func specification(for product: Product, named name: String) -> Specification? {
        store.specifications
            .filter { specificationBelongs($0, to: product) }
            .sorted { $0.order < $1.order }
            .first {
                specificationNameKey($0.specName) == specificationNameKey(name)
        }
    }

    private func parseNumericValue(_ specification: Specification?, forceNumeric: Bool = false) -> ParsedNumericValue? {
        guard let specification else { return nil }
        let cleaned = specification.details
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if specification.isNumeric == false && !forceNumeric { return nil }
        if specification.isNumeric != true && (cleaned.contains("\n") || cleaned.count > 45) { return nil }

        let pattern = #"^\s*([$€£¥₹]|RM|Rm)?\s*(-?\d[\d,]*(?:\.\d+)?)\s*([^\s,;]*)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
              let numberRange = Range(match.range(at: 2), in: cleaned),
              let number = Double(cleaned[numberRange].replacingOccurrences(of: ",", with: "")) else { return nil }
        let currency = Range(match.range(at: 1), in: cleaned).map { String(cleaned[$0]) } ?? ""
        let inlineUnit = Range(match.range(at: 3), in: cleaned).map { String(cleaned[$0]) } ?? ""
        let unit = normalizeUnit(specification.unit?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? specification.unit!
            : (currency.isEmpty ? inlineUnit : currency))
        return ParsedNumericValue(value: number, unit: unit)
    }

    private func normalizeUnit(_ unit: String) -> String {
        switch unit.lowercased() {
        case "gram", "grams": "g"
        case "inches", "\"", "″": "inch"
        case "year", "years": "year"
        case "month", "months": "month"
        case "hour", "hours", "hr", "hrs": "hrs"
        case "mah": "mAh"
        case "hz": "Hz"
        default: unit
        }
    }

    private enum BestValueMode: String {
        case higher
        case lower
    }

    private struct ParsedNumericValue {
        let value: Double
        let unit: String
    }
}
