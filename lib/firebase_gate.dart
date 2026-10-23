import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cloud_inventory.dart';
import 'firebase_config.dart';

String cloudError(Object error) {
  if (error is InventoryConflict) return error.message;
  if (error is ArgumentError) return 'Die verfügbare Menge reicht nicht aus.';
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' =>
        'Keine Berechtigung. Bitte Freigabe und Datenbankregeln prüfen.',
      'unavailable' || 'network-request-failed' || 'deadline-exceeded' => 'Keine Verbindung. Die Änderung wurde nicht bestätigt. Bitte erneut versuchen.',
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' ||
      'invalid-email' => 'E-Mail oder Passwort ungültig.',
      'email-already-in-use' => 'Für diese E-Mail besteht bereits ein Konto.',
      'weak-password' =>
        'Bitte ein stärkeres Passwort wählen (mindestens 6 Zeichen).',
      'too-many-requests' =>
        'Zu viele Versuche. Bitte später erneut versuchen.',
      'operation-not-allowed' =>
        'E-Mail/Passwort muss zuerst in Firebase aktiviert werden.',
      _ => 'Vorgang fehlgeschlagen (${error.code}). Bitte erneut versuchen.',
    };
  }
  return 'Vorgang fehlgeschlagen. Bitte erneut versuchen.';
}

class FirebaseGate extends StatefulWidget {
  const FirebaseGate({super.key, required this.inventoryBuilder});
  final Widget Function(CloudInventory store, bool admin) inventoryBuilder;
  @override
  State<FirebaseGate> createState() => _FirebaseGateState();
}

class _FirebaseGateState extends State<FirebaseGate> {
  late Future<void> initialization = initialize();
  Future<void> initialize() async {
    if (!InventoryFirebaseConfig.configured) {
      throw StateError(
        'Firebase-Konfiguration fehlt. Bitte zuerst die Apps im Projekt inventory-molenstraat registrieren und die Konfiguration hinterlegen.',
      );
    }
    await Firebase.initializeApp(options: InventoryFirebaseConfig.options);
    // Prevent stock from a previous account being kept in a persistent cache.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: initialization,
    builder: (context, init) {
      if (init.hasError) {
        return Scaffold(
          appBar: AppBar(title: const Text('Spoke · Firebase einrichten')),
          body: const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Firebase ist noch nicht verbunden. Bitte die App-Konfiguration für inventory-molenstraat hinterlegen. Die bisherigen lokalen Daten bleiben gespeichert. Anleitung: FIREBASE_SETUP.md im Projekt.',
            ),
          ),
        );
      }
      if (init.connectionState != ConnectionState.done) return const _Loading();
      return StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, auth) {
          if (auth.hasError) {
            return const _Message(
              'Anmeldestatus konnte nicht geladen werden. Bitte App neu starten.',
            );
          }
          if (auth.connectionState == ConnectionState.waiting) {
            return const _Loading();
          }
          if (auth.data == null) return const LoginPage();
          return _MembershipGate(
            key: ValueKey(auth.data!.uid),
            user: auth.data!,
            inventoryBuilder: widget.inventoryBuilder,
          );
        },
      );
    },
  );
}

class _MembershipGate extends StatefulWidget {
  const _MembershipGate({
    super.key,
    required this.user,
    required this.inventoryBuilder,
  });
  final User user;
  final Widget Function(CloudInventory, bool) inventoryBuilder;
  @override
  State<_MembershipGate> createState() => _MembershipGateState();
}

class _MembershipGateState extends State<_MembershipGate> {
  late final store = CloudInventory(
    FirebaseFirestore.instance,
    widget.user.uid,
  );
  late final membership = store.membership;
  late final Future<void> profile = FirebaseFirestore.instance
      .collection('users')
      .doc(widget.user.uid)
      .set({'email': widget.user.email ?? ''});

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: profile,
    builder: (context, registered) {
      if (registered.hasError) return _Message(cloudError(registered.error!));
      if (registered.connectionState != ConnectionState.done) {
        return const _Loading();
      }
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: membership,
        builder: (context, snapshot) {
          if (snapshot.hasError) return _Message(cloudError(snapshot.error!));
          if (!snapshot.hasData) return const _Loading();
          if (snapshot.data!.metadata.isFromCache) {
            return const _Message(
              'Verbindung wird hergestellt. Für die Prüfung deiner Freigabe wird Internet benötigt.',
            );
          }
          final role = snapshot.data!.data()?['role'];
          if (role != 'admin' && role != 'editor') {
            return Scaffold(
              appBar: AppBar(
                title: const Text('Freigabe ausstehend'),
                actions: [
                  IconButton(
                    tooltip: 'Abmelden',
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    icon: const Icon(Icons.logout),
                  ),
                ],
              ),
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.user.email ?? ''),
                    const SizedBox(height: 16),
                    const Text(
                      'Dein Konto ist angelegt. Ein Administrator muss dich noch für das Lager Molenstraat freigeben.',
                    ),
                    const SizedBox(height: 16),
                    SelectableText('Benutzer-ID: ${widget.user.uid}'),
                    TextButton.icon(
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: widget.user.uid),
                      ),
                      icon: const Icon(Icons.copy),
                      label: const Text('Benutzer-ID kopieren'),
                    ),
                  ],
                ),
              ),
            );
          }
          return CloudInventoryScope(
            store: store,
            child: Navigator(
              key: ValueKey('${widget.user.uid}-$role'),
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => widget.inventoryBuilder(store, role == 'admin'),
              ),
            ),
          );
        },
      );
    },
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  final form = GlobalKey<FormState>();
  bool register = false, busy = false;
  String? error, message;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit({bool reset = false}) async {
    if (busy || (!reset && !form.currentState!.validate())) return;
    if (reset && !email.text.contains('@')) {
      setState(() => error = 'Bitte zuerst deine E-Mail-Adresse eingeben.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
      message = null;
    });
    try {
      final auth = FirebaseAuth.instance;
      if (reset) {
        await auth.sendPasswordResetEmail(email: email.text.trim());
        if (mounted) {
          setState(
            () => message = 'Falls ein Konto existiert, erhältst du eine E-Mail zum Zurücksetzen.',
          );
        }
      } else if (register) {
        await auth.createUserWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );
      } else {
        await auth.signInWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = cloudError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Spoke · Molenstraat')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Form(
          key: form,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                register ? 'Konto anlegen' : 'Anmelden',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: email,
                enabled: !busy,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'E-Mail'),
                validator: (v) =>
                    v != null && v.contains('@') ? null : 'E-Mail eingeben',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: password,
                enabled: !busy,
                obscureText: true,
                autofillHints: [
                  register ? AutofillHints.newPassword : AutofillHints.password,
                ],
                decoration: const InputDecoration(labelText: 'Passwort'),
                validator: (v) =>
                    (v?.length ?? 0) >= 6 ? null : 'Mindestens 6 Zeichen',
                onFieldSubmitted: (_) => submit(),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(message!),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: busy ? null : submit,
                child: Text(
                  busy
                      ? 'Bitte warten…'
                      : register
                      ? 'Konto anlegen'
                      : 'Anmelden',
                ),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        register = !register;
                        error = null;
                        message = null;
                      }),
                child: Text(
                  register
                      ? 'Bereits ein Konto? Anmelden'
                      : 'Neues Konto anlegen',
                ),
              ),
              TextButton(
                onPressed: busy ? null : () => submit(reset: true),
                child: const Text('Passwort vergessen?'),
              ),
              if (register)
                const Text(
                  'Neue Konten benötigen die Freigabe eines Administrators, bevor sie Lagerdaten sehen können.',
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class UsersPage extends StatefulWidget {
  const UsersPage({super.key, required this.store});
  final CloudInventory store;
  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  bool busy = false;
  Future<void> change(String uid, String? role) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final ref = widget.store.members.doc(uid);
      if (role == null) {
        await ref.delete();
      } else {
        await ref.set({'role': role});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(cloudError(e))));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nutzer verwalten')),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.store.db.collection('users').snapshots(),
      builder: (context, users) {
        if (users.hasError) {
          return Center(child: Text(cloudError(users.error!)));
        }
        if (!users.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: widget.store.members.snapshots(),
          builder: (context, members) {
            if (members.hasError) {
              return Center(child: Text(cloudError(members.error!)));
            }
            if (!members.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final roles = {
              for (final doc in members.data!.docs) doc.id: doc.data()['role'],
            };
            return ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Neue Nutzer legen zuerst ein Konto in der App an. Hier kannst du sie anschließend freigeben.',
                  ),
                ),
                for (final user in users.data!.docs)
                  ListTile(
                    title: Text(user.data()['email'] as String? ?? user.id),
                    subtitle: Text(
                      user.id == widget.store.uid
                          ? 'Dein Konto · Admin'
                          : roles[user.id] == 'admin'
                          ? 'Admin'
                          : roles[user.id] == 'editor'
                          ? 'Mitarbeiter'
                          : 'Freigabe ausstehend',
                    ),
                    trailing: user.id == widget.store.uid
                        ? null
                        : PopupMenuButton<String>(
                            enabled: !busy,
                            onSelected: (role) =>
                                change(user.id, role == 'none' ? null : role),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'editor',
                                child: Text('Als Mitarbeiter freigeben'),
                              ),
                              PopupMenuItem(
                                value: 'admin',
                                child: Text('Als Admin freigeben'),
                              ),
                              PopupMenuItem(
                                value: 'none',
                                child: Text('Zugriff entziehen'),
                              ),
                            ],
                          ),
                  ),
              ],
            );
          },
        );
      },
    ),
  );
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _Message extends StatelessWidget {
  const _Message(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      actions: [
        IconButton(
          onPressed: () => FirebaseAuth.instance.signOut(),
          icon: const Icon(Icons.logout),
          tooltip: 'Abmelden',
        ),
      ],
    ),
    body: Center(
      child: Padding(padding: const EdgeInsets.all(24), child: Text(message)),
    ),
  );
}
