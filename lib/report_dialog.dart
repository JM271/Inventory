import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'inventory_report.dart';
import 'onedrive_service.dart';
import 'part.dart';

class ReportDialog extends StatefulWidget {
  const ReportDialog({super.key, required this.parts});
  final List<Part> parts;
  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog>
    with WidgetsBindingObserver {
  Completer<void>? _foregroundWaiter;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _releaseWaiter();
  }

  void _releaseWaiter() {
    final waiter = _foregroundWaiter;
    _foregroundWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  Future<void> _waitForForeground() async {
    final state = WidgetsBinding.instance.lifecycleState;
    if (!mounted || state == null || state == AppLifecycleState.resumed) return;
    _foregroundWaiter ??= Completer<void>();
    await _foregroundWaiter!.future;
  }

  final clientId = TextEditingController();
  final service = OneDriveService();
  final folderLink = TextEditingController(
    text: OneDriveService.defaultFolderLink,
  );
  bool busy = false, ready = false;
  DeviceSignIn? signIn;
  String? error;
  Uri? uploaded;
  String? filename;
  Uint8List? reportBytes;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        folderLink.text =
            prefs.getString('inventory_workshop_folder_link') ??
            OneDriveService.defaultFolderLink;
        clientId.text =
            prefs.getString('inventory_onedrive_client_id') ??
            OneDriveService.defaultClientId;
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              error = 'Could not load setup. Enter your application ID below.',
        );
      }
    }
    if (mounted) {
      setState(() => ready = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _releaseWaiter();
    service.dispose();
    clientId.dispose();
    folderLink.dispose();
    super.dispose();
  }

  Future<void> open(Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Could not open browser');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not open the browser. Copy the address below and open it manually.',
        );
      }
    }
  }

  Future<void> connect() async {
    final id = clientId.text.trim();
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(id)) {
      setState(
        () => error = 'Enter the Application (client) ID from your Microsoft app registration.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
      signIn = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('inventory_onedrive_client_id', id);
      await prefs.setString('inventory_workshop_folder_link', folderLink.text.trim());
      service.folderLink = folderLink.text.trim();
      final request = await service.startSignIn(id);
      if (!mounted) {
        return;
      }
      setState(() => signIn = request);
      await service.finishSignIn(
        id,
        request,
        () => !mounted,
        beforePoll: _waitForForeground,
      );
      if (mounted) {
        setState(() => signIn = null);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          signIn = null;
          error = e is OneDriveException ? e.message : 'Microsoft could not be reached. Check your internet connection and try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> upload() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final now = DateTime.now().toUtc();
      final name = filename ??=
          'Spoke-inventory-${now.toIso8601String().replaceAll(':', '-').replaceAll('.', '-')}.xlsx';
      final bytes = reportBytes ??= buildInventoryReport(widget.parts, now);
      final url = await service.upload(name, bytes);
      if (mounted) {
        setState(() {
          uploaded = url;
          filename = name;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is OneDriveException ? e.message : 'The Excel report could not be prepared or uploaded. Your inventory is unchanged. Try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Excel report to OneDrive'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.parts.length} part types · ${widget.parts.fold<int>(0, (n, p) => n + p.quantity)} units',
            ),
            const SizedBox(height: 8),
            const Text(
              'Includes all parts, categories, SKU, locations, quantities, minimum levels and stock status. Saves a new dated Excel file in the configured shared OneDrive folder.',
            ),
            const SizedBox(height: 16),
            if (kIsWeb)
              const Text(
                'Direct Microsoft sign-in is available in the Android and iOS app. Run the mobile app to upload reports. Device-code sign-in is not supported in this browser build.',
              )
            else if (uploaded != null) ...[
              const Icon(
                Icons.cloud_done_outlined,
                size: 42,
                color: Colors.green,
              ),
              const SizedBox(height: 12),
              const Text(
                'Saved to OneDrive',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(filename!),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => open(uploaded!),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open saved report'),
              ),
              SelectableText(
                uploaded.toString(),
                style: const TextStyle(fontSize: 12),
              ),
            ] else ...[
              if (!service.connected) ...[
                TextField(
                  controller: clientId,
                  enabled: ready && !busy,
                  decoration: const InputDecoration(
                    labelText: 'Inventory application (client) ID',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: folderLink,
                  enabled: ready && !busy,
                  decoration: const InputDecoration(
                    labelText: 'Workshop inventory folder link',
                  ),
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('First-time Microsoft setup'),
                  children: const [
                    Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: SelectableText(
                        '1. In the Inventory Microsoft app registration, enable personal Microsoft accounts under Supported account types.\n2. Sign in with your personal Microsoft account, as in Bike Dispatch. It needs edit access to the shared folder.\n3. Under Authentication → Settings, enable Allow public client flows.\n4. Under API permissions, add Microsoft Graph → Delegated → Files.ReadWrite.\n5. Copy Inventory’s Application (client) ID here. Microsoft displays the name from that registration during sign-in. No client secret is needed.',
                      ),
                    ),
                  ],
                ),
                const Text(
                  'Sign in for each report session. Access tokens stay in memory and are cleared when you close this window.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                if (signIn != null) ...[
                  const Text('Enter this code on Microsoft’s sign-in page:'),
                  SelectableText(
                    signIn!.code,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => open(signIn!.url),
                    child: const Text('Open Microsoft sign-in'),
                  ),
                  SelectableText(signIn!.url.toString()),
                  const Text(
                    'After signing in, return here. Waiting for Microsoft…',
                  ),
                ] else
                  FilledButton.icon(
                    onPressed: ready && !busy ? connect : null,
                    icon: const Icon(Icons.login),
                    label: const Text('Sign in to Microsoft'),
                  ),
              ] else ...[
                const Text('Microsoft connected. Ready to upload.'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: busy ? null : upload,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Upload Excel report'),
                ),
                TextButton(
                  onPressed: busy ? null : () => setState(service.disconnect),
                  child: const Text('Use another account'),
                ),
              ],
            ],
            if (busy)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(busy && signIn != null ? 'Cancel sign-in' : 'Close'),
      ),
    ],
  );
}
