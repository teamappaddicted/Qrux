import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'dart:convert';

import 'shared_widgets.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool opening = false;

  Future<void> openResult(String value) async {
    if (opening) return;
    final id = value.replaceFirst('qrux://container/', '').trim();
    if (id.isEmpty) return;
    setState(() => opening = true);
    final snapshot = await FirebaseFirestore.instance
        .collection('containers')
        .doc(id)
        .get();
    if (!mounted) return;
    setState(() => opening = false);
    if (!snapshot.exists) {
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('QR expired'),
          content: const Text('This container QR has expired. Contact admin.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ContainerDetails(containerId: snapshot.id, data: snapshot.data()!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PageShell(
    title: 'Scan container',
    subtitle: 'Point your camera at a QRUX identity',
    child: Column(
      children: [
        SizedBox(
          height: 270,
          child: ClipRect(
            child: MobileScanner(
              onDetect: (capture) {
                final value = capture.barcodes.firstOrNull?.rawValue;
                if (value != null) openResult(value);
              },
            ),
          ),
        ),
        if (opening)
          const Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ),
      ],
    ),
  );
}

class ContainerDetails extends StatelessWidget {
  final String containerId;
  final Map<String, dynamic> data;
  const ContainerDetails({
    required this.containerId,
    required this.data,
    super.key,
  });
  @override
  Widget build(BuildContext context) => PageShell(
    title: data['name'] as String? ?? containerId,
    subtitle: 'Verified QRUX container identity',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: QrImageView(
            data: 'qrux://container/$containerId',
            size: 220,
            backgroundColor: Colors.white,
          ),
        ),
        Wrap(
          spacing: 18,
          runSpacing: 18,
          children: [
            Detail('MATERIAL', data['material'] as String? ?? 'Not specified'),
            Detail('QUANTITY', data['quantity'] as String? ?? 'Not specified'),
            Detail('LOCATION', data['location'] as String? ?? 'Not specified'),
            Detail('STATUS', data['status'] as String? ?? 'Secured'),
          ],
        ),
        const SizedBox(height: 26),
        PrimaryButton(
          label: 'Move container',
          icon: Icons.open_in_new,
          onTap: () => _authorize(context),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () => _deleteContainer(context),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete container'),
          style: TextButton.styleFrom(foregroundColor: Colors.black),
        ),
      ],
    ),
  );

  Future<void> _deleteContainer(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete container?'),
        content: const Text(
          'This permanently expires its QR identity and removes its control link.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('containers')
          .doc(containerId)
          .delete();
      await FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: 'https://qrux-11a39-default-rtdb.firebaseio.com',
      ).ref('containers/$containerId').remove();
      if (context.mounted) {
        Navigator.pop(context);
        showMessage(context, 'Container deleted. Its QR is now expired.');
      }
    } on FirebaseException catch (error) {
      if (context.mounted) {
        showMessage(context, error.message ?? 'Could not delete container.');
      }
    }
  }

  Future<void> _authorize(BuildContext context) async {
    String? enteredPassword;
    try {
      enteredPassword = await showDialog<String>(
        context: context,
        builder: (_) => const _MovementPasswordDialog(),
      );
    } catch (_) {
      enteredPassword = null;
    }
    final storedHash = data['movementPasswordHash'];
    final matches =
        enteredPassword != null &&
        enteredPassword!.isNotEmpty &&
        storedHash is String &&
        sha256.convert(utf8.encode(enteredPassword!)).toString() == storedHash;
    if (!context.mounted) return;
    if (!matches) {
      showMessage(context, 'Invalid password.');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => Controller(containerId: containerId)),
    );
  }
}

class _MovementPasswordDialog extends StatefulWidget {
  const _MovementPasswordDialog();
  @override
  State<_MovementPasswordDialog> createState() =>
      _MovementPasswordDialogState();
}

class _MovementPasswordDialogState extends State<_MovementPasswordDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Authorize movement'),
    content: InputField(
      label: 'Movement password',
      icon: Icons.key_outlined,
      obscure: true,
      controller: controller,
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text),
        child: const Text('Verify'),
      ),
    ],
  );
}

class Controller extends StatefulWidget {
  final String containerId;
  const Controller({required this.containerId, super.key});
  @override
  State<Controller> createState() => _ControllerState();
}

class _ControllerState extends State<Controller> {
  String command = 'STOPPED';

  Future<void> sendCommand(String nextCommand) async {
    setState(() => command = nextCommand);
    try {
      await FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: 'https://qrux-11a39-default-rtdb.firebaseio.com',
      ).ref('containers/${widget.containerId}/command').set({
        'value': nextCommand,
        'uid': FirebaseAuth.instance.currentUser?.uid,
        'timestamp': ServerValue.timestamp,
      });
    } on FirebaseException catch (error) {
      if (mounted)
        showMessage(context, error.message ?? 'Could not send command.');
    }
  }

  @override
  Widget build(BuildContext context) => PageShell(
    title: 'Container controller',
    subtitle: '${widget.containerId}  •  Connected via Firebase',
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          color: Colors.black,
          child: Row(
            children: [
              const Icon(Icons.wifi, color: Color(0xffb9ff62)),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'LIVE LINK ACTIVE',
                  style: TextStyle(
                    color: Colors.white,
                    letterSpacing: 1.5,
                    fontSize: 11,
                  ),
                ),
              ),
              Text(
                command,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Control(
          'FORWARD',
          Icons.keyboard_arrow_up,
          () => sendCommand('FORWARD'),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Control(
              'LEFT',
              Icons.keyboard_arrow_left,
              () => sendCommand('LEFT'),
            ),
            Control(
              'STOP',
              Icons.stop,
              () => sendCommand('STOPPED'),
              filled: true,
            ),
            Control(
              'RIGHT',
              Icons.keyboard_arrow_right,
              () => sendCommand('RIGHT'),
            ),
          ],
        ),
        Control(
          'BACKWARD',
          Icons.keyboard_arrow_down,
          () => sendCommand('BACKWARD'),
        ),
      ],
    ),
  );
}
