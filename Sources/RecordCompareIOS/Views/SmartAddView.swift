import SwiftUI

struct SmartAddView: View {
    @EnvironmentObject var store: ProductStore

    @State private var title = ""
    @State private var brand = ""

    var body: some View {
        VStack(spacing: 18) {
            Text("Smart Add Product")
                .font(.system(size: 28, weight: .bold))
                .padding(.top)

            VStack(alignment: .leading, spacing: 12) {
                Text("Product name")
                    .font(.system(size: 15, weight: .semibold))
                TextField("e.g. Sony PX470", text: $title)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Text("Brand")
                    .font(.system(size: 15, weight: .semibold))
                TextField("e.g. Sony", text: $brand)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)

            Button {
                let product = Product(
                    id: UUID().uuidString,
                    name: title.isEmpty ? "New product" : title,
                    brand: brand.isEmpty ? "Unknown" : brand,
                    tags: [brand, "Smart Add"],
                    overview: "Created using Smart Add flow.",
                    pictures: []
                )
                store.products.insert(product, at: 0)
                title = ""
                brand = ""
            } label: {
                Text("Add Product")
                    .font(.system(size: 20, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.indigo)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal)

            Spacer()
        }
    }
}
