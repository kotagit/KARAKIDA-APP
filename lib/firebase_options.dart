import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Web is not configured yet.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError('macOS is not configured yet.');
      case TargetPlatform.windows:
        throw UnsupportedError('Windows is not configured yet.');
      case TargetPlatform.linux:
        throw UnsupportedError('Linux is not configured yet.');
      default:
        throw UnsupportedError('Unsupported platform.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBowNiPC6aKjBqTmb5l2dW581HmEFzMApI',
    appId: '1:784037102811:android:ddd4dadcf1d7368d96f8fe',
    messagingSenderId: '784037102811',
    projectId: 'karakida-app-7bbc0',
    storageBucket: 'karakida-app-7bbc0.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyD5OGYeELulZTJlFhF7qBTX50dknOFZSmc',
    appId: '1:784037102811:ios:f5580ecc523ea26596f8fe',
    messagingSenderId: '784037102811',
    projectId: 'karakida-app-7bbc0',
    storageBucket: 'karakida-app-7bbc0.appspot.com',
    androidClientId: '784037102811-46bspknidepib0fgmifosm48tki8h333.apps.googleusercontent.com',
    iosClientId: '784037102811-6msbnc3i4ogjdl8cob8ogv04v65p46r0.apps.googleusercontent.com',
    iosBundleId: 'com.karakida.karakidaApp',
  );

}