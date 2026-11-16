import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// The products' pictures in the shared database
/// (workshops/molenstraat/productImages, saved by tool/product_images): one
/// document per picture, named like the file in a product's imageAsset, so
/// "assets/products/oxv8-13.png" finds the document "oxv8-13.png".
///
/// A picture is read once and kept until the app is closed or another
/// account signs in. Without a picture in the database (or without a
/// connection) the caller shows the picture bundled with the app.
class ProductImages {
  static CollectionReference<Map<String, dynamic>>? _source;
  static final _loaded = <String, Future<Uint8List?>>{};

  /// Whether pictures are read from the database (signed in to Firebase).
  static bool get enabled => _source != null;

  /// Sets where pictures are read from; null when signed out.
  static void use(CollectionReference<Map<String, dynamic>>? source) {
    _source = source;
    _loaded.clear();
  }

  /// The document name of [imageAsset]: its file name in lower case.
  static String nameOf(String imageAsset) =>
      imageAsset.split('/').last.trim().toLowerCase();

  /// The picture saved for [imageAsset], or null when there is none or it
  /// could not be read.
  static Future<Uint8List?> load(String imageAsset) {
    final source = _source;
    final name = nameOf(imageAsset);
    if (source == null || name.isEmpty) return SynchronousFuture(null);
    return _loaded[name] ??= _read(source, name);
  }

  static Future<Uint8List?> _read(
    CollectionReference<Map<String, dynamic>> source,
    String name,
  ) async {
    try {
      final bytes = (await source.doc(name).get()).data()?['bytes'];
      if (bytes is Blob && bytes.bytes.isNotEmpty) return bytes.bytes;
      if (bytes is Uint8List && bytes.isNotEmpty) return bytes;
    } on Exception catch (e) {
      debugPrint('Product picture $name: $e');
    }
    return null;
  }
}
