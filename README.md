# RecordCompareIOS

This repository contains a SwiftUI app for the ProductCompare app with a UI and flow intentionally aligned to the Android version.

## What is included
- Catalog view
- Compare products view
- Smart Add Product flow
- Product reviews
- Data & Backup screen
- Local JSON storage
- Android ZIP backup import support

## How to open in Xcode
1. Open Xcode.
2. Choose `Open` and select this repository folder.
3. Xcode will recognize the Swift Package.
4. Connect an iPhone to your Mac and select it as the run destination.
5. Press Run.

## Notes
- This is the initial port and keeps data local/offline.
- Android ZIP compatibility is implemented at the data model layer, with import/export handled by the app store.
- No online backend is included.
