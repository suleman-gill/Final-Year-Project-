// File generated for Firebase web + Android configuration.
// Do not edit manually.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for iOS - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCeMVYJvD109-uBsiRVmIlP9w9Al28-d-o',
    appId: '1:118473168936:web:9c8446d133bce64e26fd1d',
    messagingSenderId: '118473168936',
    projectId: 'tilawah-ai-faisal',
    authDomain: 'tilawah-ai-faisal.firebaseapp.com',
    storageBucket: 'tilawah-ai-faisal.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAgXN5Uic04sD4-PPtzElJ09sNbPv491QQ',
    appId: '1:118473168936:android:d453eb7660e7f55026fd1d',
    messagingSenderId: '118473168936',
    projectId: 'tilawah-ai-faisal',
    storageBucket: 'tilawah-ai-faisal.firebasestorage.app',
  );
}
