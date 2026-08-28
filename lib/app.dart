import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'dashboard.dart';
import 'shared_widgets.dart';

class QruxApp extends StatelessWidget {
  const QruxApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'QRUX',
    theme: ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xfff4f4f1),
      colorScheme: const ColorScheme.light(
        primary: Colors.black,
        onPrimary: Colors.white,
        secondary: Color(0xffb9ff62),
        onSecondary: Colors.black,
        surface: Color(0xfff4f4f1),
        onSurface: Colors.black,
      ),
      fontFamily: 'Georgia',
    ),
    home: const SplashScreen(),
  );
}

class SessionStore {
  static late SharedPreferences _preferences;

  static void initialize(SharedPreferences preferences) {
    _preferences = preferences;
  }

  static String? get staffName => _preferences.getString('staffName');
  static String? get staffAdminUid => _preferences.getString('staffAdminUid');
  static bool get hasStaffSession => staffName != null && staffAdminUid != null;

  static Future<void> saveStaffSession({
    required String name,
    required String adminUid,
  }) async {
    await _preferences.setString('staffName', name);
    await _preferences.setString('staffAdminUid', adminUid);
  }

  static Future<void> clearStaffSession() async {
    await _preferences.remove('staffName');
    await _preferences.remove('staffAdminUid');
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashState();
}

class _SplashState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => FirebaseAuth.instance.currentUser != null
                ? const Dashboard()
                : SessionStore.hasStaffSession
                ? Dashboard(
                    staffName: SessionStore.staffName,
                    staffAdminUid: SessionStore.staffAdminUid,
                  )
                : const RoleScreen(),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: FadeTransition(
      opacity: animation,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code_2, color: Colors.white, size: 70),
            SizedBox(height: 20),
            Text(
              'QRUX',
              style: TextStyle(
                color: Colors.white,
                fontSize: 42,
                letterSpacing: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'SECURE MOTION SYSTEMS',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 10,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class RoleScreen extends StatelessWidget {
  const RoleScreen({super.key});
  @override
  Widget build(BuildContext context) => PageShell(
    title: 'Welcome to QRUX',
    subtitle: 'Choose your access level',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RoleTile(
          title: 'Admin',
          detail: 'Manage containers, people and movement',
          icon: Icons.shield_outlined,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AuthScreen()),
          ),
        ),
        const SizedBox(height: 14),
        RoleTile(
          title: 'Staff',
          detail: 'Access your assigned operations',
          icon: Icons.badge_outlined,
          muted: true,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const StaffLoginScreen()),
          ),
        ),
      ],
    ),
  );
}

class StaffLoginScreen extends StatefulWidget {
  const StaffLoginScreen({super.key});
  @override
  State<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends State<StaffLoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool loading = false;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    final emailValue = email.text.trim().toLowerCase();
    final passwordValue = password.text;
    if (emailValue.isEmpty || passwordValue.isEmpty) {
      showMessage(context, 'Enter your email and password.');
      return;
    }
    setState(() => loading = true);
    try {
      final result = await FirebaseFirestore.instance
          .collection('staff')
          .where('email', isEqualTo: emailValue)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();
      final record = result.docs.firstOrNull;
      final hash = sha256.convert(utf8.encode(passwordValue)).toString();
      if (record == null || record.data()['passwordHash'] != hash) {
        showMessage(context, 'Invalid staff credentials.');
        return;
      }
      if (!mounted) return;
      await SessionStore.saveStaffSession(
        name: record.data()['name'] as String? ?? emailValue,
        adminUid: record.data()['adminUid'] as String? ?? '',
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => Dashboard(
            staffName: record.data()['name'] as String? ?? emailValue,
            staffAdminUid: record.data()['adminUid'] as String?,
          ),
        ),
      );
    } on FirebaseException catch (error) {
      if (mounted) showMessage(context, error.message ?? 'Could not sign in.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageShell(
    title: 'Staff access',
    subtitle: 'Sign in with credentials created by admin',
    child: Column(
      children: [
        InputField(
          label: 'Email address',
          icon: Icons.email_outlined,
          controller: email,
        ),
        const SizedBox(height: 12),
        InputField(
          label: 'Password',
          icon: Icons.lock_outline,
          obscure: true,
          controller: password,
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          label: loading ? 'Signing in...' : 'Sign in',
          icon: Icons.login,
          onTap: loading ? () {} : login,
        ),
      ],
    ),
  );
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthState();
}

class _AuthState extends State<AuthScreen> {
  bool register = false;
  bool submitting = false;
  final nameController = TextEditingController();
  final companyController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  @override
  void dispose() {
    nameController.dispose();
    companyController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final email = emailController.text.trim();
    final password = passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      showMessage(context, 'Enter your email and password.');
      return;
    }
    if (register && nameController.text.trim().isEmpty) {
      showMessage(context, 'Enter your full name.');
      return;
    }

    setState(() => submitting = true);
    try {
      if (register) {
        final credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);
        await credential.user?.updateDisplayName(nameController.text.trim());
        await FirebaseFirestore.instance
            .collection('users')
            .doc(credential.user!.uid)
            .set({
              'name': nameController.text.trim(),
              'company': companyController.text.trim(),
              'email': email,
              'role': 'admin',
              'createdAt': FieldValue.serverTimestamp(),
            });
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const Dashboard()),
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      showMessage(context, error.message ?? 'Authentication failed.');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageShell(
    title: register ? 'Create your account' : 'Admin access',
    subtitle: register
        ? 'Set up your factory workspace'
        : 'Sign in to your command centre',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (register)
          InputField(
            label: 'Full name',
            icon: Icons.person_outline,
            controller: nameController,
          ),
        if (register) const SizedBox(height: 12),
        if (register)
          InputField(
            label: 'Company or factory',
            icon: Icons.business_outlined,
            controller: companyController,
          ),
        if (register) const SizedBox(height: 12),
        InputField(
          label: 'Email address',
          icon: Icons.alternate_email,
          controller: emailController,
          obscure: false,
        ),
        const SizedBox(height: 12),
        InputField(
          label: 'Password',
          icon: Icons.lock_outline,
          obscure: true,
          controller: passwordController,
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          label: submitting
              ? 'Please wait...'
              : register
              ? 'Create admin account'
              : 'Enter dashboard',
          icon: Icons.arrow_forward,
          onTap: submitting ? () {} : submit,
        ),
        TextButton(
          onPressed: () => setState(() => register = !register),
          child: Text(
            register
                ? 'Already registered? Sign in'
                : 'New to QRUX? Create an account',
          ),
        ),
      ],
    ),
  );
}
