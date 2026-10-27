import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_inventory.dart';

class StockChangesPage extends StatelessWidget {
  const StockChangesPage({super.key, this.cloud});
  final CloudInventory? cloud;

  Future<List<Map<String, dynamic>>> localChanges() async {
    final prefs = await SharedPreferences.getInstance();
    return (jsonDecode(prefs.getString('stock_changes_v1') ?? '[]') as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Widget entries(List<Map<String, dynamic>> changes) {
    if (changes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No stock changes recorded yet.\nNew changes will appear here.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: changes.length,
      itemBuilder: (context, index) {
        final c = changes[index];
        final raw = c['createdAt'];
        final date = raw is Timestamp
            ? raw.toDate().toLocal()
            : DateTime.tryParse('$raw')?.toLocal();
        final time = date == null
            ? 'Saving…'
            : '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${c['name']}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if ((c['productNumber'] ?? '') != '')
                  Text('Product ID: ${c['productNumber']}'),
                Text('${c['action']} · $time'),
                const SizedBox(height: 8),
                Text(
                  'Werkstatt: ${c['beforeWorkshop']} → ${c['afterWorkshop']}',
                ),
                Text('Auto: ${c['beforeCar']} → ${c['afterCar']}'),
                const SizedBox(height: 8),
                Text(
                  'User: ${c['uid']}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Recent stock changes')),
    body: cloud != null
        ? StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: cloud!.changes
                .orderBy('createdAt', descending: true)
                .limit(200)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text(
                    'Could not load stock changes. Please try again.',
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return entries(snapshot.data!.docs.map((d) => d.data()).toList());
            },
          )
        : FutureBuilder<List<Map<String, dynamic>>>(
            future: localChanges(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text('Could not load stock changes.'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return entries(snapshot.data!);
            },
          ),
  );
}
