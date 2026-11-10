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
        var names: [String] = []
        for product in selectedProducts {
            let productSpecs = store.specifications
                .filter { $0.productId == product.id || $0.productTitle == product.name }
                .sorted { $0.order < $1.order }
            for specification in productSpecs where !names.contains(where: { $0.caseInsensitiveCompare(specification.specName) == .orderedSame }) {
                names.append(specification.specName)
            }
        }
        return names
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
        HStack(spacing: 10) {
            Text("Record \(index + 1)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            if let product {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name).font(.subheadline.weight(.semibold)).lineLimit(1)
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
            } else {
                Spacer(minLength: 4)
                Button("Choose product") { slotPickerRequest = CompareSlotPickerRequest(index: index) }
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(11)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
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
            ForEach(selectedProducts) { product in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.brand.isEmpty ? "Other" : product.brand.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.indigo)
                        Text(product.name).font(.subheadline.weight(.semibold))
                    }
                    Spacer(minLength: 4)
                    Button(role: .destructive) {
                        store.removeComparedProduct(product.id)
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .accessibilityLabel("Remove \(product.name) from comparison")
                }
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private func comparisonPropertyCard(
        _ title: String,
        value: @escaping (Product) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(.indigo)
            ForEach(selectedProducts) { product in
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    let content = value(product)
                    if title == "Overview" && !content.isEmpty {
                        RichHTMLText(html: content, fontSize: 13, textColor: .label)
                    } else {
                        Text(content.isEmpty ? "—" : content)
                            .font(.system(size: 13))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
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
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
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
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(product.name.uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(linkedReviews.count) review\(linkedReviews.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let review = linkedReviews.first {
                        Text(review.title ?? "Review #\(review.reviewNumber)")
                            .font(.subheadline.weight(.semibold))
                        Text(String(repeating: "★", count: max(0, min(5, review.rating ?? 0))))
                            .font(.caption)
                            .foregroundStyle(.orange)
                        if !review.body.isEmpty {
                            RichHTMLText(html: review.body, fontSize: 13, textColor: .label)
                        }
                        photoStrip(review.pictures, imageHeight: 100)
                    } else {
                        Text("No linked reviews")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button("Open reviews") { store.selectedTab = .reviews }
                .font(.subheadline.weight(.semibold))
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
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
                Spacer()
                Button {
                    numericOverrides[name] = !numeric
                } label: {
                    Text(numeric ? "# Numeric" : "Aa Text")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
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
            .padding(10)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(selectedProducts.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedProducts[index].name.uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        comparisonValueCell(
                            specs[index],
                            parsed: parsed[index],
                            bestValue: bestValue,
                            showBars: valuesAreComparable,
                            isBest: bestValue != nil && parsed[index]?.value == bestValue
                        )
                    }
                    if let specification = specs[index], !specification.pictures.isEmpty {
                        photoStrip(specification.pictures, imageHeight: 100)
                    }
                }
            }
        }
        .padding(14)
        .background(differs ? Color.yellow.opacity(0.1) : Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.15)))
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
            RichHTMLText(html: specValue.map {
                [$0.details, $0.unit ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
            } ?? "—", fontSize: 13, textColor: isBest ? .systemIndigo : .label)
                .frame(maxWidth: .infinity, alignment: .leading)
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
        .padding(10)
    }

    private func specification(for product: Product, named name: String) -> Specification? {
        store.specifications.first {
            ($0.productId == product.id || $0.productTitle == product.name) &&
            $0.specName.caseInsensitiveCompare(name) == .orderedSame
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
