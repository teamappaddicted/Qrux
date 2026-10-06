import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';

export 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final usesNativeFirebaseConfig =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (usesNativeFirebaseConfig) {
    await Firebase.initializeApp();
  } else {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSyC1ZgVWLMVagn4luRdLb4P4UfZVKzwDIRQ',
        authDomain: 'qrux-11a39.firebaseapp.com',
        projectId: 'qrux-11a39',
        storageBucket: 'qrux-11a39.firebasestorage.app',
        messagingSenderId: '777455928832',
        appId: '1:777455928832:web:01b2eb56c3c6f06fa1fae5',
      ),
    );
  }
  final preferences = await SharedPreferences.getInstance();
  SessionStore.initialize(preferences);
  runApp(const QruxApp());
}
