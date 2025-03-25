import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FcmService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;


  static Future<void> removeToken() async {
    try {
      String? token = await _messaging.getToken();
      if (token != null) {
        final user = _auth.currentUser;
        if (user != null) {
          await _firestore.collection('users').doc(user.uid).update({
            'fcmTokens': FieldValue.arrayRemove([token]),
          });
          print("FCM токен $token успешно удалён для пользователя ${user.uid}");
        } else {
          print("Пользователь не найден при удалении FCM токена.");
        }
      } else {
        print("Не удалось получить FCM токен для удаления.");
      }
    } catch (e) {
      print("Ошибка при удалении FCM токена: $e");
    }
  }

}
