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
      tx.set(ref, next.toJson());
      if (state.data()?['initialized'] != true) {
        tx.set(workshop, {'initialized': true});
      }
    });
  }

  Future<void> adjust(String id, StockSite site, int delta) =>
      _change(id, (part) => part.adjustAt(site, delta));

  Future<void> transfer(String id, StockSite from, int amount) =>
      _change(id, (part) => part.transfer(from, amount));

  Future<void> _change(String id, void Function(Part) apply) async {
    final ref = parts.doc(documentId(id));
    await db.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      if (!snapshot.exists) {
        throw const InventoryConflict('Der Artikel wurde inzwischen gelöscht.');
      }
      final current = Part.fromJson(snapshot.data()!);
      apply(current);
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
        local.length + custom.length > 400) {
      throw const InventoryConflict(
        'Import benötigt 1 bis 400 Lager- und Katalogartikel. Bei größeren Lagern bitte zuerst die Datenübernahme vorbereiten.',
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
        if (existing.exists && !mapEquals(existing.data(), product.toJson())) {
          throw const InventoryConflict(
            'Ein Katalogprodukt mit dieser SKU existiert bereits. Import abgebrochen.',
          );
        }
        existingCustom[key] = existing.exists;
      }
      for (final part in local) {
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
