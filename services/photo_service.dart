import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:exif/exif.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tesseract_ocr/android_ios.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
import 'package:minio/minio.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:translator/translator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:path/path.dart' as p;

class PhotoService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  List<Map<String, dynamic>> _serverPhotos = [];
  final minio = Minio(
    endPoint: '91.197.98.163',
    port: 9000,
    accessKey: 'minioadmin',
    secretKey: 'minioadminpassword',
    useSSL: false,
  );

  Future<String> uploadPhotoToServer(AssetEntity localPhoto) async {
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print("Пользователь не авторизован");
        return '';
      }
      File file = await localPhoto.file as File;
      Map<String, IfdTag> exifData = await readExifFromBytes(await file.readAsBytes());
      DateTime creationDate = DateTime.now();
      if (exifData.containsKey('DateTimeOriginal')) {
        String? dateString = exifData['DateTimeOriginal']?.printable;
        if (dateString != null) {
          try {
            creationDate = _parseExifDate(dateString);
          } catch (e) {
            print("Ошибка парсинга даты EXIF: $e");
          }
        }
      }
      String bucketName = 'photo';
      final existingPhoto = await FirebaseFirestore.instance
          .collection('photos')
          .where('id', isEqualTo: localPhoto.title)
          .get();
      if (existingPhoto.docs.isNotEmpty) {
        print("Фото уже существует в Firestore.");
        return existingPhoto.docs.first['url'];
      }
      bool bucketExists = await minio.bucketExists(bucketName);
      if (!bucketExists) {
        await minio.makeBucket(bucketName);
      }
      var stream = file.openRead().transform(
        StreamTransformer<List<int>, Uint8List>.fromHandlers(
          handleData: (data, sink) {
            sink.add(Uint8List.fromList(data));
          },
        ),
      );
      await minio.putObject(bucketName, localPhoto.title!, stream);
      String downloadUrl = await minio.presignedGetObject(
        bucketName,
        localPhoto.title!,
        expires: 7 * 24 * 3600,
      );
      final List<String> tags = await _getTranslatedImageLabels(file);
      String extractedText = '';
      try {
        extractedText = await FlutterTesseractOcr.extractText(
          file.path,
          language: 'rus+eng',
        );
        extractedText = extractedText.trim();
      } catch (e) {
        print("Ошибка OCR с помощью Tesseract: $e");
      }
      

      await FirebaseFirestore.instance.collection('photos').doc(localPhoto.title).set({
  'id': localPhoto.title,
  'url': downloadUrl,
  'timestamp': DateTime.now(),
  'creation_date': creationDate.toIso8601String(),
  'exif': {
    'EXIF DateTimeOriginal': _convertToExifDateFormat(localPhoto.createDateTime.toIso8601String()),
  },
  'tags': tags,
  'ocrText': extractedText,
  'owner': {
    'uid': currentUser.uid,
    'email': currentUser.email ?? "Не указан",
    'displayName': currentUser.displayName ?? "Аноним",
    'photoURL': currentUser.photoURL ?? "",
  },
  'sharedWith': {},
  'favorites': [], 
  'latitude': '',
  'longitude': '',
});

      print("Файл успешно загружен в MinIO, информация сохранена в Firestore");
      return downloadUrl;
    } catch (e) {
      print("Ошибка при загрузке изображения: $e");
      return '';
    }
  }

  Future<bool> deleteServerPhoto(Map<String, dynamic> serverPhoto) async {
    try {
      String photoId = serverPhoto['id'];
      var querySnapshot = await FirebaseFirestore.instance
          .collection('photos')
          .where('id', isEqualTo: photoId)
          .limit(1)
          .get();
      if (querySnapshot.docs.isEmpty) {
        print("Фото с id $photoId не найдено в Firestore.");
        return false;
      }
      await querySnapshot.docs.first.reference.delete();
      await minio.removeObject('photo', photoId);
      return true;
    } catch (e) {
      print("Ошибка при удалении серверного фото: $e");
      return false;
    }
  }

  DateTime _parseExifDate(String date) {
    return DateTime.parse(date.replaceFirst(':', '-').replaceFirst(':', '-'));
  }

  String _convertToExifDateFormat(String originalDate) {
    DateTime dateTime = _parseDateString(originalDate);
    return _formatDateForExif(dateTime);
  }

  DateTime _parseDateString(String dateString) {
    try {
      DateTime dateTime = DateTime.parse(dateString);
      return dateTime;
    } catch (e) {
      print("Ошибка при парсинге строки даты: $e");
      return DateTime.now();
    }
  }

  String _formatDateForExif(DateTime dateTime) {
    return DateFormat('yyyy:MM:dd HH:mm:ss').format(dateTime);
  }

  Future<List<String>> _getTranslatedImageLabels(File file) async {
    final inputImage = InputImage.fromFile(file);
    final imageLabeler = ImageLabeler(options: ImageLabelerOptions());
    final List<ImageLabel> labels = await imageLabeler.processImage(inputImage);
    final List<String> tags = labels
        .where((label) => label.confidence >= 0.5)
        .map((label) => label.label)
        .toList();
    imageLabeler.close();
    return await _translateTags(tags);
  }

  Future<List<String>> _translateTags(List<String> tags) async {
    final translator = GoogleTranslator();
    List<String> translatedTags = [];
    for (String tag in tags) {
      try {
        final translation = await translator.translate(tag, from: 'en', to: 'ru');
        translatedTags.add(translation.text);
      } catch (e) {
        print("Ошибка перевода для '$tag': $e");
        translatedTags.add(tag); 
      }
    }
    return translatedTags;
  }

  Future<List<Map<String, dynamic>>> fetchPhotosFromFirestore() async {
    final userUid = _auth.currentUser?.uid;
    final snapshot = await FirebaseFirestore.instance.collection('photos').get();
    return _serverPhotos = snapshot.docs
        .map((doc) => doc.data())
        .where((photo) {
          final ownerUid = photo['owner']?['uid'] as String?;
          final sharedWith = photo['sharedWith'] as Map<String, dynamic>? ?? {};
          return ownerUid == userUid || sharedWith.containsKey(userUid);
        })
        .toList();
  }

  Future<void> saveLocalPhotoToServer(AssetEntity localPhoto, gm.LatLng? photoLocation) async {
    try {
      final existingPhoto = await FirebaseFirestore.instance
          .collection('photos')
          .where('id', isEqualTo: localPhoto.title)
          .get();
      if (existingPhoto.docs.isEmpty) {
        await pickAndUploadImage(localPhoto, photoLocation);
        print("Фото успешно сохранено на сервер");
      } else {
        print("Фото уже сохранено на сервере");
      }
    } catch (e) {
      print("Ошибка при сохранении локального фото на сервер: $e");
    }
  }

  Future<void> updatePhotoLocation(gm.LatLng location, Map<String, dynamic>? serverPhoto) async {
    final snap = await FirebaseFirestore.instance
        .collection('photos')
        .where('id', isEqualTo: serverPhoto!['id'])
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) {
      await snap.docs.first.reference.update({
        'latitude': location.latitude,
        'longitude': location.longitude,
      });
    } else {
      print("Документ с полем 'id' = '${serverPhoto['id']}' не существует.");
    }
  }

  Future<void> toggleFavorite(Map<String, dynamic> serverPhoto) async {
    try {
      final String photoId = serverPhoto['id'];
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;
      DocumentReference docRef =
          FirebaseFirestore.instance.collection('photos').doc(photoId);
      DocumentSnapshot snapshot = await docRef.get();
      if (snapshot.exists) {
        Map<String, dynamic>? data = snapshot.data() as Map<String, dynamic>?;
        List<dynamic> favorites = data?['favorites'] ?? [];
        if (favorites.contains(currentUser.uid)) {
          await docRef.update({
            'favorites': FieldValue.arrayRemove([currentUser.uid])
          });
        } else {
          await docRef.update({
            'favorites': FieldValue.arrayUnion([currentUser.uid])
          });
        }
      }
    } catch (e) {
      print("Ошибка при переключении избранного серверного фото: $e");
    }
  }

  Future<void> toggleFavoriteLocal(AssetEntity localPhoto) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;
      final docRef =
          FirebaseFirestore.instance.collection('userFavorites').doc(currentUser.uid);
      DocumentSnapshot snapshot = await docRef.get();
      List<dynamic> localFavs = [];
      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>?;
        localFavs = data?['localPhotos'] ?? [];
      }
      String id = localPhoto.title ?? "";
      if (id.isEmpty) return;
      if (localFavs.contains(id)) {
        await docRef.update({
          'localPhotos': FieldValue.arrayRemove([id])
        });
      } else {
        await docRef.set({
          'localPhotos': FieldValue.arrayUnion([id])
        }, SetOptions(merge: true));
      }
    } catch (e) {
      print("Ошибка при переключении избранного локального фото: $e");
    }
  }

  Future<void> removePhotosFromFolder(Set<dynamic> photos, String? folderId) async {
    List<String> photoIdsToRemove = [];
    for (var photo in photos) {
      String id = "";
      if (photo['type'] == 'server') {
        id = photo['photo']['id'];
      } else if (photo['type'] == 'local') {
        id = photo['photo'].title;
      }
      if (id.isNotEmpty) {
        photoIdsToRemove.add(id);
      }
    }
    await FirebaseFirestore.instance
        .collection('folders')
        .doc(folderId)
        .update({
      'photos': FieldValue.arrayRemove(photoIdsToRemove),
    });
  }

  Future<void> pickAndUploadImage(AssetEntity localPhoto, gm.LatLng? location) async {
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print("Пользователь не авторизован");
        return;
      }
      File file = await localPhoto.file as File;
      Map<String, IfdTag> exifData = await readExifFromBytes(await file.readAsBytes());
      DateTime creationDate = DateTime.now();
      if (exifData.containsKey('DateTimeOriginal')) {
        String? dateString = exifData['DateTimeOriginal']?.printable;
        if (dateString != null) {
          try {
            creationDate = _parseExifDate(dateString);
          } catch (e) {
            print("Ошибка парсинга даты EXIF: $e");
          }
        }
      }
      String bucketName = 'photo';
      bool bucketExists = await minio.bucketExists(bucketName);
      if (!bucketExists) {
        await minio.makeBucket(bucketName);
      }
      var stream = file.openRead().transform(
        StreamTransformer<List<int>, Uint8List>.fromHandlers(
          handleData: (data, sink) {
            sink.add(Uint8List.fromList(data));
          },
        ),
      );
      await minio.putObject(bucketName, localPhoto.title!, stream);
      String downloadUrl = await minio.presignedGetObject(
        bucketName,
        localPhoto.title!,
        expires: 7 * 24 * 3600,
      );
      final List<String> tags = await _getTranslatedImageLabels(file);
      String extractedText = '';
      try {
        extractedText = await FlutterTesseractOcr.extractText(
          file.path,
          language: 'rus+eng',
        );
        extractedText = extractedText.trim();
      } catch (e) {
        print("Ошибка OCR с помощью Tesseract: $e");
      }
      await FirebaseFirestore.instance
          .collection('photos')
          .doc(localPhoto.title)
          .set({
        'id': localPhoto.title,
        'url': downloadUrl,
        'timestamp': DateTime.now(),
        'creation_date': creationDate.toIso8601String(),
        'exif': {
          'EXIF DateTimeOriginal': _convertToExifDateFormat(
            localPhoto.createDateTime.toIso8601String(),
          ),
        },
        'tags': tags,
        'ocrText': extractedText,
        'owner': {
          'uid': currentUser.uid,
          'email': currentUser.email ?? "Не указан",
          'displayName': currentUser.displayName ?? "Аноним",
          'photoURL': currentUser.photoURL ?? "",
        },
        'sharedWith': {},
        if (location != null) ...{
          'latitude': location.latitude,
          'longitude': location.longitude,
        } else ...{
          'latitude': '',
          'longitude': '',
        },
      });
      print("Файл успешно загружен в MinIO, информация сохранена в Firestore");
    } catch (e) {
      print("Ошибка при загрузке изображения: $e");
    }
  }
Future<void> updatePhotosSharingForFolder(String folderId, Map<String, dynamic> newShare) async {
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('photos')
        .where('folderIds', arrayContains: folderId)
        .get();
    for (var doc in snapshot.docs) {
      final data = doc.data();
      Map<String, dynamic> folderShares = Map<String, dynamic>.from(data['folderShares'] ?? {});
      folderShares[folderId] = newShare;
      Map<String, dynamic> unionShared = {};
      folderShares.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          unionShared.addAll(value);
        }
      });
      await doc.reference.update({
        'folderShares': folderShares,
        'sharedWith': unionShared,
      });
    }
    print("Обновлено ${snapshot.docs.length} фото для папки $folderId");
  } catch (e) {
    print("Ошибка при обновлении шаринга для фотографий папки: $e");
  }
}




  Future<bool> uploadImage(File? selectedImage, User? currentUser) async {
    try {
      File file = selectedImage!;
      String fileName = p.basename(file.path);
      Map<String, IfdTag> exifData = await readExifFromBytes(await file.readAsBytes());
      DateTime creationDate = DateTime.now();
      if (exifData.containsKey('DateTimeOriginal')) {
        String? dateString = exifData['DateTimeOriginal']?.printable;
        if (dateString != null) {
          try {
            creationDate = _parseExifDate(dateString);
          } catch (e) {
            print("Ошибка парсинга даты EXIF: $e");
          }
        }
      }
      String bucketName = 'photo';
      final existingPhoto = await FirebaseFirestore.instance
          .collection('photos')
          .where('id', isEqualTo: fileName)
          .get();
      if (existingPhoto.docs.isNotEmpty) {
        return false;
      }
      bool bucketExists = await minio.bucketExists(bucketName);
      if (!bucketExists) {
        await minio.makeBucket(bucketName);
      }
      var stream = file.openRead().transform(
        StreamTransformer<List<int>, Uint8List>.fromHandlers(
          handleData: (data, sink) {
            sink.add(Uint8List.fromList(data));
          },
        ),
      );
      await minio.putObject(bucketName, fileName, stream);
      String downloadUrl = await minio.presignedGetObject(
        bucketName,
        fileName,
        expires: 7 * 24 * 3600,
      );
      final List<String> tags = await _getTranslatedImageLabels(file);
      String extractedText = '';
      try {
        extractedText = await FlutterTesseractOcr.extractText(
          file.path,
          language: 'rus+eng',
        );
        extractedText = extractedText.trim();
      } catch (e) {
        print("Ошибка OCR с помощью Tesseract: $e");
      }
      await FirebaseFirestore.instance.collection('photos').add({
        'id': fileName,
        'url': downloadUrl,
        'timestamp': DateTime.now(),
        'creation_date': creationDate.toIso8601String(),
        'exif': exifData.map((key, value) => MapEntry(key, value.printable)),
        'tags': tags,
        'ocrText': extractedText,
        'owner': {
          'uid': currentUser?.uid,
          'email': currentUser?.email ?? "Не указан",
          'displayName': currentUser?.displayName ?? "Аноним",
          'photoURL': currentUser?.photoURL ?? "",
        },
        'sharedWith': {},
        'longitude': '',
        'latitude': '',
      });
      return true;
    } catch (e) {
      print("Ошибка при загрузке изображения: $e");
      return false;
    }
  }
}
