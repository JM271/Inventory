import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

class PdfReportPage extends StatelessWidget {
  const PdfReportPage({super.key, required this.bytes, required this.filename});
  final Uint8List bytes;
  final String filename;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Lagerbericht · PDF')),
    body: PdfPreview(
      build: (_) async => bytes,
      pdfFileName: filename,
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      onError: (_, error) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Die PDF-Vorschau konnte nicht geladen werden. Bitte schließe den Bericht und versuche es erneut.',
          ),
        ),
      ),
    ),
  );
}
