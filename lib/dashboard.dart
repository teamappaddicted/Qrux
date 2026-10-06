import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:crypto/crypto.dart';

import 'dart:convert';

import 'app.dart';
import 'container_flow.dart';
import 'shared_widgets.dart';

class Dashboard extends StatelessWidget {
  final String? staffName;
  final String? staffAdminUid;
  const Dashboard({this.staffName, this.staffAdminUid, super.key});
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (staffAdminUid != null && SessionStore.isStaffUser(user?.uid)) {
      return StaffDashboard(
        name: staffName ?? 'Staff',
        adminUid: staffAdminUid!,
      );
    }
    final ownerUid = user?.uid ?? staffAdminUid;
    if (ownerUid == null) return const AuthScreen();
    final containers = FirebaseFirestore.instance
        .collection('containers')
        .where('ownerUid', isEqualTo: ownerUid)
        .snapshots();
    final staff = FirebaseFirestore.instance
        .collection('staff')
        .where('adminUid', isEqualTo: ownerUid)
        .where('status', isEqualTo: 'active')
        .snapshots();
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: containers,
          builder: (context, snapshot) {
            final docs = snapshot.data?.docs ?? [];
            final online = docs
                .where((doc) => doc.data()['online'] == true)
                .length;
            final name = staffName?.trim().isNotEmpty == true
                ? staffName!.trim()
                : user?.displayName?.trim().isNotEmpty == true
                ? user!.displayName!.trim()
                : user?.email?.split('@').first ?? 'Admin';
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'GOOD MORNING, ${name.toUpperCase()}',
                        style: const TextStyle(
                          fontSize: 11,
                          letterSpacing: 2,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: user != null ? 'Profile' : 'Sign out',
                      onPressed: () async {
                        if (user != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ProfileScreen(),
                            ),
                          );
                        } else {
                          await SessionStore.clearStaffSession();
                          if (context.mounted) {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const RoleScreen(),
                              ),
                              (_) => false,
                            );
                          }
                        }
                      },
                      icon: Icon(
                        user != null
                            ? Icons.account_circle_outlined
                            : Icons.logout,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Command centre',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(20),
                  color: Colors.black,
                  child: Row(
                    children: [
                      const Icon(Icons.radar, color: Colors.white),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Text(
                          'Live fleet status',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.circle,
                        size: 12,
                        color: snapshot.hasError
                            ? Colors.redAccent
                            : const Color(0xffb9ff62),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    Metric(
                      '${docs.length}',
                      'CONTAINERS',
                      Icons.inventory_2_outlined,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ContainerList(),
                        ),
                      ),
                    ),
                    Metric('$online', 'ONLINE NOW', Icons.wifi),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: staff,
                      builder: (context, staffSnapshot) => Metric(
                        '${staffSnapshot.data?.docs.length ?? 0}',
                        'STAFF',
                        Icons.people_outline,
                      ),
                    ),
                    Metric(
                      '${docs.length}',
                      'EVENTS TODAY',
                      Icons.insights_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const Text(
                  'Quick actions',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                ActionRow(
                  icon: Icons.add_box_outlined,
                  title: 'Register container',
                  detail: 'Create identity and movement key',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RegisterContainer(),
                    ),
                  ),
                ),
                ActionRow(
                  icon: Icons.qr_code_2,
                  title: 'Scan a container',
                  detail: 'Identify and inspect a QRUX asset',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ScanScreen()),
                  ),
                ),
                ActionRow(
                  icon: Icons.people_outline,
                  title: 'Manage staff',
                  detail: 'Invite and control permissions',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StaffScreen()),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class StaffDashboard extends StatelessWidget {
  final String name;
  final String adminUid;
  const StaffDashboard({required this.name, required this.adminUid, super.key});

  @override
  Widget build(BuildContext context) {
    final containers = FirebaseFirestore.instance
        .collection('containers')
        .where('ownerUid', isEqualTo: adminUid)
        .snapshots();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff dashboard'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              await SessionStore.clearStaffSession();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const RoleScreen()),
                  (_) => false,
                );
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: containers,
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Welcome, ${name.toUpperCase()}',
                style: const TextStyle(fontSize: 12, letterSpacing: 2),
              ),
              const SizedBox(height: 8),
              const Text(
                'Assigned containers',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ActionRow(
                icon: Icons.qr_code_scanner,
                title: 'Scan a container',
                detail: 'Open, close, and update container details',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ScanScreen(staffMode: true),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Metric(
                '${docs.length}',
                'CONTAINERS',
                Icons.inventory_2_outlined,
              ),
              const SizedBox(height: 20),
              ...docs.map(
                (doc) => ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(doc.data()['name'] as String? ?? doc.id),
                  subtitle: Text(
                    doc.data()['location'] as String? ?? 'No location',
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StaffContainerDetails(
                        containerId: doc.id,
                        data: doc.data(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return PageShell(
      title: user?.displayName ?? 'Admin profile',
      subtitle: user?.email ?? '',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.account_circle, size: 100),
          const SizedBox(height: 20),
          Detail('NAME', user?.displayName ?? 'Admin'),
          const SizedBox(height: 16),
          Detail('EMAIL', user?.email ?? 'Not available'),
          const SizedBox(height: 16),
          Detail('ROLE', 'Administrator'),
          const SizedBox(height: 28),
          PrimaryButton(
            label: 'Sign out',
            icon: Icons.logout,
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const RoleScreen()),
                  (_) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});
  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  bool saving = false;

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> createStaff() async {
    final admin = FirebaseAuth.instance.currentUser;
    final emailValue = email.text.trim().toLowerCase();
    if (admin == null ||
        name.text.trim().isEmpty ||
        emailValue.isEmpty ||
        password.text.length < 6) {
      showMessage(
        context,
        'Enter name, email, and a password of at least 6 characters.',
      );
      return;
    }

    setState(() => saving = true);
    FirebaseAuth? provisioningAuth;
    try {
      final existing = await FirebaseFirestore.instance
          .collection('staff')
          .where('adminUid', isEqualTo: admin.uid)
          .where('email', isEqualTo: emailValue)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        if (mounted) {
          showMessage(context, 'A staff account already uses this email.');
        }
        return;
      }

      const provisioningAppName = 'qrux-staff-provisioning';
      FirebaseApp provisioningApp;
      try {
        provisioningApp = Firebase.app(provisioningAppName);
      } on FirebaseException {
        provisioningApp = await Firebase.initializeApp(
          name: provisioningAppName,
          options: Firebase.app().options,
        );
      }
      provisioningAuth = FirebaseAuth.instanceFor(app: provisioningApp);

      final credential = await provisioningAuth.createUserWithEmailAndPassword(
        email: emailValue,
        password: password.text,
      );
      final staffUid = credential.user?.uid;
      if (staffUid == null) {
        throw StateError('Firebase did not return the new staff account ID.');
      }

      try {
        await FirebaseFirestore.instance.collection('staff').doc(staffUid).set({
          'adminUid': admin.uid,
          'name': name.text.trim(),
          'email': emailValue,
          'status': 'active',
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        await provisioningAuth.currentUser?.delete();
        rethrow;
      }

      var realtimeAccessReady = true;
      try {
        await FirebaseDatabase.instanceFor(
          app: Firebase.app(),
          databaseURL: databaseUrl,
        ).ref('admins/${admin.uid}/staff/$staffUid/active').set(true);
      } on FirebaseException {
        realtimeAccessReady = false;
      }

      name.clear();
      email.clear();
      password.clear();
      if (mounted) {
        showMessage(
          context,
          realtimeAccessReady ? 'Staff account created.' : 'Staff account created. Realtime Database rules must allow the admin to add its staff access link.',
        );
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        showMessage(
          context,
          error.message ?? 'Could not create staff account.',
        );
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        showMessage(
          context,
          error.message ?? 'Could not create staff account.',
        );
      }
    } catch (error) {
      if (mounted) showMessage(context, error.toString());
    } finally {
      await provisioningAuth?.signOut();
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = FirebaseAuth.instance.currentUser;
    final staff = FirebaseFirestore.instance
        .collection('staff')
        .where('adminUid', isEqualTo: admin?.uid)
        .snapshots();
    return Scaffold(
      appBar: AppBar(title: const Text('Manage staff')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      InputField(
                        label: 'Staff name',
                        icon: Icons.person_outline,
                        controller: name,
                      ),
                      const SizedBox(height: 8),
                      InputField(
                        label: 'Staff email',
                        icon: Icons.email_outlined,
                        controller: email,
                      ),
                      const SizedBox(height: 8),
                      InputField(
                        label: 'Password',
                        icon: Icons.lock_outline,
                        obscure: true,
                        controller: password,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: saving ? null : createStaff,
                  icon: const Icon(Icons.person_add),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: staff,
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty)
                  return const Center(child: Text('No staff accounts yet.'));
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    return ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(data['name'] as String? ?? 'Unknown'),
                      subtitle: Text(data['email'] as String? ?? 'Unknown'),
                      trailing: IconButton(
                        tooltip: 'Delete staff record',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          try {
                            await FirebaseDatabase.instanceFor(
                                  app: Firebase.app(),
                                  databaseURL: databaseUrl,
                                )
                                .ref(
                                  'admins/${admin?.uid}/staff/${docs[index].id}',
                                )
                                .remove();
                            await docs[index].reference.delete();
                            if (context.mounted) {
                              showMessage(context, 'Staff access removed.');
                            }
                          } on FirebaseException catch (error) {
                            if (context.mounted) {
                              showMessage(
                                context,
                                error.message ??
                                    'Could not remove staff access.',
                              );
                            }
                          }
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ContainerList extends StatelessWidget {
  const ContainerList({super.key});
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final stream = FirebaseFirestore.instance
        .collection('containers')
        .where('ownerUid', isEqualTo: user?.uid)
        .snapshots();
    return Scaffold(
      appBar: AppBar(title: const Text('Containers')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return Center(
              child: Text('Could not load containers: ${snapshot.error}'),
            );
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          if (snapshot.data!.docs.isEmpty)
            return const Center(child: Text('No containers registered yet.'));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final data = doc.data();
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(data['name'] as String? ?? doc.id),
                  subtitle: Text(data['location'] as String? ?? 'No location'),
                  trailing: Icon(
                    Icons.circle,
                    size: 12,
                    color: data['online'] == true
                        ? const Color(0xff4d8c27)
                        : Colors.black26,
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ContainerDetails(containerId: doc.id, data: data),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class RegisterContainer extends StatefulWidget {
  const RegisterContainer({super.key});
  @override
  State<RegisterContainer> createState() => _RegisterContainerState();
}

class _RegisterContainerState extends State<RegisterContainer> {
  final name = TextEditingController();
  final material = TextEditingController();
  final quantity = TextEditingController();
  final location = TextEditingController();
  final movementPassword = TextEditingController();
  bool saving = false;

  @override
  void dispose() {
    name.dispose();
    material.dispose();
    quantity.dispose();
    location.dispose();
    movementPassword.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null ||
        name.text.trim().isEmpty ||
        movementPassword.text.isEmpty) {
      showMessage(context, 'Enter a container name and movement password.');
      return;
    }
    setState(() => saving = true);
    try {
      final reference = await FirebaseFirestore.instance
          .collection('containers')
          .add({
            'ownerUid': user.uid,
            'name': name.text.trim(),
            'material': material.text.trim(),
            'quantity': quantity.text.trim(),
            'location': location.text.trim(),
            'movementPasswordHash': sha256
                .convert(utf8.encode(movementPassword.text))
                .toString(),
            'online': false,
            'status': 'Secured',
            'createdAt': FieldValue.serverTimestamp(),
          });
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ContainerDetails(
            containerId: reference.id,
            data: {
              'name': name.text.trim(),
              'material': material.text.trim(),
              'quantity': quantity.text.trim(),
              'location': location.text.trim(),
              'status': 'Secured',
              'online': false,
            },
          ),
        ),
      );
    } on FirebaseException catch (error) {
      if (mounted)
        showMessage(context, error.message ?? 'Could not save container.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: 'Register container',
    subtitle: 'Give this asset a secure digital identity',
    fields: [
      InputField(
        label: 'Container name',
        icon: Icons.inventory_2_outlined,
        controller: name,
      ),
      InputField(
        label: 'Material stored',
        icon: Icons.category_outlined,
        controller: material,
      ),
      InputField(
        label: 'Quantity and unit',
        icon: Icons.scale_outlined,
        controller: quantity,
      ),
      InputField(
        label: 'Factory location',
        icon: Icons.location_on_outlined,
        controller: location,
      ),
      InputField(
        label: 'Movement password',
        icon: Icons.key_outlined,
        obscure: true,
        controller: movementPassword,
      ),
    ],
    buttonLabel: saving ? 'Saving...' : 'Generate QR identity',
    onSubmit: saving ? () {} : save,
  );
}

class FormPage extends StatelessWidget {
  final String title, subtitle;
  final List<Widget> fields;
  final VoidCallback onSubmit;
  final String buttonLabel;
  const FormPage({
    required this.title,
    required this.subtitle,
    required this.fields,
    this.buttonLabel = 'Generate QR identity',
    required this.onSubmit,
    super.key,
  });
  @override
  Widget build(BuildContext context) => PageShell(
    title: title,
    subtitle: subtitle,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...fields.expand((field) => [field, const SizedBox(height: 12)]),
        PrimaryButton(
          label: buttonLabel,
          icon: Icons.arrow_forward,
          onTap: onSubmit,
        ),
      ],
    ),
  );
}
