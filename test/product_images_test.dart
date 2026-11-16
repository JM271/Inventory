import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory/cloud_inventory.dart';
import 'package:inventory/part.dart';
import 'package:inventory/product_catalog.dart';
import 'package:inventory/product_images.dart';

/// A 1×1 PNG.
final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

Part product(String imageAsset) => Part(
  id: 'catalog-OXV8-05',
  name: '3 in 1 switch',
  category: 'Electrics',
  sku: 'OXV8-05',
  imageAsset: imageAsset,
);

Future<void> show(WidgetTester tester, Part part) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ProductPhoto(part: part)),
    ),
  );
  await tester.runAsync(() => ProductImages.load(part.imageAsset));
  await tester.pump();
}

ImageProvider shownPicture(WidgetTester tester) =>
    tester.widget<Image>(find.byType(Image)).image;

void main() {
  late CloudInventory cloud;
  setUp(() {
    cloud = CloudInventory(FakeFirebaseFirestore(), 'alice');
    ProductImages.use(cloud.productImages);
  });
  tearDown(() => ProductImages.use(null));

  testWidgets('a product shows its picture from the database', (tester) async {
    await cloud.productImages.doc('oxv8-05.png').set({
      'bytes': Blob(png),
      'contentType': 'image/png',
      'sha256': 'abc',
    });
    await show(tester, product('assets/products/OXV8-05.png'));
    final picture = shownPicture(tester);
    expect(picture, isA<MemoryImage>());
    expect((picture as MemoryImage).bytes, png);
  });

  testWidgets('without a picture in the database the bundled one is shown', (
    tester,
  ) async {
    await show(tester, product('assets/products/oxv8-05.png'));
    final picture = shownPicture(tester);
    expect(picture, isA<AssetImage>());
    expect((picture as AssetImage).assetName, 'assets/products/oxv8-05.png');
  });

  testWidgets('without Firebase the bundled picture is shown at once', (
    tester,
  ) async {
    ProductImages.use(null);
    await tester.pumpWidget(
      MaterialApp(
        home: ProductPhoto(part: product('assets/products/oxv8-05.png')),
      ),
    );
    expect(shownPicture(tester), isA<AssetImage>());
  });

  testWidgets('a product without a picture shows the placeholder', (
    tester,
  ) async {
    await show(tester, product(''));
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
  });

  test('a picture is read from the database only once', () async {
    await cloud.productImages.doc('oxv8-05.png').set({'bytes': Blob(png)});
    final first = await ProductImages.load('assets/products/oxv8-05.png');
    await cloud.productImages.doc('oxv8-05.png').delete();
    final second = await ProductImages.load('assets/products/oxv8-05.png');
    expect(first, png);
    expect(identical(first, second), isTrue);
  });
}
