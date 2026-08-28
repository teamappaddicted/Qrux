import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';

export 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSyC1ZgVWLMVagn4u',
        authDomain: 'qrux-11a39.firebaseapp.com',
        projectId: 'qrux-11a39',
        storageBucket: 'qrux-11a39.firebasestorage.app',
        messagingSenderId: '777455928832',
        appId: '1:777455928832:web:01b2eb56c3c6f06fa1fae5',
      ),
    );
  } catch (_) {}
  final preferences = await SharedPreferences.getInstance();
  SessionStore.initialize(preferences);
  runApp(const QruxApp());
}
