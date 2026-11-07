import SwiftUI

struct DataBackupView: View {
    @EnvironmentObject var store: ProductStore

    var body: some View {
        VStack(spacing: 18) {
            Text("Data & Backup")
                .font(.system(size: 28, weight: .bold))
                .padding(.top, 18)

            VStack(spacing: 14) {
                Button {
                    store.saveBackupToDocuments()
                } label: {
                    Text("Export Backup")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.indigo)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Button {
                    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    if let backupURL = try? documents.appendingPathComponent("backup.json") {
                        print("Backup saved at: \(backupURL)")
                    }
                } label: {
                    Text("Import Backup")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.gray.opacity(0.12))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                Text("Current summary")
                    .font(.system(size: 16, weight: .bold))
                Text("Products: \(store.products.count)")
                Text("Specifications: \(store.specifications.count)")
                Text("Reviews: \(store.reviews.count)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)

            Spacer()
        }
    }
}
