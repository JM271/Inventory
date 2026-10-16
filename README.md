# Spoke — Workshop inventory

A phone-first Flutter inventory app for bike parts, tools and workshop supplies.

- Add, edit and delete parts with category, SKU and storage location.
- Open the book icon in the app bar or choose **Aus Katalog wählen** in **Add a part** for the offline catalog: 243 products from New Image V.202605, searchable by SKU, name and category. Select a product, enter its actual quantity and save. Selecting an existing SKU opens its current stock instead of adding a duplicate.
- Catalog photos are preserved when editing and saving stock. The source has no photo for OXGT-26 and OXGT-28; those show a placeholder.
- Receive or use stock with the + / − controls.
- Search by name, SKU or location and filter by category or low stock.
- Minimum stock levels flag parts that need restocking (quantity ≤ minimum).
- Inventory saves locally using shared_preferences. On the next launch, five catalog products are added once as clearly labelled [TEST] stock. Existing SKUs are skipped; their quantities are preserved. Test items can be edited or deleted like other stock and will not return after deletion.

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

Tap **Report** in the app bar to open the current inventory as a PDF preview immediately, without Microsoft sign-in. Use the preview actions to print or share/save the PDF. Every export includes all inventory regardless of active filters. The cloud button remains available for direct OneDrive uploads.

Tap the cloud button to sign in with your personal Microsoft account, using the same device-code approach as Bike Dispatch and upload a dated Excel inventory report. Enter the Application (client) ID from a Microsoft app registration named **Inventory**. The sign-in name comes from that registration. The **workshop inventory** shared folder is prefilled and can be changed. Its setting is saved separately from the previous report destination. Your account needs edit access to that folder. Tokens stay in memory and are cleared when the report dialog closes. Reports contain a snapshot of all stock, independent of filters. This exports reports; it does not synchronize or restore inventory.

The Inventory client ID (`7398cfd4-950c-4aa3-91ea-2e092163dc78`) is prefilled and saved separately from the old inspection-app setting. You can override the default with `--dart-define=INVENTORY_MICROSOFT_CLIENT_ID=<client-id>`.

Sign-in uses Microsoft’s `/consumers` endpoint, as in Bike Dispatch, while retaining Inventory’s own client ID. In Entra, change Inventory’s **Supported account types** from organization-only to an option that includes **personal Microsoft accounts**, then save. Sign in with a personal account that has edit access to the destination folder. The Microsoft registration must support personal accounts, allow public client flows and grant delegated Files.ReadWrite access. No client secret is used. Mobile sign-in is supported; the browser build displays guidance instead. Live sign-in and uploads require verification with your Microsoft account.

## Werkstatt und Auto

Each product has separate quantities and minimum stock for Werkstatt and Auto. Existing saved quantities and minimums remain in Werkstatt; Auto starts at zero. Choose Alle / Werkstatt / Auto above the search. The stock counters and low-stock filter follow the selection. Use Umlagern to move a positive quantity between locations without changing the total. Car minimum zero disables car restocking warnings until a minimum is configured. PDF and Excel reports always include both locations and total stock, regardless of the selected filter. The free-text location remains a shelf/bin description.
