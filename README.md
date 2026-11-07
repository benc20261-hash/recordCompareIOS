# RecordCompareIOS

A native SwiftUI iOS port of ProductCompare. The goal is to preserve the Android app's five modules and interaction patterns: Catalog, Compare Products, Smart Add Product, Product Reviews, and Data & Backup.

## Open and run
Open `RecordCompareIOS.xcodeproj` on a Mac with Xcode, choose the `RecordCompareIOS` scheme, connect an iPhone, select it as the run destination, and press **Run**. Set your Apple ID under **Signing & Capabilities** if Xcode asks. The project targets iOS 17 or later.

You can also download the repository as a ZIP from GitHub and open the `.xcodeproj` inside it. GitHub stores the source project; it does not install the app directly onto an iPhone.

## Current status
This is an in-progress port. The native project and initial catalog/comparison UI are in place. The Android ZIP archive import/export, durable local persistence, and feature-level parity are still being implemented and tested. No server-based sync is planned; app data is intended to remain local to the device.
