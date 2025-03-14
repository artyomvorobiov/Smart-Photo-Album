import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AlbumsService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<Map<String, dynamic>>> getUserAlbums() async {
    try {
      final userUid = _auth.currentUser?.uid;
      final userAlbumSnapshot = await _firestore
          .collection('albums')
          .where('owner', isEqualTo: userUid)
          .get();
      final userAlbums = userAlbumSnapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>})
          .toList();
      return userAlbums;
    } catch (e) {
      print("Ошибка при загрузке альбомов: $e");
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getSharedAlbums() async {
    try {
      final userUid = _auth.currentUser?.uid;
      if (userUid == null) return [];
      final snapshot = await _firestore.collection('albums').get();
      final allAlbums = snapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>})
          .toList();
      final sharedAlbums = allAlbums.where((album) {
        final sharedWith = album['sharedWith'] as Map<dynamic, dynamic>?;
        return sharedWith != null && sharedWith.containsKey(userUid);
      }).toList();
      return sharedAlbums;
    } catch (e) {
      print("Ошибка при загрузке общих альбомов: $e");
      return [];
    }
  }

  Future<void> deleteAlbum(Map<String, dynamic> album) async {
    final albumId = album['id'];
    await _firestore.collection('albums').doc(albumId).delete();
  }
}
