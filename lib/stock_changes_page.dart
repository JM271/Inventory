import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_inventory.dart';

/// Taps on the same part by the same person this close together are shown
/// as one entry (five taps on "−" read as "Poya −5").
const mergeWindow = Duration(minutes: 5);

const _sites = ['Poya', 'Auto', 'Garage'];

/// One recorded stock change (or several merged taps).
class StockChange {
  StockChange({
    required this.partId,
    required this.name,
    required this.action,
    required this.before,
    required this.after,
    required this.uid,
    required this.email,
    required this.time,
    this.count = 1,
  });

  factory StockChange.fromMap(Map<String, dynamic> c) {
    final raw = c['createdAt'];
    int n(Object? v) => (v as num? ?? 0).toInt();
    return StockChange(
      partId: '${c['partId'] ?? ''}',
      name: '${c['name'] ?? ''}',
      action: '${c['action'] ?? ''}',
      before: [n(c['beforeWorkshop']), n(c['beforeCar']), n(c['beforeGarage'])],
      after: [n(c['afterWorkshop']), n(c['afterCar']), n(c['afterGarage'])],
      uid: '${c['uid'] ?? ''}',
      email: '${c['email'] ?? ''}',
      time: raw is Timestamp
          ? raw.toDate().toLocal()
          : DateTime.tryParse('${raw ?? ''}')?.toLocal(),
    );
  }

  final String partId, name, action, uid, email;
  final List<int> before, after;

  /// Null while the server timestamp is still pending.
  final DateTime? time;
  final int count;

  List<int> get delta => [for (var i = 0; i < 3; i++) after[i] - before[i]];
  int get net => delta.fold(0, (a, b) => a + b);
  String get person => email.isNotEmpty ? email : uid;

  /// Earlier taps by the same person on the same part, merged into this one.
  bool canAbsorb(StockChange older, DateTime? oldestTime) =>
      action == 'Adjusted' &&
      older.action == 'Adjusted' &&
      partId.isNotEmpty &&
      older.partId == partId &&
      older.person == person &&
      oldestTime != null &&
      older.time != null &&
      oldestTime.difference(older.time!) <= mergeWindow;

  StockChange absorb(StockChange older) => StockChange(
    partId: partId,
    name: name,
    action: action,
    before: older.before,
    after: after,
    uid: uid,
    email: email,
    time: time,
    count: count + older.count,
  );

  /// What happened, in one line: "Poya −1", "Poya → Auto 2", "Neu · Poya 4".
  String get summary {
    final d = delta;
    String signed(int v) => v > 0 ? '+$v' : '−${-v}';
    final moves = [
      for (var i = 0; i < 3; i++)
        if (d[i] != 0) '${_sites[i]} ${signed(d[i])}',
    ];
    final from = [
      for (var i = 0; i < 3; i++)
        if (d[i] < 0) i,
    ];
    final to = [
      for (var i = 0; i < 3; i++)
        if (d[i] > 0) i,
    ];
    final text = switch (action) {
      'Added' || 'Imported' => [
        action == 'Added' ? 'Neu angelegt' : 'Importiert',
        for (var i = 0; i < 3; i++)
          if (after[i] != 0) '${_sites[i]} ${after[i]}',
      ].join(' · '),
      'Deleted' => ['Gelöscht', ...moves].join(' · '),
      _ when from.length == 1 && to.length == 1 && net == 0 =>
        '${_sites[from.single]} → ${_sites[to.single]} · ${d[to.single]}',
      'Edited' => ['Bearbeitet', ...moves].join(' · '),
      _ => moves.isEmpty ? 'Keine Änderung' : moves.join(' · '),
    };
    return text;
  }

  IconData get icon => switch (action) {
    'Added' || 'Imported' => Icons.add_circle_outline,
    'Deleted' => Icons.delete_outline,
    _ when net == 0 && delta.any((v) => v != 0) => Icons.swap_horiz,
    _ when net < 0 => Icons.arrow_downward,
    _ when net > 0 => Icons.arrow_upward,
    _ => Icons.remove,
  };
}

/// Newest first; merges runs of taps (see [mergeWindow]).
List<StockChange> groupChanges(List<StockChange> newestFirst) {
  final out = <StockChange>[];
  DateTime? oldest;
  for (final c in newestFirst) {
    if (out.isNotEmpty && out.last.canAbsorb(c, oldest)) {
      out[out.length - 1] = out.last.absorb(c);
    } else {
      out.add(c);
    }
    oldest = c.time;
  }
  return out;
}

enum ChangeKind { all, out, inbound, transfer }

const _kindLabels = {
  ChangeKind.all: 'Alle',
  ChangeKind.out: 'Entnommen',
  ChangeKind.inbound: 'Hinzugefügt',
  ChangeKind.transfer: 'Umgelagert',
};

bool matchesKind(StockChange c, ChangeKind kind) => switch (kind) {
  ChangeKind.all => true,
  ChangeKind.out => c.net < 0,
  ChangeKind.inbound => c.net > 0,
  ChangeKind.transfer => c.net == 0 && c.delta.any((v) => v != 0),
};

const _weekdays = ['Mo.', 'Di.', 'Mi.', 'Do.', 'Fr.', 'Sa.', 'So.'];
const _months = [
  'Jan.', 'Feb.', 'März', 'Apr.', 'Mai', 'Juni', //
  'Juli', 'Aug.', 'Sept.', 'Okt.', 'Nov.', 'Dez.',
];

String dayLabel(DateTime? d, DateTime now) {
  if (d == null) return 'Heute';
  final day = DateTime(d.year, d.month, d.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Heute';
  if (diff == 1) return 'Gestern';
  final year = d.year == now.year ? '' : ' ${d.year}';
  return '${_weekdays[d.weekday - 1]} ${d.day}. ${_months[d.month - 1]}$year';
}

class StockChangesPage extends StatefulWidget {
  const StockChangesPage({
    super.key,
    this.cloud,
    this.admin = false,
    this.partId,
    this.partName,
    this.onOpenPart,
  });
  final CloudInventory? cloud;

  /// Admins can read the user list, so older entries without an email
  /// still show who made them.
  final bool admin;

  /// Set to show only the history of one part.
  final String? partId, partName;

  /// Opens a part from an entry; null when entries are not tappable.
  final void Function(String partId)? onOpenPart;

  @override
  State<StockChangesPage> createState() => _StockChangesPageState();
}

class _StockChangesPageState extends State<StockChangesPage> {
  late final Stream<List<StockChange>> changes = _load();
  Map<String, String> emails = {};
  int? site;
  ChangeKind kind = ChangeKind.all;
  String? person;

  @override
  void initState() {
    super.initState();
    final cloud = widget.cloud;
    if (cloud != null && widget.admin) {
      cloud.db.collection('users').get().then((users) {
        if (!mounted) return;
        setState(
          () => emails = {
            for (final u in users.docs) u.id: '${u.data()['email'] ?? ''}',
          },
        );
      }, onError: (_) {});
    }
  }

  Stream<List<StockChange>> _load() {
    final cloud = widget.cloud;
    List<StockChange> sorted(Iterable<Map<String, dynamic>> rows) {
      final list = rows.map(StockChange.fromMap).toList();
      // Pending (null) timestamps are the newest.
      list.sort(
        (a, b) =>
            (b.time ?? DateTime(9999)).compareTo(a.time ?? DateTime(9999)),
      );
      return list;
    }

    if (cloud == null) {
      return Stream.fromFuture(
        SharedPreferences.getInstance().then((prefs) {
          final rows =
              (jsonDecode(prefs.getString('stock_changes_v1') ?? '[]') as List)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .where(
                    (c) =>
                        widget.partId == null ||
                        c['partId'] == widget.partId ||
                        (c['partId'] == null && c['name'] == widget.partName),
                  );
          return sorted(rows);
        }),
      );
    }
    // A plain equality query needs no composite index; sorted here.
    final query = widget.partId != null
        ? cloud.changes.where('partId', isEqualTo: widget.partId)
        : cloud.changes.orderBy('createdAt', descending: true).limit(500);
    return query.snapshots().map((s) => sorted(s.docs.map((d) => d.data())));
  }

  String personName(StockChange c) {
    String short(String email) => email.split('@').first;
    if (c.email.isNotEmpty) return short(c.email);
    if (c.uid == 'This device') return 'Dieses Gerät';
    final cloud = widget.cloud;
    if (cloud != null && c.uid == cloud.uid && cloud.email.isNotEmpty) {
      return short(cloud.email);
    }
    final known = emails[c.uid] ?? '';
    return known.isNotEmpty ? short(known) : 'Unbekannt';
  }

  Widget menuChip<T>(
    String label,
    T value,
    Map<T, String> options,
    void Function(T) onSelected,
  ) => PopupMenuButton<T>(
    initialValue: value,
    onSelected: onSelected,
    itemBuilder: (_) => [
      for (final MapEntry(:key, value: text) in options.entries)
        PopupMenuItem(value: key, child: Text(text)),
    ],
    child: Chip(
      label: Text('$label: ${options[value]}'),
      avatar: const Icon(Icons.arrow_drop_down, size: 18),
      backgroundColor: options.keys.first == value
          ? null
          : Theme.of(context).colorScheme.secondaryContainer,
    ),
  );

  Widget filters(List<StockChange> all) {
    final people = <String?, String>{null: 'Alle'};
    for (final c in all) {
      people.putIfAbsent(c.person, () => personName(c));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        spacing: 8,
        children: [
          menuChip<int?>('Ort', site, {
            null: 'Alle',
            for (var i = 0; i < 3; i++) i: _sites[i],
          }, (v) => setState(() => site = v)),
          menuChip<ChangeKind>(
            'Art',
            kind,
            _kindLabels,
            (v) => setState(() => kind = v),
          ),
          menuChip<String?>(
            'Person',
            people.containsKey(person) ? person : null,
            people,
            (v) => setState(() => person = v),
          ),
        ],
      ),
    );
  }

  Widget entries(List<StockChange> all) {
    final shown = groupChanges(all)
        .where(
          (c) =>
              (site == null || c.delta[site!] != 0) &&
              matchesKind(c, kind) &&
              (person == null || c.person == person),
        )
        .toList();
    if (all.isEmpty || shown.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            all.isEmpty
                ? 'Noch keine Bestandsänderungen.\nNeue Buchungen erscheinen hier.'
                : 'Keine Änderungen für diese Filter.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final now = DateTime.now();
    final items = <Widget>[];
    String? day;
    for (final c in shown) {
      final label = dayLabel(c.time, now);
      if (label != day) {
        day = label;
        items.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        );
      }
      items.add(
        ListTile(
          leading: Icon(c.icon),
          title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              c.summary,
              personName(c),
              if (c.count > 1) '${c.count} Buchungen',
            ].join(' · '),
          ),
          onTap: widget.onOpenPart == null || c.partId.isEmpty
              ? null
              : () => widget.onOpenPart!(c.partId),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: items,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.partName != null
            ? 'Verlauf · ${widget.partName}'
            : 'Letzte Bestandsänderungen',
        overflow: TextOverflow.ellipsis,
      ),
    ),
    body: StreamBuilder<List<StockChange>>(
      stream: changes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('Änderungen konnten nicht geladen werden.'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snapshot.data!;
        return Column(
          children: [
            if (all.isNotEmpty) filters(all),
            Expanded(child: entries(all)),
          ],
        );
      },
    ),
  );
}
