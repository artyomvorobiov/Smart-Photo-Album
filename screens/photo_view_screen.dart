import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:photo_manager/photo_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:minio/minio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:photo_view/photo_view_gallery.dart';
import 'package:photo_view/photo_view.dart';
import 'package:trip/services/photo_service.dart';
import 'package:trip/services/profile_service.dart';

class PhotoViewScreen extends StatefulWidget {
  final AssetEntity? localPhoto;
  final Map<String, dynamic>? serverPhoto; 
  final List<dynamic>? photoList; 
  final int initialIndex; 
  final Function? onDelete; 
  final String? folderId; 
  PhotoViewScreen.local({
    required this.localPhoto,
    this.onDelete,
    this.folderId,
  })  : serverPhoto = null,
        photoList = null,
        initialIndex = 0;
  PhotoViewScreen.server({
    required this.serverPhoto,
    this.onDelete,
    this.folderId,
  })  : localPhoto = null,
        photoList = null,
        initialIndex = 0;
  PhotoViewScreen.multiple({
    required this.photoList,
    this.initialIndex = 0,
    this.onDelete,
    this.folderId,
  })  : localPhoto = null,
        serverPhoto = null;

  @override
  State<PhotoViewScreen> createState() => _PhotoViewScreenState();
}

class _PhotoViewScreenState extends State<PhotoViewScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final PhotoService _photoService = PhotoService();
  final ProfileService _profileService = ProfileService();

  User? _currentUser;
  gm.LatLng? _photoLocation;
  gm.GoogleMapController? _mapController;
  List<Map<String, dynamic>> _predictions = [];
  String googleApiKey = "AIzaSyCQ8vbtQMgNbgIRonzzUo234QFhF_4IzFE"; 

  final minio = Minio(
    endPoint: '91.197.98.163',
    port: 9000,
    accessKey: 'minioadmin',
    secretKey: 'minioadminpassword',
    useSSL: false,
  );
  int _currentIndex = 0;
  PageController? _pageController;
  bool _isLoading = false;
  late AnimationController _loadingController;

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    if (widget.photoList != null) {
      _currentIndex = widget.initialIndex;
      _pageController = PageController(initialPage: _currentIndex);
    }
    _loadPhotoLocation();
    _loadingController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();
  }

  @override
  void dispose() {
    _loadingController.dispose();
    super.dispose();
  }
  dynamic get currentPhoto {
    if (widget.photoList != null) {
      return widget.photoList![_currentIndex];
    } else if (widget.localPhoto != null) {
      return widget.localPhoto;
    } else {
      return widget.serverPhoto;
    }
  }
  void _loadPhotoLocation() {
    var photo = currentPhoto;
    if (photo != null &&
        photo is Map<String, dynamic> &&
        photo.containsKey('latitude') &&
        photo.containsKey('longitude')) {
      final latValue = photo['latitude'];
      final lngValue = photo['longitude'];
      if (latValue is num && lngValue is num) {
        _photoLocation = gm.LatLng(latValue.toDouble(), lngValue.toDouble());
      } else if (latValue is String &&
          latValue.isNotEmpty &&
          lngValue is String &&
          lngValue.isNotEmpty) {
        final latDouble = double.tryParse(latValue);
        final lngDouble = double.tryParse(lngValue);
        if (latDouble != null && lngDouble != null) {
          _photoLocation = gm.LatLng(latDouble, lngDouble);
        }
      }
    }
  }
  Future<void> _updatePhotoLocation(gm.LatLng location) async {
    setState(() {
      _photoLocation = location;
    });
    if (currentPhoto is Map<String, dynamic>) {
      await _photoService.updatePhotoLocation(location, currentPhoto);
      _showCustomMessage('Геолокация обновлена на сервере');
    } else if (currentPhoto is AssetEntity) {
      _onPressUpload();
      _showCustomMessage('Геолокация установлена');
    }
  }
  void _showLocationPicker() {
    TextEditingController searchController = TextEditingController();
    List<Map<String, dynamic>> localPredictions = [];
    gm.LatLng? tempLocation = _photoLocation;
    if (tempLocation != null) {
      _reverseGeocode(tempLocation).then((addr) {
        if (addr != null && searchController.text.isEmpty) {
          searchController.text = addr;
        }
      });
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white.withOpacity(0.9),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateModal) {
            Future<void> _onSearchChanged(String input) async {
              if (input.isEmpty) {
                setStateModal(() => localPredictions = []);
                return;
              }
              final url = "https://maps.googleapis.com/maps/api/place/autocomplete/json?"
                  "input=$input"
                  "&language=ru"
                  "&components=country:ru"
                  "&key=$googleApiKey";
              try {
                final response = await http.get(Uri.parse(url));
                if (response.statusCode == 200) {
                  final data = json.decode(response.body);
                  if (data["status"] == "OK") {
                    final preds = data["predictions"] as List;
                    setStateModal(() {
                      localPredictions = preds.map((item) => {
                        "description": item["description"],
                        "place_id": item["place_id"],
                      }).toList();
                    });
                  } else {
                    setStateModal(() => localPredictions = []);
                  }
                }
              } catch (e) {
                debugPrint("Ошибка автокомплита: $e");
              }
            }

            Future<void> _onPredictionTap(Map<String, dynamic> prediction) async {
              setStateModal(() => localPredictions = []);
              final placeId = prediction["place_id"];
              final detailsUrl =
                  "https://maps.googleapis.com/maps/api/place/details/json?"
                  "place_id=$placeId"
                  "&language=ru"
                  "&key=$googleApiKey";
              try {
                final response = await http.get(Uri.parse(detailsUrl));
                if (response.statusCode == 200) {
                  final data = json.decode(response.body);
                  if (data["status"] == "OK") {
                    final result = data["result"];
                    final geometry = result["geometry"];
                    final loc = geometry["location"];
                    double lat = loc["lat"];
                    double lng = loc["lng"];
                    tempLocation = gm.LatLng(lat, lng);
                    searchController.text = prediction["description"] ?? "";
                  }
                }
              } catch (e) {
                debugPrint("Ошибка place details: $e");
              }
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.7,
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 6,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey[400],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: TextField(
                          controller: searchController,
                          decoration: InputDecoration(
                            hintText: "Введите адрес или место",
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                          ),
                          onChanged: _onSearchChanged,
                        ),
                      ),
                      if (localPredictions.isNotEmpty)
                        Expanded(
                          child: ListView.builder(
                            itemCount: localPredictions.length,
                            itemBuilder: (context, index) {
                              final p = localPredictions[index];
                              return ListTile(
                                leading: const Icon(Icons.location_on),
                                title: Text(p["description"] ?? ""),
                                onTap: () => _onPredictionTap(p),
                              );
                            },
                          ),
                        )
                      else
                        const Expanded(
                          child: Center(
                            child: Text("Нет подсказок..."),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.check),
                          label: const Text("Сохранить местоположение"),
                          onPressed: () {
                            Navigator.pop(context);
                            if (tempLocation != null) {
                              _updatePhotoLocation(tempLocation!);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
  Future<String?> _reverseGeocode(gm.LatLng location) async {
    final lat = location.latitude;
    final lng = location.longitude;
    final url = "https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng"
        "&language=ru"
        "&key=$googleApiKey";
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data["results"] as List?;
        if (results != null && results.isNotEmpty) {
          return results[0]["formatted_address"];
        }
      }
    } catch (e) {
      debugPrint("Ошибка reverseGeocode: $e");
    }
    return null;
  }
  void _onPressSave() async {
    if (currentPhoto == null || currentPhoto is! Map<String, dynamic>) return;
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    final sharedWith = (currentPhoto as Map<String, dynamic>)['sharedWith'] as Map<String, dynamic>? ?? {};
    final String? userPermission = sharedWith[currentUser.uid];
    final ownerUid = (currentPhoto as Map<String, dynamic>)['owner']?['uid'];
    final bool isOwner = ownerUid == currentUser.uid;
    final bool canSave = (currentPhoto is AssetEntity) || isOwner || userPermission == 'save';
    if (!canSave) {
      _showCustomMessage("Нет прав для сохранения фото.", icon: Icons.error_outline, backgroundColor: Colors.redAccent);
      return;
    }
    await _saveServerPhotoToGallery(currentPhoto as Map<String, dynamic>);
    _showCustomMessage("Фото сохранено в галерею");
  }
  Future<void> _saveServerPhotoToGallery(Map<String, dynamic> serverPhoto) async {
    try {
      final String imageUrl = serverPhoto['url'];
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final asset = await _saveImageToGallery(bytes, serverPhoto['id']);
        if (asset != null) {
          debugPrint("Фото успешно сохранено в галерею");
        } else {
          debugPrint("Не удалось сохранить фото");
        }
      } else {
        debugPrint("Ошибка при загрузке фото с сервера");
      }
    } catch (e) {
      debugPrint("Ошибка при сохранении фото: $e");
    }
  }

  Future<AssetEntity?> _saveImageToGallery(Uint8List bytes, String name) async {
    return await PhotoManager.editor.saveImage(
      bytes,
      title: name,
      filename: name,
    );
  }
  void _onPressUpload() async {
    if (currentPhoto is AssetEntity) {
      setState(() {
        _isLoading = true;
      });
      try {
        await _photoService.saveLocalPhotoToServer(currentPhoto, _photoLocation);
        setState(() {
          _isLoading = false;
        });
        _showCustomMessage("Фото сохранено на сервер");
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        _showCustomMessage("Ошибка при сохранении фото: $e",
            icon: Icons.error_outline, backgroundColor: Colors.redAccent);
      }
    }
  }
  void _onPressDelete() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      _showCustomMessage("Пользователь не авторизован.", icon: Icons.error_outline, backgroundColor: Colors.redAccent);
      return;
    }
    if (currentPhoto is Map<String, dynamic>) {
      final ownerUid = (currentPhoto as Map<String, dynamic>)['owner']?['uid'];
      final sharedWith = (currentPhoto as Map<String, dynamic>)['sharedWith'] as Map<String, dynamic>? ?? {};
      final userPermission = sharedWith[currentUser.uid];
      final bool isOwner = (ownerUid == currentUser.uid);
      final bool canDelete = isOwner || userPermission == 'save';
      if (!canDelete) {
        _showCustomMessage("Нет прав для удаления.", icon: Icons.error_outline, backgroundColor: Colors.redAccent);
        return;
      }
    }
    if (widget.folderId != null) {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Подтверждение удаления"),
          content: const Text("Удалить фото только из папки или полностью из галереи?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, "folder"),
              child: const Text("Из папки"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, "gallery"),
              child: const Text("Из галереи"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, "cancel"),
              child: const Text("Отмена"),
            ),
          ],
        ),
      );
      if (choice == "cancel" || choice == null) return;
      if (choice == "folder") {
        String photoId = "";
        if (currentPhoto is Map<String, dynamic>) {
          photoId = currentPhoto['id'];
        } else if (currentPhoto is AssetEntity) {
          photoId = currentPhoto.title ?? "";
        }
        if (photoId.isNotEmpty) {
          try {
            await _firestore
                .collection('folders')
                .doc(widget.folderId)
                .update({
              'photos': FieldValue.arrayRemove([photoId])
            });
            _showCustomMessage("Фото удалено из папки");
            if (widget.onDelete != null) {
              widget.onDelete!();
            }
            Navigator.pop(context);
            return;
          } catch (e) {
            _showCustomMessage("Ошибка при удалении из папки: $e",
                icon: Icons.error_outline, backgroundColor: Colors.redAccent);
            return;
          }
        }
      }
    }
    bool success = false;
    if (currentPhoto is AssetEntity) {
      success = await _deleteLocalPhoto(currentPhoto);
    } else if (currentPhoto is Map<String, dynamic>) {
      success = await _deleteServerPhoto(currentPhoto);
    }
    if (success) {
      _showCustomMessage("Фото удалено");
      if (widget.onDelete != null) {
        widget.onDelete!();
      }
      Navigator.pop(context);
    } else {
      _showCustomMessage("Ошибка при удалении",
          icon: Icons.error_outline, backgroundColor: Colors.redAccent);
    }
  }
  Future<bool> _deleteLocalPhoto(AssetEntity photo) async {
    bool confirmed = await _showDeleteConfirmationDialog(
      context,
      'Удаление локального фото',
      'Вы уверены, что хотите удалить это фото локально?',
    );
    if (!confirmed) return false;
    try {
      final success = await PhotoManager.editor.deleteWithIds([photo.id]);
      return success.isNotEmpty;
    } catch (e) {
      debugPrint("Ошибка при удалении локальной фотографии: $e");
      return false;
    }
  }
  Future<bool> _deleteServerPhoto(Map<String, dynamic> serverPhoto) async {
    bool confirmed = await _showDeleteConfirmationDialog(
      context,
      'Удаление серверного фото',
      'Вы уверены, что хотите удалить это фото с сервера?',
    );
    if (!confirmed) return false;
    try {
      final photoId = serverPhoto['id'];
      final querySnapshot = await _firestore
          .collection('photos')
          .where('id', isEqualTo: photoId)
          .limit(1)
          .get();
      if (querySnapshot.docs.isEmpty) {
        _showCustomMessage('Фото с ID $photoId не найдено.',
            icon: Icons.error_outline, backgroundColor: Colors.redAccent);
        return false;
      }
      await querySnapshot.docs.first.reference.delete();
      await minio.removeObject('photo', photoId);
      return true;
    } catch (e) {
      debugPrint("Ошибка при удалении серверного фото: $e");
      return false;
    }
  }
  Future<bool> _showDeleteConfirmationDialog(
    BuildContext context,
    String title,
    String message,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          content: Text(message),
          actions: [
            TextButton(
              child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            ElevatedButton(
              child: const Text('Удалить'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }
  void _onPressShare() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      _showCustomMessage("Пользователь не авторизован.", icon: Icons.error_outline, backgroundColor: Colors.redAccent);
      return;
    }
    if (currentPhoto is Map<String, dynamic>) {
      final ownerUid = (currentPhoto as Map<String, dynamic>)['owner']?['uid'];
      final sharedWith = (currentPhoto as Map<String, dynamic>)['sharedWith'] as Map<String, dynamic>? ?? {};
      final userPermission = sharedWith[currentUser.uid];
      final bool isOwner = ownerUid == currentUser.uid;
      final bool canShare = isOwner || userPermission == 'save';
      if (!canShare) {
        _showCustomMessage("Нет прав для отправки фото.", icon: Icons.error_outline, backgroundColor: Colors.redAccent);
        return;
      }
    }
    try {
      final usersList = await _profileService.getUsersList();
      print(usersList);
      final currentUid = currentUser.uid;
      final fullUsers = usersList.where((u) {
        final uId = u['id'];
        if (uId == null) return false;
        if (uId == currentUid) return false;
        return true;
      }).toList();
      final selectedUsers = await _showUserSelectionBottomSheet(context, fullUsers);
      if (selectedUsers == null || selectedUsers.isEmpty) {
        _showCustomMessage("Никто не выбран для отправки.", icon: Icons.error_outline, backgroundColor: Colors.redAccent);
        return;
      }
      if (currentPhoto is AssetEntity) {
        await _shareLocalPhoto(currentPhoto, selectedUsers);
      } else if (currentPhoto is Map<String, dynamic>) {
        final success = await _shareServerPhoto(currentPhoto, selectedUsers);
        if (!success) {
          _showCustomMessage("Ошибка при отправке фотографии.", icon: Icons.error_outline, backgroundColor: Colors.redAccent);
          return;
        }
      }
      _showCustomMessage("Фото успешно отправлено");
    } catch (e) {
      _showCustomMessage("Ошибка при отправке: $e", icon: Icons.error_outline, backgroundColor: Colors.redAccent);
    }
  }
  Future<List<Map<String, dynamic>>?> _showUserSelectionBottomSheet(
    BuildContext context,
    List<Map<String, dynamic>> users,
  ) async {
    final Map<String, dynamic> sharedMap =
        (currentPhoto is Map<String, dynamic>)
            ? (currentPhoto as Map<String, dynamic>)['sharedWith'] as Map<String, dynamic>? ?? {}
            : {};
    final Map<String, String> userPermissions = {};
    for (var entry in sharedMap.entries) {
      final userId = entry.key;
      final permission = entry.value;
      if (permission is String) {
        userPermissions[userId] = permission;
      } else {
        userPermissions[userId] = 'view';
      }
    }
    final fullUsers = users;
    final TextEditingController searchController = TextEditingController();
    List<Map<String, dynamic>> filteredUsers = [];
    void _filter(String query) {
      final lowerQuery = query.trim().toLowerCase();
      if (lowerQuery.isEmpty) {
        filteredUsers = [];
      } else {
        final matched = fullUsers.where((u) {
          final displayName = (u['displayName'] ?? '').toString().toLowerCase();
          final email = (u['email'] ?? '').toString().toLowerCase();
          return displayName.contains(lowerQuery) || email.contains(lowerQuery);
        }).take(10).toList();
        for (final selectedUid in userPermissions.keys) {
          final alreadyIn = matched.any((u) => u['id'] == selectedUid);
          if (!alreadyIn) {
            final found = fullUsers.firstWhere((u) => u['id'] == selectedUid, orElse: () => {});
            if (found.isNotEmpty) matched.add(found);
          }
        }
        filteredUsers = matched;
      }
    }
    Widget _buildPermissionChips(
      String userId,
      StateSetter setStateModal,
      String currentQuery,
      void Function(String) filterCallback,
    ) {
      final List<Map<String, dynamic>> permissionOptions = [
        {
          'value': 'view',
          'label': 'Только просмотр',
          'icon': Icons.visibility,
          'color': Colors.grey,
        },
        {
          'value': 'save',
          'label': 'Просмотр + Скачивание',
          'icon': Icons.download,
          'color': Colors.green,
        },
      ];
      final currentValue = userPermissions[userId];
      return Wrap(
        spacing: 8,
        children: permissionOptions.map((option) {
          final isSelected = (option['value'] == currentValue);
          return ChoiceChip(
            selected: isSelected,
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  option['icon'] as IconData,
                  size: 18,
                  color: isSelected ? Colors.white : (option['color'] as Color),
                ),
                const SizedBox(width: 4),
                Text(
                  option['label'] as String,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.black,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            selectedColor: (option['color'] as Color).withOpacity(0.8),
            backgroundColor: Colors.grey[200],
            onSelected: (bool selected) {
              setStateModal(() {
                if (selected) {
                  userPermissions[userId] = option['value'] as String;
                }
                filterCallback(currentQuery);
              });
            },
          );
        }).toList(),
      );
    }
    return await showModalBottomSheet<List<Map<String, dynamic>>>( 
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return FractionallySizedBox(
          heightFactor: 0.6,
          child: StatefulBuilder(
            builder: (context, setStateModal) {
              if (filteredUsers.isEmpty && userPermissions.isNotEmpty) {
                _filter('');
              }
              return Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 8, bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Text(
                    'Выберите пользователей и права',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: 'Введите ник или email для поиска',
                        prefixIcon: const Icon(Icons.search),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (val) {
                        setStateModal(() {
                          _filter(val);
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: filteredUsers.isEmpty
                        ? Center(
                            child: Text(
                              "Введите ник или email для поиска",
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredUsers.length,
                            itemBuilder: (context, index) {
                              final user = filteredUsers[index];
                              final userId = user['id'] as String?;
                              if (userId == null) return const SizedBox.shrink();
                              final bool isSelected = userPermissions.containsKey(userId);
                              return Card(
                                elevation: 2,
                                margin: const EdgeInsets.symmetric(
                                  vertical: 4,
                                  horizontal: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ListTile(
                                  tileColor: isSelected
                                      ? Colors.blue.withOpacity(0.1)
                                      : null,
                                  leading: Checkbox(
                                    value: isSelected,
                                    onChanged: (bool? selected) {
                                      setStateModal(() {
                                        if (selected == true) {
                                          userPermissions[userId] = "view";
                                        } else {
                                          userPermissions.remove(userId);
                                        }
                                        _filter(searchController.text);
                                      });
                                    },
                                  ),
                                  title: Text(
                                    user['displayName'] ?? 'Неизвестный',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        user['email'] ?? '',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(height: 4),
                                      if (isSelected)
                                        _buildPermissionChips(
                                          userId,
                                          setStateModal,
                                          searchController.text,
                                          _filter,
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context, null),
                            child: const Text(
                              'Отмена',
                              style: TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              final result = userPermissions.entries.map((e) {
                                return {
                                  'id': e.key,
                                  'permission': e.value,
                                };
                              }).toList();
                              Navigator.pop(context, result);
                            },
                            child: const Text('Сохранить',
                                style: TextStyle(fontSize: 16)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
  Future<bool> _shareServerPhoto(
    Map<String, dynamic> serverPhoto,
    List<Map<String, dynamic>> selectedUsers,
  ) async {
    try {
      final photoId = serverPhoto['id'];
      final snapshot = await _firestore
          .collection('photos')
          .where('id', isEqualTo: photoId)
          .limit(1)
          .get();
      if (snapshot.docs.isEmpty) {
        debugPrint("Фото с id $photoId не найдено");
        return false;
      }
      final docRef = snapshot.docs.first.reference;
      final currentShared = (serverPhoto['sharedWith'] ?? {}) as Map<String, dynamic>;
      for (var user in selectedUsers) {
        currentShared[user['id']] = user['permission'];
      }
      await docRef.update({'sharedWith': currentShared});
      return true;
    } catch (e) {
      debugPrint("Ошибка при отправке серверного фото: $e");
      return false;
    }
  }
  Future<void> _shareLocalPhoto(
    AssetEntity localPhoto,
    List<Map<String, dynamic>> selectedUsers,
  ) async {
    try {
      final existing = await _firestore
          .collection('photos')
          .where('id', isEqualTo: localPhoto.title)
          .get();
      final Map<String, dynamic> newShared = {};
      for (var user in selectedUsers) {
        newShared[user['id']] = user['permission'];
      }
      if (existing.docs.isNotEmpty) {
        final docRef = existing.docs.first.reference;
        final oldData = existing.docs.first.data();
        final oldShared = (oldData['sharedWith'] ?? {}) as Map<String, dynamic>;
        newShared.forEach((k, v) {
          oldShared[k] = v;
        });
        await docRef.update({'sharedWith': oldShared});
      } else {
        await _photoService.pickAndUploadImage(localPhoto, _photoLocation);
        final uploaded = await _firestore
            .collection('photos')
            .where('id', isEqualTo: localPhoto.title)
            .get();
        if (uploaded.docs.isNotEmpty) {
          final docRef = uploaded.docs.first.reference;
          await docRef.update({'sharedWith': newShared});
        }
      }
    } catch (e) {
      debugPrint("Ошибка при отправке локального фото: $e");
    }
  }
  void _showNoAccessDialog() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Недостаточно прав"),
          content: const Text(
            "У вас нет разрешения на выполнение этого действия. "
            "Только владелец или пользователь с правом 'Просмотр и скачивание' могут это делать.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        );
      },
    );
  }
  void _showCustomMessage(String message,
      {IconData icon = Icons.check_circle_outline, Color backgroundColor = Colors.green}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: backgroundColor,
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }
Widget _buildLoadingOverlay() {
  return Container(
    color: Colors.black.withOpacity(0.6),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _loadingController,
            builder: (context, child) {
              return Transform.rotate(
                angle: _loadingController.value * 6.28,
                child: child,
              );
            },
            child: ClipOval( 
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFFC5C7D), Color(0xFF6A82FB)],
                  ),
                ),
                child: const Icon(
                  Icons.photo,
                  size: 50,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "Пожалуйста, подождите...",
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.none, 
            ),
          )
        ],
      ),
    ),
  );
}



  @override
  Widget build(BuildContext context) {
    final currentUser = _auth.currentUser;
    bool isLocal;
    String? ownerUid;
    Map<String, dynamic> sharedWith = {};
    if (currentPhoto is AssetEntity) {
      isLocal = true;
    } else {
      isLocal = false;
      ownerUid = (currentPhoto as Map<String, dynamic>)['owner']?['uid'];
      sharedWith = (currentPhoto as Map<String, dynamic>)['sharedWith'] as Map<String, dynamic>? ?? {};
    }
    final bool isOwner = (ownerUid != null && ownerUid == currentUser?.uid);
    final userPermission = sharedWith[currentUser?.uid];
    final bool canSave = isLocal || isOwner || userPermission == 'save';

    return Stack(
      children: [
        Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.black.withOpacity(0.3),
            elevation: 0,
            actions: [
              if (currentPhoto is Map<String, dynamic>)
                IconButton(
                  icon: const Icon(Icons.save_alt),
                  tooltip: "Сохранить на устройство",
                  onPressed: canSave ? _onPressSave : _showNoAccessDialog,
                ),
              if (currentPhoto is AssetEntity)
                IconButton(
                  icon: const Icon(Icons.cloud_upload),
                  tooltip: "Загрузить на сервер",
                  onPressed: _onPressUpload,
                ),
              IconButton(
                icon: const Icon(Icons.delete),
                tooltip: "Удалить",
                onPressed: canSave ? _onPressDelete : _showNoAccessDialog,
              ),
              FavoriteIcon(
                photo: currentPhoto,
                photoService: _photoService,
                auth: _auth,
                firestore: _firestore,
              ),
              IconButton(
                icon: const Icon(Icons.location_on),
                tooltip: "Обновить геолокацию",
                onPressed: canSave ? _showLocationPicker : _showNoAccessDialog,
              ),
              IconButton(
                icon: const Icon(Icons.share),
                tooltip: "Поделиться",
                onPressed: canSave ? _onPressShare : _showNoAccessDialog,
              ),
            ],
          ),
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF89CFFD),
                  Color(0xFFB084CC),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: _buildPhotoViewer(),
                ),
              ),
            ),
          ),
        ),
        if (_isLoading) _buildLoadingOverlay(),
      ],
    );
  }
  Widget _buildPhotoViewer() {
    if (widget.photoList != null) {
      return PhotoViewGallery.builder(
        itemCount: widget.photoList!.length,
        pageController: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
            _loadPhotoLocation();
          });
        },
        builder: (context, index) {
          final photoItem = widget.photoList![index];
          if (photoItem is Map<String, dynamic>) {
            return PhotoViewGalleryPageOptions(
              imageProvider: NetworkImage(photoItem['url']),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 2,
              initialScale: PhotoViewComputedScale.contained,
              heroAttributes: PhotoViewHeroAttributes(tag: '$index'),
            );
          } else if (photoItem is AssetEntity) {
            return PhotoViewGalleryPageOptions.customChild(
              child: FutureBuilder<File?>(
                future: photoItem.file,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasData && snapshot.data != null) {
                    return Image.file(snapshot.data!, fit: BoxFit.contain);
                  } else {
                    return const Center(child: Text("Не удалось загрузить фото."));
                  }
                },
              ),
              childSize: MediaQuery.of(context).size,
              initialScale: PhotoViewComputedScale.contained,
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 2,
              heroAttributes: PhotoViewHeroAttributes(tag: '$index'),
            );
          } else {
            return PhotoViewGalleryPageOptions.customChild(
              child: const Center(child: Text("Ошибка: неверный формат фото.")),
              childSize: MediaQuery.of(context).size,
              initialScale: PhotoViewComputedScale.contained,
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 2,
              heroAttributes: PhotoViewHeroAttributes(tag: '$index'),
            );
          }
        },
        backgroundDecoration: const BoxDecoration(color: Colors.transparent),
      );
    } else if (currentPhoto is AssetEntity) {
      return FutureBuilder<File?>(
        future: (currentPhoto as AssetEntity).file,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasData && snapshot.data != null) {
            return PhotoView(
              imageProvider: FileImage(snapshot.data!),
              backgroundDecoration: const BoxDecoration(color: Colors.transparent),
            );
          } else {
            return const Center(child: Text("Не удалось загрузить фото."));
          }
        },
      );
    } else if (currentPhoto is Map<String, dynamic>) {
      return PhotoView(
        imageProvider: NetworkImage(currentPhoto['url']),
        backgroundDecoration: BoxDecoration(color: Colors.transparent),
      );
    } else {
      return const Center(child: Text("Ошибка: фото не найдено."));
    }
  }
}

class FavoriteIcon extends StatefulWidget {
  final dynamic photo;
  final PhotoService photoService;
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  const FavoriteIcon({
    Key? key,
    required this.photo,
    required this.photoService,
    required this.auth,
    required this.firestore,
  }) : super(key: key);

  @override
  _FavoriteIconState createState() => _FavoriteIconState();
}

class _FavoriteIconState extends State<FavoriteIcon> {
  bool _isFavorite = false;
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.auth.currentUser;
    _loadFavoriteState();
  }

  @override
  void didUpdateWidget(FavoriteIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo != widget.photo) {
      _loadFavoriteState();
    }
  }

  Future<void> _loadFavoriteState() async {
    if (_currentUser == null) return;
    if (widget.photo is AssetEntity) {
      final doc = await widget.firestore
          .collection('userFavorites')
          .doc(_currentUser!.uid)
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        final List<dynamic> localFavs = data?['localPhotos'] ?? [];
        setState(() {
          _isFavorite = localFavs.contains((widget.photo as AssetEntity).title);
        });
      }
    } else if (widget.photo is Map<String, dynamic>) {
      final List<dynamic> favorites = widget.photo['favorites'] ?? [];
      setState(() {
        _isFavorite = favorites.contains(_currentUser?.uid);
      });
    }
  }

  Future<void> _toggleFavorite() async {
  if (widget.photo is Map<String, dynamic>) {
    try {
      await widget.photoService.toggleFavorite(widget.photo);
      final docRef = widget.firestore.collection('photos').doc(widget.photo['id']);
      final snap = await docRef.get();
      if (snap.exists) {
        final updatedData = snap.data();
        setState(() {
          _isFavorite = (updatedData?['favorites'] ?? []).contains(_currentUser?.uid);
        });
      }
      _showCustomMessage("Статус избранного обновлён");
    } catch (e) {
      _showCustomMessage("Ошибка при обновлении избранного: $e",
          icon: Icons.error_outline, backgroundColor: Colors.redAccent);
    }
  } else if (widget.photo is AssetEntity) {
    await widget.photoService.toggleFavoriteLocal(widget.photo);
    await _loadFavoriteState();
    _showCustomMessage("Статус избранного обновлён");
  }
}


 void _showCustomMessage(
  String message, {
  IconData icon = Icons.check_circle_outline,
  Color backgroundColor = Colors.green,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: backgroundColor,
      content: Row(
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 3),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        _isFavorite ? Icons.star : Icons.star_border,
        color: Colors.yellowAccent,
      ),
      tooltip: "Избранное",
      onPressed: _toggleFavorite,
    );
  }
}

