import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; 
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

class ProfileService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Future<User?> getProfile(String email, String password) async {
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

  Future<List<Map<String, dynamic>>> getUsersList() async {
    try {
      QuerySnapshot usersSnapshot =
          await FirebaseFirestore.instance.collection('users').get();

      return usersSnapshot.docs.map((doc) {
        return {
          'id': doc.id,
          'email': doc['email'] ?? '',
          'displayName': doc['nickname'] ?? 'Неизвестный пользователь',
        };
      }).toList();
    } catch (e) {
      print("Ошибка при получении списка пользователей: $e");
      return [];
    }
  }


  Future<List<String>> searchNicknames(String query, User? _currentUser, List<String> _allowedUsers) async {
    try {
      final result = await _firestore.collection('users').get();
      String currentUserUid = _currentUser?.uid ?? '';

      final nicknames = result.docs
          .where((doc) {
            String nickname = doc.data()['nickname'] as String? ?? '';
            return doc.id != currentUserUid &&
                !_allowedUsers.contains(nickname) &&
                (nickname.toLowerCase().startsWith(query.toLowerCase()) ||
                    levenshteinDistance(query, nickname) <= 2);
          })
          .map((doc) => doc.data()['nickname'] as String)
          .toList();
      return nicknames;
    } catch (e) {
      return [];
    }
  }


  int levenshteinDistance(String s1, String s2) {
    int len1 = s1.length;
    int len2 = s2.length;

    List<List<int>> dp = List.generate(len1 + 1, (_) => List.filled(len2 + 1, 0));

    for (int i = 0; i <= len1; i++) {
      for (int j = 0; j <= len2; j++) {
        if (i == 0) {
          dp[i][j] = j;
        } else if (j == 0) {
          dp[i][j] = i;
        } else if (s1[i - 1] == s2[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1];
        } else {
          dp[i][j] = 1 +
              [
                dp[i - 1][j],
                dp[i][j - 1],
                dp[i - 1][j - 1]
              ].reduce((a, b) => a < b ? a : b);
        }
      }
    }
    return dp[len1][len2];
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      debugPrint(e.toString());
    }
  }
}
