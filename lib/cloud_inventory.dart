import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'part.dart';

class InventoryConflict implements Exception {
  const InventoryConflict(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Checks the version displayed when an editor/delete dialog was opened.
void checkUnchanged(Part? current, Part? expected) {
  if ((current == null) != (expected == null) ||
      (current != null && !mapEquals(current.toJson(), expected!.toJson()))) {
    throw const InventoryConflict(
      'Der Artikel wurde inzwischen geändert. Bitte erneut öffnen.',
    );
  }
}

class CloudInventory {
  CloudInventory(this.db, this.uid);
  final FirebaseFirestore db;
  final String uid;
  static const workshopId = 'molenstraat';
  DocumentReference<Map<String, dynamic>> get workshop =>
      db.collection('workshops').doc(workshopId);
  CollectionReference<Map<String, dynamic>> get parts =>
      workshop.collection('parts');
  CollectionReference<Map<String, dynamic>> get catalog =>
      workshop.collection('catalog');
  CollectionReference<Map<String, dynamic>> get members =>
      workshop.collection('members');

  CollectionReference<Map<String, dynamic>> get changes =>
      workshop.collection('stockChanges');

  void recordChange(Transaction tx, Part? before, Part? after, String action) {
    if (before != null &&
        after != null &&
        before.quantity == after.quantity &&
        before.carQuantity == after.carQuantity) {
      return;
    }
    final part = after ?? before!;
    tx.set(changes.doc(), {
      'partId': part.id,
      'name': part.name,
      'productNumber': part.productIdentification,
      'action': action,
      'beforeWorkshop': before?.quantity ?? 0,
      'afterWorkshop': after?.quantity ?? 0,
      'beforeCar': before?.carQuantity ?? 0,
      'afterCar': after?.carQuantity ?? 0,
      'uid': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // Encoding keeps legacy IDs (including SKU slashes) safe as document IDs.
  static String documentId(String id) =>
      base64Url.encode(utf8.encode(id)).replaceAll('=', '');

  Stream<DocumentSnapshot<Map<String, dynamic>>> get membership =>
      members.doc(uid).snapshots(includeMetadataChanges: true);

  Future<void> savePart(Part next, {Part? expected}) async {
    final ref = parts.doc(documentId(next.id));
    await db.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      final state = await tx.get(workshop);
      checkUnchanged(
        snapshot.exists ? Part.fromJson(snapshot.data()!) : null,
        expected,
      );
      recordChange(tx, expected, next, expected == null ? 'Added' : 'Edited');
      tx.set(ref, next.toJson());
      if (state.data()?['initialized'] != true) {
        tx.set(workshop, {'initialized': true});
      }
    });
  }

  Future<void> adjust(String id, StockSite site, int delta) =>
      _change(id, (part) => part.adjustAt(site, delta), 'Adjusted');

  Future<void> transfer(String id, StockSite from, int amount) =>
      _change(id, (part) => part.transfer(from, amount), 'Transferred');

  Future<void> _change(
    String id,
    void Function(Part) apply,
    String action,
  ) async {
    final ref = parts.doc(documentId(id));
    await db.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      if (!snapshot.exists) {
        throw const InventoryConflict('Der Artikel wurde inzwischen gelöscht.');
      }
      final current = Part.fromJson(snapshot.data()!);
      final before = Part.fromJson(current.toJson());
      apply(current);
      recordChange(tx, before, current, action);
      tx.set(ref, current.toJson());
    });
  }

  Future<void> deletePart(Part expected) async {
    final ref = parts.doc(documentId(expected.id));
    await db.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      checkUnchanged(
        snapshot.exists ? Part.fromJson(snapshot.data()!) : null,
        expected,
      );
      recordChange(tx, expected, null, 'Deleted');
      tx.delete(ref);
    });
  }

  /// First-use import only; the same workspace marker is written by all creates.
  /// A competing first edit/import therefore retries and cannot overwrite stock.
  Future<void> importLocal(
    List<Part> local, {
    List<Part> custom = const [],
  }) async {
    if (local.length + custom.length == 0 ||
        local.length * 2 + custom.length > 400) {
      throw const InventoryConflict(
        'Import benötigt mindestens einen Artikel und erlaubt maximal 400 Schreibvorgänge (zwei pro Lagerartikel inklusive Verlauf, einen pro Katalogartikel). Bei größeren Lagern bitte zuerst die Datenübernahme vorbereiten.',
      );
    }
    if (local.map((p) => p.id).toSet().length != local.length) {
      throw const InventoryConflict(
        'Die lokalen Daten enthalten doppelte IDs.',
      );
    }
    await db.runTransaction((tx) async {
      final state = await tx.get(workshop);
      if (state.data()?['initialized'] == true) {
        throw const InventoryConflict(
          'Das gemeinsame Lager wurde bereits verwendet. Import abgebrochen; kein Bestand wurde überschrieben.',
        );
      }
      final existingCustom = <String, bool>{};
      for (final product in custom) {
        final key = documentId(product.sku.trim().toLowerCase());
        if (existingCustom.containsKey(key)) {
          throw const InventoryConflict('Doppelte SKU im lokalen Katalog.');
        }
        final existing = await tx.get(catalog.doc(key));
        if (existing.exists &&
            !mapEquals(
              Part.fromJson(existing.data()!).toJson(),
              product.toJson(),
            )) {
          throw const InventoryConflict(
            'Ein Katalogprodukt mit dieser SKU existiert bereits. Import abgebrochen.',
          );
        }
        existingCustom[key] = existing.exists;
      }
      for (final part in local) {
        recordChange(tx, null, part, 'Imported');
        tx.set(parts.doc(documentId(part.id)), part.toJson());
      }
      for (final product in custom) {
        final key = documentId(product.sku.trim().toLowerCase());
        if (!existingCustom[key]!) tx.set(catalog.doc(key), product.toJson());
      }
      tx.set(workshop, {'initialized': true});
    });
  }

  Future<void> saveCatalogProduct(Part part) async {
    // A normalized SKU is the key so simultaneous creates cannot duplicate it.
    final ref = catalog.doc(documentId(part.sku.trim().toLowerCase()));
    await db.runTransaction((tx) async {
      if ((await tx.get(ref)).exists) {
        throw const InventoryConflict('Diese SKU ist bereits im Katalog.');
      }
      tx.set(ref, part.toJson());
    });
  }
}

class CloudInventoryScope extends InheritedWidget {
  const CloudInventoryScope({
    super.key,
    required this.store,
    required super.child,
  });
  final CloudInventory store;
  static CloudInventory? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CloudInventoryScope>()?.store;
  @override
  bool updateShouldNotify(CloudInventoryScope oldWidget) =>
      store != oldWidget.store;
}
