# Spoke — Workshop inventory

A phone-first Flutter inventory app for bike parts, tools and workshop supplies.

- Add, edit and delete parts with category, SKU and storage location.
- Receive or use stock with the + / − controls.
- Search by name, SKU or location and filter by category or low stock.
- Minimum stock levels flag parts that need restocking (quantity ≤ minimum).
- Inventory saves locally using shared_preferences. The first launch starts empty.

## Run

```sh
flutter pub get
flutter run
```

For a browser preview: `flutter run -d chrome`.

## Verify

```sh
flutter analyze
flutter test
flutter build web
```

Android, iOS and web projects are included. Mobile builds require their platform SDKs; iOS also requires signing for a physical device.

Data is local to the app/browser on one device. There is no cloud sync, stock history or inventory restore yet. OneDrive integration is paused and its controls are hidden from the app. Clearing app data or browser storage removes the inventory. This initial version is intended for a single workshop device.

## Reports

OneDrive sign-in and upload are paused. The app runs locally without a Microsoft account. Report-generation and integration source files remain available for future work.
