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

Data is local to the app/browser on one device. There is no cloud sync, stock history or inventory restore yet. OneDrive report export is available from the cloud button in the app bar. Clearing app data or browser storage removes the inventory. This initial version is intended for a single workshop device.

## Reports

Tap the cloud button to sign in with a personal Microsoft account and upload a dated Excel inventory report. The Bike Dispatch public client ID and shared folder are prefilled; both can be changed. Your account needs edit access to that folder. Tokens stay in memory and are cleared when the report dialog closes. Reports contain a snapshot of all stock, independent of filters. This exports reports; it does not synchronize or restore inventory.

The Microsoft registration must support personal accounts, allow public client flows and grant delegated Files.ReadWrite access. No client secret is used. Mobile sign-in is supported; the browser build displays guidance instead. Live sign-in and uploads require verification with your Microsoft account.
