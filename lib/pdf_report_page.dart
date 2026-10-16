import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

class PdfReportSnapshot {
  const PdfReportSnapshot({
    required this.bytes,
    required this.filename,
    required this.generatedAt,
  });
  final Uint8List bytes;
  final String filename;
  final DateTime generatedAt;
}

class PdfReportPage extends StatefulWidget {
  const PdfReportPage({
    super.key,
    required this.initialReport,
    required this.onRefresh,
    this.previewBuilder,
  });
  final PdfReportSnapshot initialReport;
  final Future<PdfReportSnapshot> Function() onRefresh;
  final Widget Function(PdfReportSnapshot)? previewBuilder;

  @override
  State<PdfReportPage> createState() => _PdfReportPageState();
}

class _PdfReportPageState extends State<PdfReportPage> {
  late PdfReportSnapshot report = widget.initialReport;
  bool refreshing = false;
  int revision = 0;

  Future<void> refresh() async {
    if (refreshing) return;
    setState(() => refreshing = true);
    try {
      final updated = await widget.onRefresh();
      if (!mounted) return;
      setState(() {
        report = updated;
        revision++;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Aktualisierung fehlgeschlagen. Der vorherige Bericht bleibt geöffnet. Bitte erneut versuchen.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = report.generatedAt.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${two(date.day)}.${two(date.month)}.${date.year} ${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lagerbericht · PDF'),
        actions: [
          IconButton(
            tooltip: 'PDF aktualisieren',
            onPressed: refreshing ? null : refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              refreshing ? 'Bericht wird aktualisiert…' : 'Datenstand: $stamp',
            ),
          ),
          Expanded(
            child: refreshing
                ? const Center(child: CircularProgressIndicator())
                : KeyedSubtree(
                    key: ValueKey(revision),
                    child:
                        widget.previewBuilder?.call(report) ??
                        PdfPreview(
                          build: (_) async => report.bytes,
                          pdfFileName: report.filename,
                          canChangePageFormat: false,
                          canChangeOrientation: false,
                          canDebug: false,
                          onError: (_, error) => const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Die PDF-Vorschau konnte nicht geladen werden. Bitte auf Aktualisieren tippen.',
                              ),
                            ),
                          ),
                        ),
                  ),
          ),
        ],
      ),
    );
  }
}
