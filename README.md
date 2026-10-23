# Spoke — Workshop inventory

A phone-first Flutter inventory app for bike parts, tools and workshop supplies.

**Version 2:** Firebase Authentication and shared Firestore stock for mobile and web.
Setup, first administrator and migration: [FIREBASE_SETUP.md](FIREBASE_SETUP.md).

- Add, edit and delete parts with category, SKU and storage location.
- Open the book icon in the app bar or choose **Aus Katalog wählen** in **Add a part** for the offline catalog: 243 products from New Image V.202605, searchable by SKU, name and category. Select a product, enter its actual quantity and save. Selecting an existing SKU opens its current stock instead of adding a duplicate.
- Catalog photos are preserved when editing and saving stock. The source has no photo for OXGT-26 and OXGT-28; those show a placeholder.
- Receive or use stock with the + / − controls.
- Search by name, SKU or location and filter by category or low stock.
- Minimum stock levels flag parts that need restocking (quantity ≤ minimum).
- Version 2 saves shared inventory in Firestore. Legacy local stock remains in shared_preferences until explicitly imported; the shared inventory does not receive automatic test stock.

## Run

```sh
flutter pub get
flutter run
```

## Im Browser nutzen

Die App unterstützt Android, iOS und Browser aus demselben Projekt.

```sh
flutter run -d chrome --web-hostname localhost --web-port 8080
```

Für eine lokale Vorschau des fertigen Web-Builds:

```sh
flutter build web
python3 -m http.server 8080 --directory build/web
```

Dann **http://localhost:8080** öffnen. Den Server im Terminal laufen lassen.
Für eine öffentliche Webadresse den Inhalt von `build/web` auf einem statischen
HTTPS-Webserver veröffentlichen. Bei Hosting in einem Unterordner zuerst mit
`flutter build web --base-href /unterordner/` bauen.

Version 2 verwendet das Firebase-Projekt `inventory-molenstraat`. Freigegebene
Nutzer teilen Lagerbestand und eigene Katalogprodukte zwischen Geräten und
Browsern. Anmeldung und Buchungen benötigen eine Internetverbindung.
Die bisherigen lokalen Daten bleiben erhalten und können einmalig in das noch
unbenutzte gemeinsame Lager übernommen werden. Einrichtung und Nutzerverwaltung:
[FIREBASE_SETUP.md](FIREBASE_SETUP.md).

Katalog, Lagerbearbeitung und PDF-Berichte sind im Browser verfügbar.
Für die PDF-Vorschau ist eine Internetverbindung zum Laden der PDF-Komponente
nötig; Drucken und Speichern erfolgen über die Browserfunktionen.
Microsoft-Anmeldung und OneDrive-Upload sind derzeit nur mobil unterstützt.

## Verify

```sh
flutter analyze
flutter test
flutter build web
```

Android, iOS and web projects are included. Mobile builds require their platform SDKs; iOS also requires signing for a physical device.

Shared inventory is synchronized through Firestore after sign-in and administrator approval. The OneDrive button exports reports separately; it does not synchronize inventory. Legacy local data is device/browser-specific and is removed if that local storage is cleared.

## Reports

Tap **Report** in the app bar to open the current inventory as a PDF preview immediately, without Microsoft sign-in. Use the preview actions to print or share/save the PDF. The PDF preview shows its generation time including seconds; use **PDF aktualisieren** to regenerate it from the current stock without closing the preview. Every export includes all inventory regardless of active filters. The cloud button remains available for direct OneDrive uploads.

Tap the cloud button to sign in with your personal Microsoft account, using the same device-code approach as Bike Dispatch and upload a dated Excel inventory report. Enter the Application (client) ID from a Microsoft app registration named **Inventory**. The sign-in name comes from that registration. The **workshop inventory** shared folder is prefilled and can be changed. Its setting is saved separately from the previous report destination. Your account needs edit access to that folder. The Microsoft connection is retained between report uploads and app restarts. Refresh tokens are stored in Android secure storage / iOS Keychain; access tokens stay in memory. Inventory requests offline_access and renews access automatically. Use **Abmelden / Konto wechseln** to remove the saved connection. A renewed Microsoft sign-in is only needed if the saved authorization expires or is revoked. Reports contain a snapshot of all stock, independent of filters. This exports reports; it does not synchronize or restore inventory.

The Inventory client ID (`7398cfd4-950c-4aa3-91ea-2e092163dc78`) is prefilled and saved separately from the old inspection-app setting. You can override the default with `--dart-define=INVENTORY_MICROSOFT_CLIENT_ID=<client-id>`.

Sign-in uses Microsoft’s `/consumers` endpoint, as in Bike Dispatch, while retaining Inventory’s own client ID. In Entra, change Inventory’s **Supported account types** from organization-only to an option that includes **personal Microsoft accounts**, then save. Sign in with a personal account that has edit access to the destination folder. The Microsoft registration must support personal accounts, allow public client flows and grant delegated Files.ReadWrite access. No client secret is used. Mobile sign-in is supported; the browser build displays guidance instead. Live sign-in and uploads require verification with your Microsoft account.

## Werkstatt und Auto

Each product has separate quantities and minimum stock for Werkstatt and Auto. Existing saved quantities and minimums remain in Werkstatt; Auto starts at zero. Choose Alle / Werkstatt / Auto above the search. The stock counters and low-stock filter follow the selection. Use Umlagern to move a positive quantity between locations without changing the total. Car minimum zero disables car restocking warnings until a minimum is configured. PDF and Excel reports always include both locations and total stock, regardless of the selected filter. The free-text location remains a shelf/bin description.
