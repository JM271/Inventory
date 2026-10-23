# Firebase – Inventory Version 2

Projekt: **inventory-molenstraat**. Gemeinsames Lager: **Molenstraat**.
Die Web-App und die Android-App (`ch.jonas.inventory`) sind registriert; die öffentlichen Web-Konfigurationswerte stehen in
`lib/firebase_config.dart`. Diese Werte sind keine geheimen Zugangsdaten.
Der Schutz der Daten erfolgt über Authentication und die Firestore-Regeln.

## Einmalige Einrichtung im Firebase-Projekt

1. Unter **Authentication → Anmeldemethode** E-Mail/Passwort aktivieren.
2. Unter **Firestore Database** eine Datenbank **(default)** im Produktionsmodus
   anlegen. Den europäischen Standort bewusst auswählen.
3. Unter **Firestore Database → Regeln** den vollständigen Inhalt von
   [`firestore.rules`](firestore.rules) einsetzen und veröffentlichen.
   Keine pauschalen Regeln wie `allow read, write: if true` verwenden.
4. Die App lokal starten:

   ```sh
   flutter pub get
   flutter run -d chrome --web-hostname localhost --web-port 8080
   ```

5. In der App **Neues Konto anlegen** auswählen und das eigene Konto erstellen.
   Es erscheint **Freigabe ausstehend** mit der Benutzer-ID (UID).
6. Den ersten Administrator einmalig in der Firebase Console unter
   **Firestore Database → Daten** anlegen:

   - Sammlung `workshops`, Dokument-ID `molenstraat`.
   - Falls die Console ein Feld für das übergeordnete Dokument verlangt:
     `initialized` vom Typ **boolean** auf `false` setzen.
   - Darunter Sammlung `members`, Dokument-ID **die eigene UID**.
   - Feld `role`, Typ **string**, Wert `admin`.

   Nur der erste Admin wird so eingerichtet. Niemals `initialized` nachträglich
   zurücksetzen. Die App wechselt bei bestehender Internetverbindung automatisch
   von der Freigabeansicht zum Lager.

## Weitere Nutzer

Nutzer erstellen jeweils ein eigenes Konto über die App. Danach kann ein Admin
über **Kontosymbol → Nutzer verwalten** die registrierte E-Mail als **Mitarbeiter**
oder **Admin** freigeben und den Zugriff wieder entziehen. Die Registrierung
allein gibt keinen Zugriff auf Lager und Katalog. Es gibt keine Möglichkeit,
sich selbst zum Admin zu machen. Eigene Rechte können in der App nicht entzogen
werden, damit der letzte Admin nicht versehentlich seinen Zugang verliert.
Das Entziehen einer Mitgliedschaft löscht nicht das Authentication-Konto.

## Vorhandenen Bestand übernehmen

Auf dem Gerät bzw. im Browserprofil mit den bisherigen lokalen Daten anmelden.
Als Admin **Kontosymbol → Lokalen Bestand übernehmen** wählen und die angezeigten
Anzahlen prüfen. Der Import übernimmt Lagerartikel und eigene Katalogprodukte
in einer Transaktion, nur solange das gemeinsame Lager noch nie verwendet wurde.
`[TEST]`-Lagerartikel werden ausgelassen. Die lokalen Daten bleiben unverändert.
Maximal 400 Lager- und Katalogartikel können zusammen übernommen werden.

Den Import vor dem Anlegen des ersten gemeinsamen Lagerartikels durchführen.
Eine wiederholte Übernahme, auch nach Löschen aller gemeinsamen Lagerartikel,
wird verweigert. Unterschiedliche lokale Bestände mehrerer Geräte werden nicht
automatisch zusammengeführt.

## Android und iOS verbinden

Android ist bereits über `lib/firebase_config.dart` konfiguriert; die
zugehörige Datei liegt in `android/app/google-services.json`. Das Pixel kann
ohne zusätzliche Dart-Defines gestartet werden. Für iOS fehlt noch die Registrierung.


Beide Apps müssen **im selben Firebase-Projekt** registriert werden:

- Android: Paketname `ch.jonas.inventory`.
- iOS: Bundle-ID `ch.jonas.inventory`.

Die zugehörigen Werte aus `google-services.json` bzw. `GoogleService-Info.plist`
als öffentliche App-Konfiguration übergeben. Nicht die Web-App-ID für mobile Apps
verwenden. Ohne passende App-ID zeigt die iOS-App eine Einrichtungsansicht.

```sh
flutter run -d <device-id> \
  --dart-define=FIREBASE_APP_ID=<mobile-app-id> \
  --dart-define=FIREBASE_API_KEY=<api-key-der-mobilen-app> \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=39036121879
```

Die Initialisierung erfolgt explizit über `FirebaseOptions` in Dart. Für diese
E-Mail/Passwort-Anmeldung sind keine Google-Anmeldedienste oder Analytics nötig.
Die Android-Konfiguration wurde mit der gelieferten `google-services.json`
abgeglichen. Die iOS-Konfiguration fehlt noch. iOS-Builds benötigen zusätzlich
CocoaPods und die iOS-Werkzeuge.

## Web veröffentlichen

Firebase CLI installieren und auf dem eigenen Rechner mit `firebase login`
anmelden. Danach:

```sh
flutter build web
firebase deploy --only firestore:rules,hosting --project inventory-molenstraat
```

`firebase.json` enthält Firestore-Regeln und eine Hosting-Konfiguration für
`build/web`. Eine öffentliche Bereitstellung erfolgt erst durch diesen Deploy.
Die registrierten Domains können unter **Authentication → Einstellungen →
Autorisierte Domains** geprüft werden. Bei einer eigenen Domain diese ergänzen.

## Verhalten der Synchronisierung

- Handy und Web verwenden dieselben Konten und Firestore-Dokumente.
- Änderungen werden über Firestore-Listener empfangen.
- Plus/Minus und Umlagern lesen den aktuellen Serverbestand in einer
  Transaktion. Überbuchungen werden abgewiesen; Umlagern bleibt atomar.
- Beim Bearbeiten/Löschen wird geprüft, ob der Artikel seit dem Öffnen geändert
  wurde. Bei Konflikten bleibt der Serverbestand erhalten; Artikel erneut öffnen.
- Schreiben und die Prüfung der Mitgliedschaft benötigen Internet.
  Keine Offline-Buchungswarteschlange: unbestätigte Transaktionen werden nicht
  als gespeichert angezeigt. Der Firestore-Festplattencache ist deaktiviert.
- Lokale V1-Daten werden nicht als gemeinsamer Bestand angezeigt und nicht
  automatisch hochgeladen. Im produktiven Einstieg gibt es keinen automatischen
  Rückfall auf ein lokales Lager.
- Der mitgelieferte Produktkatalog bleibt ein App-Asset; eigene neue Produkte
  werden gemeinsam in Firestore gespeichert. Geöffnete Katalogansichten erhalten
  Aktualisierungen. Bestandsberichte verwenden den aktuell angezeigten Bestand.

## Prüfungen

```sh
flutter analyze
flutter test
flutter build web
```

`test/cloud_inventory_test.dart` prüft die Datenzugriffe mit einer lokalen
Firestore-Nachbildung. Diese Tests beweisen keine echte Anmeldung oder
Synchronisierung im Firebase-Projekt. `cloud_firestore` und dessen
Plattforminterface sind für die Kompatibilität mit dieser Testbibliothek gepinnt.
Für einen Live-Test nach Veröffentlichung der Regeln dieselben Konten in zwei
Browserprofilen anmelden, eine Buchung vornehmen und die Gegenstelle prüfen.
Zusätzlich einen nicht freigegebenen Nutzer prüfen: Er darf keine Lagerdaten
lesen oder ändern.

Die echten Firestore-Regeln können zusätzlich im lokalen Emulator geprüft werden
(Node.js und Java 21 oder neuer erforderlich):

```sh
cd tool/firebase_rules
npm install
npm test
```

Diese Tests verwenden ausschließlich das Demo-Projekt `demo-inventory`; sie
ändern keine Daten im Firebase-Projekt `inventory-molenstraat`.
