import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; 
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:trip/services/fcm_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
   final FirebaseFirestore _firestore = FirebaseFirestore.instance;
     static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  Future<User?> signInWithEmail(String email, String password) async {
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCredential.user;
    } catch (e) {
      print(e);
      return null;
    }
  }
  Future<User?> registerWithEmail(String email, String password) async {
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await userCredential.user?.sendEmailVerification();
      return userCredential.user;
    } catch (e) {
      print(e);
      return null;
    }
  }


Future<void> signOut() async {
  await FcmService.removeToken();
  await _auth.signOut();
}


 Future<User?> signInWithGoogle() async {
  final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
  if (googleUser == null) {
    return null; 
  }
  final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
  final credential = GoogleAuthProvider.credential(
    accessToken: googleAuth.accessToken,
    idToken: googleAuth.idToken,
  );
  UserCredential userCredential = await _auth.signInWithCredential(credential);
  User? user = userCredential.user;
  if (user != null) {
    String? fcmToken = await FirebaseMessaging.instance.getToken();
    if (fcmToken != null) {
      DocumentReference userRef = _firestore.collection('users').doc(user.uid);
      DocumentSnapshot userDoc = await userRef.get();
      if (userDoc.exists) {
        await userRef.update({
          'email': user.email,
          'displayName': user.displayName ?? 'New User',
          'photoURL': user.photoURL ?? '',
          'fcmTokens': FieldValue.arrayUnion([fcmToken]),
        });
      } else {
        await userRef.set({
          'email': user.email,
          'displayName': user.displayName ?? 'New User',
          'photoURL': user.photoURL ?? '',
          'createdAt': DateTime.now(),
          'nickname': '',
          'privacySetting': 'От всех пользователей',
          'fcmTokens': [fcmToken],
          'tariff': 'basic',
          'storageUsed': 0,
          'storageQuota': 100 * 1024 * 1024,
        });
      }
    }
  }
  return user;
}



  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      debugPrint(e.toString());
    }
  }
}
