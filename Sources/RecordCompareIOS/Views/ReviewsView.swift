import SwiftUI

struct ReviewsView: View {
    @EnvironmentObject var store: ProductStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Product Reviews")
                    .font(.system(size: 28, weight: .bold))
                    .padding(.top, 18)

                ForEach(store.reviews) { review in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(review.title ?? "Review")
                            .font(.system(size: 20, weight: .bold))
                        Text(review.body)
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                        HStack {
                            ForEach(0..<max(1, review.rating ?? 0), id: \ .self) { _ in
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                }
            }
        }
    }
}
