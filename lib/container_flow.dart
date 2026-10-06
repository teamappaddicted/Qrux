import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'shared_widgets.dart';

// ============================================================
// BACKEND CONFIGURATION
// ============================================================
//
// IMPORTANT:
// Put your CURRENT Cloudflare tunnel here.
//
// Example:
// const String backendUrl =
//     'your-current-tunnel.trycloudflare.com';
//
// Do NOT include https://
// Do NOT include /api/devices/register
//

const String backendUrl = 'late-habitat-floor-require.trycloudflare.com';

const int backendPort = 443;

// ============================================================
// FIREBASE DATABASE URL
// ============================================================

const String databaseUrl = 'https://qrux-11a39-default-rtdb.firebaseio.com';

// ============================================================
// QR SCAN SCREEN
// ============================================================

class ScanScreen extends StatefulWidget {
  final bool staffMode;

  const ScanScreen({this.staffMode = false, super.key});

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

    try {
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
            content: const Text(
              'This container QR has expired. Contact admin.',
            ),
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
          builder: (_) => widget.staffMode
              ? StaffContainerDetails(
                  containerId: snapshot.id,
                  data: snapshot.data()!,
                )
              : ContainerDetails(
                  containerId: snapshot.id,
                  data: snapshot.data()!,
                ),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      setState(() => opening = false);

      showMessage(context, 'Could not load container details.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
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

                  if (value != null) {
                    openResult(value);
                  }
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
}

// ============================================================
// CONTAINER DETAILS
// ============================================================

class ContainerDetails extends StatelessWidget {
  final String containerId;
  final Map<String, dynamic> data;

  const ContainerDetails({
    required this.containerId,
    required this.data,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return PageShell(
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

          const SizedBox(height: 20),

          Wrap(
            spacing: 18,
            runSpacing: 18,
            children: [
              Detail(
                'MATERIAL',
                data['material'] as String? ?? 'Not specified',
              ),
              Detail(
                'QUANTITY',
                data['quantity'] as String? ?? 'Not specified',
              ),
              Detail(
                'LOCATION',
                data['location'] as String? ?? 'Not specified',
              ),
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

          PrimaryButton(
            label: 'Open container',
            icon: Icons.sensor_door_outlined,
            onTap: () => _authorize(context, openContainer: true),
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
  }

  // ==========================================================
  // DELETE CONTAINER
  // ==========================================================

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
        databaseURL: databaseUrl,
      ).ref('containers/$containerId').remove();

      if (!context.mounted) return;

      Navigator.pop(context);

      showMessage(context, 'Container deleted. Its QR is now expired.');
    } on FirebaseException catch (error) {
      if (!context.mounted) return;

      showMessage(context, error.message ?? 'Could not delete container.');
    }
  }

  // ==========================================================
  // MOVEMENT AUTHORIZATION
  // ==========================================================

  Future<void> _authorize(
    BuildContext context, {
    bool openContainer = false,
  }) async {
    final enteredPassword = await showDialog<String>(
      context: context,
      builder: (_) => const _MovementPasswordDialog(),
    );

    if (!context.mounted) return;

    final storedHash = data['movementPasswordHash'];

    final matches =
        enteredPassword != null &&
        enteredPassword.isNotEmpty &&
        storedHash is String &&
        sha256.convert(utf8.encode(enteredPassword)).toString() == storedHash;

    if (!matches) {
      showMessage(context, 'Invalid password.');
      return;
    }

    if (openContainer) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              OpenContainerPage(containerId: containerId, data: data),
        ),
      );
      return;
    }

    // ========================================================
    // STEP 1:
    // ASK ESP32 FOR ITS DEVICE INFORMATION
    //
    // The phone must first be connected to the QRUX hotspot.
    // ========================================================

    final deviceInfo = await _getEsp32DeviceInfo();

    if (!context.mounted) return;

    // Could not contact ESP32.
    if (deviceInfo == null) {
      showMessage(
        context,
        'Could not connect to the ESP32. '
        'Please connect your phone to the QRUX ESP32 hotspot first.',
      );
      return;
    }

    final deviceId = deviceInfo['deviceId'] ?? '';

    final registered = deviceInfo['registered'] == true;
    final deviceContainerId = deviceInfo['containerId'] as String? ?? '';

    if (deviceId.isEmpty) {
      showMessage(context, 'ESP32 device ID not found.');
      return;
    }

    if (
      registered &&
      deviceContainerId.isNotEmpty &&
      deviceContainerId != containerId
    ) {
      showMessage(
        context,
        'This ESP32 is provisioned for a different container.',
      );
      return;
    }

    // ========================================================
    // STEP 2:
    // CHECK BACKEND STATUS
    //
    // This is the important part.
    //
    // Do not decide based only on the QR code.
    // ========================================================

    final alreadyRegistered = await _checkDeviceRegistration(deviceId);

    if (!context.mounted) return;

    // ========================================================
    final hasRegistration = alreadyRegistered || registered;
    final wifiConnected = deviceInfo['wifiConnected'] == true;
    final firebaseReady = deviceInfo['firebaseReady'] == true;

    if (hasRegistration && !wifiConnected) {
      showMessage(
        context,
        'ESP32 has saved Wi-Fi credentials and is reconnecting. Try again shortly.',
      );
      return;
    }

    if (hasRegistration && !firebaseReady) {
      showMessage(
        context,
        'ESP32 is on Wi-Fi but Firebase is not ready yet. Try again shortly.',
      );
      return;
    }

    // Open the controller only for the registered, connected ESP32.
    if (hasRegistration && wifiConnected && firebaseReady) {

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => Controller(containerId: containerId)),
      );

      return;
    }

    // ========================================================
    // NEW ESP32
    //
    // NOW ASK FOR WIFI ONLY
    // ========================================================

    final wifiData = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _WifiCredentialsDialog(),
    );

    if (!context.mounted || wifiData == null) {
      return;
    }

    final ssid = wifiData['ssid'];

    final password = wifiData['password'];

    if (ssid == null || password == null || ssid.isEmpty || password.isEmpty) {
      showMessage(context, 'Wi-Fi information is incomplete.');
      return;
    }

    await _provisionEsp32(context, ssid, password, deviceId);
  }

  // ==========================================================
  // GET ESP32 DEVICE INFORMATION
  // ==========================================================

  Future<Map<String, dynamic>?> _getEsp32DeviceInfo() async {
    try {
      const esp32InfoUrl = 'http://192.168.4.1/api/device-info';

      final response = await http
          .get(Uri.parse(esp32InfoUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return null;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  // ==========================================================
  // CHECK DEVICE REGISTRATION
  // ==========================================================

  Future<bool> _checkDeviceRegistration(String deviceId) async {
    try {
      final response = await http
          .get(Uri.parse('https://$backendUrl/api/devices/$deviceId/status'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return false;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is Map<String, dynamic>) {
        return decoded['success'] == true;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  // ==========================================================
  // SEND WIFI DETAILS TO ESP32
  // ==========================================================

  Future<void> _provisionEsp32(
    BuildContext context,
    String ssid,
    String password,
    String deviceId,
  ) async {
    bool loadingDialogOpen = false;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(child: Text('Configuring container connection...')),
            ],
          ),
        ),
      );

      loadingDialogOpen = true;

      const esp32Url = 'http://192.168.4.1/api/provision';

      final user = FirebaseAuth.instance.currentUser;

      final response = await http
          .post(
            Uri.parse(esp32Url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'wifiSsid': ssid,
              'wifiPassword': password,

              'deviceId': deviceId,

              'containerId': containerId,
              'qrCodeId': containerId,

              'adminId': user?.uid ?? '',

              // CURRENT BACKEND
              'backendUrl': backendUrl,
              'backendPort': backendPort,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (loadingDialogOpen && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();

        loadingDialogOpen = false;
      }

      if (!context.mounted) return;

      if (response.statusCode == 200) {
        showMessage(
          context,
          'Container configured successfully. '
          'ESP32 is connecting to Wi-Fi.',
        );

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Controller(containerId: containerId),
          ),
        );
      } else {
        showMessage(
          context,
          'ESP32 configuration failed: '
          '${response.body}',
        );
      }
    } catch (_) {
      if (loadingDialogOpen && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (!context.mounted) return;

      showMessage(
        context,
        'Could not configure ESP32. '
        'Make sure your phone is connected '
        'to the QRUX ESP32 hotspot.',
      );
    }
  }
}

class OpenContainerPage extends StatefulWidget {
  final String containerId;
  final Map<String, dynamic> data;

  const OpenContainerPage({
    required this.containerId,
    required this.data,
    super.key,
  });

  @override
  State<OpenContainerPage> createState() => _OpenContainerPageState();
}

class StaffContainerDetails extends StatelessWidget {
  final String containerId;
  final Map<String, dynamic> data;

  const StaffContainerDetails({
    required this.containerId,
    required this.data,
    super.key,
  });

  Future<void> _authorizeOpen(BuildContext context) async {
    final enteredPassword = await showDialog<String>(
      context: context,
      builder: (_) => const _MovementPasswordDialog(),
    );
    if (!context.mounted) return;

    final storedHash = data['movementPasswordHash'];
    final matches =
        enteredPassword != null &&
        enteredPassword.isNotEmpty &&
        storedHash is String &&
        sha256.convert(utf8.encode(enteredPassword)).toString() == storedHash;

    if (!matches) {
      showMessage(context, 'Invalid password.');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OpenContainerPage(containerId: containerId, data: data),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: data['name'] as String? ?? containerId,
      subtitle: 'Verified QRUX container identity',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 18,
            runSpacing: 18,
            children: [
              Detail(
                'MATERIAL',
                data['material'] as String? ?? 'Not specified',
              ),
              Detail(
                'QUANTITY',
                data['quantity'] as String? ?? 'Not specified',
              ),
              Detail(
                'LOCATION',
                data['location'] as String? ?? 'Not specified',
              ),
              Detail('STATUS', data['status'] as String? ?? 'Secured'),
            ],
          ),
          const SizedBox(height: 26),
          PrimaryButton(
            label: 'Open container',
            icon: Icons.sensor_door_outlined,
            onTap: () => _authorizeOpen(context),
          ),
        ],
      ),
    );
  }
}

class _OpenContainerPageState extends State<OpenContainerPage> {
  late final TextEditingController materialController;
  late final TextEditingController quantityController;
  late final TextEditingController locationController;
  bool opening = true;
  bool saving = false;
  bool closing = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    materialController = TextEditingController(
      text: widget.data['material'] as String? ?? '',
    );
    quantityController = TextEditingController(
      text: widget.data['quantity'] as String? ?? '',
    );
    locationController = TextEditingController(
      text: widget.data['location'] as String? ?? '',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendLidCommand('OPEN', 'Open');
    });
  }

  @override
  void dispose() {
    materialController.dispose();
    quantityController.dispose();
    locationController.dispose();
    super.dispose();
  }

  Future<void> _sendLidCommand(String command, String status) async {
    try {
      await FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: databaseUrl,
      ).ref('containers/${widget.containerId}/command').set(command);
      await FirebaseFirestore.instance
          .collection('containers')
          .doc(widget.containerId)
          .update({
            'status': status,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      if (!mounted) return;
      setState(() {
        opening = false;
        closing = false;
        errorMessage = null;
      });

      if (command == 'CLOSE') {
        Navigator.pop(context);
        showMessage(context, 'Container closed.');
      }
    } on FirebaseException catch (error) {
      if (!mounted) return;
      setState(() {
        opening = false;
        closing = false;
        errorMessage = error.message ?? 'Could not control the container lid.';
      });
    }
  }

  Future<void> _saveDetails() async {
    setState(() => saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('containers')
          .doc(widget.containerId)
          .update({
            'material': materialController.text.trim(),
            'quantity': quantityController.text.trim(),
            'location': locationController.text.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
      if (!mounted) return;
      setState(() => saving = false);
      showMessage(context, 'Container details updated.');
    } on FirebaseException catch (error) {
      if (!mounted) return;
      setState(() => saving = false);
      showMessage(context, error.message ?? 'Could not update details.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Container open',
      subtitle: widget.data['name'] as String? ?? widget.containerId,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            color: Colors.black,
            child: Row(
              children: [
                const Icon(
                  Icons.sensor_door_outlined,
                  color: Color(0xffb9ff62),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    opening ? 'OPENING LID' : 'LID OPEN',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                if (opening)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(errorMessage!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 28),
          const Text(
            'CONTAINER DETAILS',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: materialController,
            decoration: const InputDecoration(
              labelText: 'Material',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: quantityController,
            decoration: const InputDecoration(
              labelText: 'Quantity',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: locationController,
            decoration: const InputDecoration(
              labelText: 'Location',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: saving ? 'Saving details...' : 'Update details',
            icon: Icons.save_outlined,
            onTap: saving ? () {} : _saveDetails,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 54,
            child: OutlinedButton.icon(
              onPressed: closing || opening
                  ? null
                  : () {
                      setState(() => closing = true);
                      _sendLidCommand('CLOSE', 'Secured');
                    },
              icon: const Icon(Icons.lock_outline),
              label: Text(closing ? 'Closing container...' : 'Close container'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black,
                side: const BorderSide(color: Colors.black),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// MOVEMENT PASSWORD DIALOG
// ============================================================

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
  Widget build(BuildContext context) {
    return AlertDialog(
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
}

// ============================================================
// WIFI CREDENTIALS DIALOG
//
// Device ID IS NOT ASKED ANYMORE.
//
// ESP32 provides its device ID automatically.
// ============================================================

class _WifiCredentialsDialog extends StatefulWidget {
  const _WifiCredentialsDialog();

  @override
  State<_WifiCredentialsDialog> createState() => _WifiCredentialsDialogState();
}

class _WifiCredentialsDialogState extends State<_WifiCredentialsDialog> {
  final ssidController = TextEditingController();

  final passwordController = TextEditingController();

  bool obscurePassword = true;

  @override
  void dispose() {
    ssidController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connect container to Wi-Fi'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter the Wi-Fi details for this new ESP32 device.'),

            const SizedBox(height: 20),

            TextField(
              controller: ssidController,
              decoration: const InputDecoration(
                labelText: 'Wi-Fi SSID',
                prefixIcon: Icon(Icons.wifi),
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: passwordController,
              obscureText: obscurePassword,
              decoration: InputDecoration(
                labelText: 'Wi-Fi Password',
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    obscurePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      obscurePassword = !obscurePassword;
                    });
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final ssid = ssidController.text.trim();

            final password = passwordController.text;

            if (ssid.isEmpty || password.isEmpty) {
              showMessage(context, 'Please enter Wi-Fi details.');
              return;
            }

            Navigator.pop(context, {'ssid': ssid, 'password': password});
          },
          child: const Text('Configure'),
        ),
      ],
    );
  }
}

// ============================================================
// CONTAINER CONTROLLER
// ============================================================

class Controller extends StatefulWidget {
  final String containerId;

  const Controller({required this.containerId, super.key});

  @override
  State<Controller> createState() => _ControllerState();
}

class _ControllerState extends State<Controller> {
  String command = 'STOP';

  Future<void> sendCommand(String nextCommand) async {
    setState(() {
      command = nextCommand;
    });

    try {
      // IMPORTANT:
      // ESP32 expects a STRING.
      //
      // Do not send a JSON object here.

      await FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: databaseUrl,
      ).ref('containers/${widget.containerId}/command').set(nextCommand);
    } on FirebaseException catch (error) {
      if (!mounted) return;

      showMessage(context, error.message ?? 'Could not send command.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Container controller',
      subtitle: '${widget.containerId} • Connected via Firebase',
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
                () => sendCommand('STOP'),
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
}
