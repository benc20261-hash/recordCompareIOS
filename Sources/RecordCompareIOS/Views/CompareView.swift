import SwiftUI

struct CompareView: View {
    @EnvironmentObject var store: ProductStore

    var body: some View {
        VStack {
            Text("Compare Products")
                .font(.system(size: 28, weight: .bold))
                .padding(.top, 18)

            ScrollView {
                VStack(spacing: 18) {
                    ForEach(Array(store.products.enumerated()), id: \ .element.id) { index, product in
                        let isSelected = store.comparedProductIDs.contains(product.id)
                        HStack {
                            Text("\(index + 1). \(product.name)")
                                .font(.system(size: 17, weight: .semibold))
                            Spacer()
                            Button(isSelected ? "Selected" : "Add to compare") {
                                if isSelected {
                                    store.comparedProductIDs.remove(product.id)
                                } else {
                                    store.comparedProductIDs.insert(product.id)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
