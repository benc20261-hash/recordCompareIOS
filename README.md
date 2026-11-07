# RecordCompareIOS

Native SwiftUI iOS port of ProductCompare, targeting iOS 17+. Open `RecordCompareIOS.xcodeproj` on a Mac with Xcode, connect an iPhone, select it as the run destination, and press **Run**. Set your Apple ID under **Signing & Capabilities** if prompted.

The app is offline-first and stores its catalog on-device. Data & Backup imports Android ProductCompare ZIP archives (`database.json` plus media folders) or raw JSON; export creates a ZIP archive with the manifest, database, and media. Restore replaces local data after confirmation.

The project uses ZIPFoundation for ZIP archive handling. It is an in-progress port; Android's UI and behavior are references, while platform-specific SwiftUI adaptations are necessary.
