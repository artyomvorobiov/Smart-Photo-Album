import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:trip/screens/gallery_screen.dart';
import 'package:trip/screens/user_search.dart';
import 'package:trip/services/photo_service.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;

enum AlbumTheme { classic, modern, event, vintage, bright, night, pastel }

String _getThemeName(AlbumTheme theme) {
  switch (theme) {
    case AlbumTheme.classic:
      return "Классический";
    case AlbumTheme.modern:
      return "Современный";
    case AlbumTheme.event:
      return "Мероприятие";
    case AlbumTheme.vintage:
      return "Винтаж";
    case AlbumTheme.bright:
      return "Яркий";
    case AlbumTheme.night:
      return "Ночной";
    case AlbumTheme.pastel:
      return "Пастельный";
    default:
      return "Неизвестно";
  }
}

class CreateAlbumScreen extends StatefulWidget {
  final Map<String, dynamic>? albumData;
  final List<dynamic>? selected;

  const CreateAlbumScreen({Key? key, this.albumData, this.selected})
      : super(key: key);

  @override
  _CreateAlbumScreenState createState() => _CreateAlbumScreenState();
}

class _CreateAlbumScreenState extends State<CreateAlbumScreen>
    with SingleTickerProviderStateMixin {
  List<dynamic> _selectedPhotos = [];
  final PhotoService _photoService = PhotoService();
  double _duration = 5.0;
  bool _saving = false;
  List<dynamic>? selected = [];
  final TextEditingController _nameController = TextEditingController();
  bool a = false;
  final FirebaseAuth _auth = FirebaseAuth.instance;


  Map<String, dynamic> _sharedUsers = {};

  bool isOwner = true;
  bool canEditSettings = true;
  bool canAddPhotos = true;
  bool canDeletePhotos = true;
  bool canManageAccess = true;

  AlbumTheme _selectedTheme = AlbumTheme.classic;
  late AnimationController _loadingController;

  @override
  void initState() {
    super.initState();
    _loadingController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();
    final currentUser = _auth.currentUser;
    if (widget.albumData != null) {
      _nameController.text = widget.albumData!['name'] ?? '';
      _duration = widget.albumData!['duration']?.toDouble() ?? 5.0;
      _selectedPhotos = widget.albumData!['photos'] ?? [];
      if (widget.albumData!['theme'] != null) {
        String themeStr = widget.albumData!['theme'];
        _selectedTheme = AlbumTheme.values.firstWhere(
            (e) => e.toString().split('.').last == themeStr,
            orElse: () => AlbumTheme.classic);
      }
      final sharedMap = widget.albumData!['sharedWith'];
      if (sharedMap != null) {
        _loadSharedUsers(sharedMap).then((_) {
          isOwner = widget.albumData!['owner'] == currentUser?.uid;
          if (!isOwner) {
            final userPerms = widget.albumData!['sharedWith'][currentUser?.uid];
            if (userPerms is Map) {
              canEditSettings = (userPerms['editAlbumSettings'] == true ||
                  userPerms['manageAccess'] == true);
              canAddPhotos = true;
              canDeletePhotos = userPerms['deletePhotos'] == true;
              canManageAccess = userPerms['manageAccess'] == true;
            } else {
              canEditSettings = (userPerms == 'edit');
              canAddPhotos = true;
              canDeletePhotos = (userPerms == 'edit');
              canManageAccess = false;
            }
          } else {
            canEditSettings = true;
            canAddPhotos = true;
            canDeletePhotos = true;
            canManageAccess = true;
          }
          setState(() {});
        });
      }
    }

    if (widget.selected != null) {
      selected = widget.selected;
      a = true;
      _pickPhotos();
      a = false;
    }
  }

  @override
  void dispose() {
    _loadingController.dispose();
    super.dispose();
  }

  Future<void> _loadSharedUsers(Map<String, dynamic> sharedMap) async {
    final loadedData = <String, dynamic>{};
    for (final entry in sharedMap.entries) {
      final uid = entry.key;
      final permissionOrMap = entry.value;
      try {
        final userDoc =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final userData = userDoc.data() as Map<String, dynamic>? ?? {};
        final nickname = userData['nickname'] ?? uid;
        final email = userData['email'] ?? '';
        Map<String, bool> permissions;
        if (permissionOrMap is String) {
          if (permissionOrMap == 'view') {
            permissions = {
              'deletePhotos': false,
              'addPhotos': false,
              'editAlbumSettings': false,
              'manageAccess': false,
            };
          } else if (permissionOrMap == 'add') {
            permissions = {
              'deletePhotos': false,
              'addPhotos': true,
              'editAlbumSettings': false,
              'manageAccess': false,
            };
          } else if (permissionOrMap == 'edit') {
            permissions = {
              'deletePhotos': true,
              'addPhotos': true,
              'editAlbumSettings': true,
              'manageAccess': false,
            };
          } else {
            permissions = {
              'deletePhotos': false,
              'addPhotos': false,
              'editAlbumSettings': false,
              'manageAccess': false,
            };
          }
        } else if (permissionOrMap is Map) {
          permissions = Map<String, bool>.from(permissionOrMap);
        } else {
          permissions = {
            'deletePhotos': false,
            'addPhotos': false,
            'editAlbumSettings': false,
            'manageAccess': false,
          };
        }
        loadedData[uid] = {
          'nickname': nickname,
          'email': email,
          'permissions': permissions,
        };
      } catch (e) {
        loadedData[uid] = {
          'nickname': uid,
          'email': '',
          'permissions': {
            'deletePhotos': false,
            'addPhotos': false,
            'editAlbumSettings': false,
            'manageAccess': false,
          },
        };
      }
    }
    setState(() {
      _sharedUsers = loadedData;
    });
  }

  List<Widget> _buildPermissionIcons(Map<String, bool> permissions) {
    List<Widget> icons = [];
    if (permissions['deletePhotos'] == true) {
      icons.add(Tooltip(
        message: 'Удаление фотографий',
        child: Icon(Icons.delete, size: 18, color: Colors.red),
      ));
    }
    if (permissions['addPhotos'] == true) {
      icons.add(Tooltip(
        message: 'Добавление фотографий',
        child: Icon(Icons.add_a_photo, size: 18, color: Colors.green),
      ));
    }
    if (permissions['editAlbumSettings'] == true) {
      icons.add(Tooltip(
        message: 'Редактирование настроек',
        child: Icon(Icons.edit, size: 18, color: Colors.blue),
      ));
    }
    if (permissions['manageAccess'] == true) {
      icons.add(Tooltip(
        message: 'Настройка доступов',
        child: Icon(Icons.security, size: 18, color: Colors.orange),
      ));
    }
    if (icons.isEmpty) {
      icons.add(Tooltip(
        message: 'Только просмотр',
        child: Icon(Icons.remove_red_eye, size: 18, color: Colors.grey),
      ));
    }
    return icons;
  }

  Widget _buildSharedUserList() {
    if (_sharedUsers.isEmpty) {
      return const Text(
        "Нет пользователей для доступа.",
        style: TextStyle(color: Colors.white),
      );
    }
    return Column(
      children: _sharedUsers.entries.map((entry) {
        final uid = entry.key;
        final data = entry.value;
        final permissions = data['permissions'] as Map<String, bool>;
        final nickname = data['nickname'] as String? ?? '';
        final email = data['email'] as String? ?? '';
        final displayName = nickname.isNotEmpty ? nickname : uid;
        return Card(
          color: Colors.white.withOpacity(0.9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.symmetric(vertical: 4.0),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            leading: CircleAvatar(
              backgroundColor: Colors.blueAccent,
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            title: Text(
              displayName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (email.isNotEmpty)
                  Text(email,
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 4),
                Row(
                  children: _buildPermissionIcons(permissions)
                      .map((icon) => Padding(
                            padding: const EdgeInsets.only(right: 4.0),
                            child: icon,
                          ))
                      .toList(),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blueGrey),
                  onPressed: () => _editPermissionForUser(uid),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    setState(() {
                      _sharedUsers.remove(uid);
                    });
                  },
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _editPermissionForUser(String uid) async {
    final currentPermissions =
        _sharedUsers[uid]['permissions'] as Map<String, bool>? ?? {};
    final newPermissions =
        await _choosePermissions(initialPermissions: currentPermissions);
    if (newPermissions != null) {
      setState(() {
        _sharedUsers[uid]['permissions'] = newPermissions;
      });
    }
  }

  Future<Map<String, bool>?> _choosePermissions({Map<String, bool>? initialPermissions}) async {
    Map<String, bool> permissions = {
      'deletePhotos': initialPermissions?['deletePhotos'] ?? false,
      'addPhotos': initialPermissions?['addPhotos'] ?? false,
      'editAlbumSettings': initialPermissions?['editAlbumSettings'] ?? false,
      'manageAccess': initialPermissions?['manageAccess'] ?? false,
    };

    final List<Map<String, dynamic>> permissionOptions = [
      {
        'key': 'deletePhotos',
        'label': 'Удаление',
        'icon': Icons.delete,
        'color': Colors.red,
      },
      {
        'key': 'addPhotos',
        'label': 'Добавление',
        'icon': Icons.add_a_photo,
        'color': Colors.green,
      },
      {
        'key': 'editAlbumSettings',
        'label': 'Редактирование',
        'icon': Icons.edit,
        'color': Colors.blue,
      },
      {
        'key': 'manageAccess',
        'label': 'Доступы',
        'icon': Icons.security,
        'color': Colors.orange,
      },
    ];

    return showDialog<Map<String, bool>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("Выберите права доступа"),
              content: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: permissionOptions.map((option) {
                    final key = option['key'] as String;
                    return FilterChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(option['icon'] as IconData,
                              color: option['color'] as Color, size: 18),
                          const SizedBox(width: 4),
                          Text(option['label'] as String,
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                      selected: permissions[key]!,
                      onSelected: (selected) {
                        setStateDialog(() {
                          permissions[key] = selected;
                        });
                      },
                      selectedColor: (option['color'] as Color).withOpacity(0.2),
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text("Отмена"),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, permissions),
                  child: const Text("ОК"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildThemeSelector() {
    return Card(
      color: Colors.white.withOpacity(0.8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: DropdownButton<AlbumTheme>(
          value: _selectedTheme,
          isExpanded: true,
          underline: Container(),
          items: AlbumTheme.values.map((theme) {
            return DropdownMenuItem(
              value: theme,
              child: Text(
                _getThemeName(theme),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            );
          }).toList(),
          onChanged: canEditSettings
              ? (newValue) {
                  setState(() {
                    _selectedTheme = newValue!;
                  });
                }
              : null,
        ),
      ),
    );
  }

  Widget _buildAlbumForm() {
    final bool canEditAlbumSettings = isOwner || canEditSettings;

    return Column(
      children: [
        _buildCustomAppBar(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  color: Colors.white.withOpacity(0.8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    enabled: canEditAlbumSettings,
                    decoration: const InputDecoration(
                      labelText: "Название альбома",
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(12),
                    ),
                    onChanged: (value) =>
                        setState(() => _nameController.text = value),
                    controller: _nameController,
                  ),
                ),
                const SizedBox(height: 16),
                _buildThemeSelector(),
                const SizedBox(height: 16),
                Text(
                  "Продолжительность показа фото: ${_duration.toStringAsFixed(1)} сек",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.white),
                ),
                Slider(
                  value: _duration,
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: "${_duration.toStringAsFixed(1)} сек",
                  onChanged: canEditAlbumSettings
                      ? (value) {
                          setState(() {
                            _duration = value;
                          });
                        }
                      : null,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _pickPhotos,
                  icon: const Icon(Icons.add_photo_alternate),
                  label: const Text("+ Добавить фото"),
                ),
                const SizedBox(height: 16),
                _selectedPhotos.isEmpty
                    ? const Text("Выбранных фотографий пока нет",
                        style: TextStyle(color: Colors.white))
                    : (canEditAlbumSettings
                        ? _buildEditablePhotosPreview()
                        : _buildViewOnlyPhotosPreview()),
                if (isOwner || canManageAccess) ...[
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white70),
                  const SizedBox(height: 8),
                  const Text(
                    "Поделиться альбомом:",
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  _buildSharedUserList(),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _addSharedUser,
                    icon: const Icon(Icons.person_add),
                    label: const Text("Добавить пользователя"),
                  ),
                ],
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _saveAlbum,
                  child: Text(
                    widget.albumData == null
                        ? "Сохранить альбом"
                        : "Сохранить изменения",
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _exportToPDF,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text("Экспорт в PDF"),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditablePhotosPreview() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ReorderableListView(
        scrollDirection: Axis.horizontal,
        onReorder: (oldIndex, newIndex) {
          setState(() {
            if (newIndex > oldIndex) newIndex -= 1;
            final item = _selectedPhotos.removeAt(oldIndex);
            _selectedPhotos.insert(newIndex, item);
          });
        },
        children: List.generate(_selectedPhotos.length, (index) {
          final photoItem = _selectedPhotos[index];
          final key = (widget.albumData != null)
              ? ValueKey(photoItem['id'] ?? index)
              : (photoItem['type'] == 'server')
                  ? ValueKey(photoItem['photo']?['id'] ?? index)
                  : ValueKey(photoItem['photo']?.title ?? index);
          return Container(
            key: key,
            margin: const EdgeInsets.symmetric(horizontal: 4.0),
            child: _buildPhotoPreview(photoItem, index),
          );
        }),
      ),
    );
  }

  Widget _buildViewOnlyPhotosPreview() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: List.generate(_selectedPhotos.length, (index) {
          final photoItem = _selectedPhotos[index];
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 4.0),
            child: _buildPhotoPreview(photoItem, index),
          );
        }),
      ),
    );
  }

  Widget _buildCustomAppBar() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: Colors.black.withOpacity(0.1),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Text(
            widget.albumData == null
                ? "Создать фотоальбом"
                : "Редактировать альбом",
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildPhotoPreview(dynamic photoItem, int index) {
    bool showDelete = isOwner || canDeletePhotos;
    Widget imageWidget;
    if (widget.albumData != null && photoItem['url'] != null) {
      imageWidget = Image.network(photoItem['url'] ?? '',
          width: 100, height: 100, fit: BoxFit.cover);
    } else if (photoItem['type'] == 'server') {
      imageWidget = Image.network(photoItem['photo']?['url'] ?? '',
          width: 100, height: 100, fit: BoxFit.cover);
    } else {
      imageWidget = FutureBuilder<Uint8List?>(
        future: photoItem['photo']
            ?.thumbnailDataWithSize(const ThumbnailSize(200, 200)),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              snapshot.hasData) {
            return Image.memory(snapshot.data!,
                width: 100, height: 100, fit: BoxFit.cover);
          } else {
            return const SizedBox(
              width: 100,
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            );
          }
        },
      );
    }
    return Stack(
      children: [
        imageWidget,
        if (showDelete)
          Positioned(
            top: 0,
            right: 0,
            child: InkWell(
              onTap: () => _removePhoto(index),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.withOpacity(0.7),
                ),
                padding: const EdgeInsets.all(4),
                child: const Icon(Icons.close, size: 18, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }

  void _removePhoto(int index) {
    setState(() {
      _selectedPhotos.removeAt(index);
    });
  }

  Future<void> _pickPhotos() async {
    if (!a) {
      selected = await Navigator.push<List<dynamic>>(
        context,
        MaterialPageRoute(
          builder: (context) =>
              GalleryScreen(multiSelectMode: true, source: "album_creation"),
        ),
      );
    }
    if (selected != null && selected!.isNotEmpty) {
      setState(() {
        for (var newPhotoItem in selected!) {
          final newPhotoId = _extractPhotoId(newPhotoItem);
          if (newPhotoId == null) continue;
          bool alreadyExists = _selectedPhotos.any((existingItem) {
            final existingId = _extractPhotoId(existingItem);
            return existingId == newPhotoId;
          });
          if (!alreadyExists) _selectedPhotos.add(newPhotoItem);
        }
      });
    }
  }

  String? _extractPhotoId(dynamic photoItem) {
    if (photoItem == null) return null;
    if (photoItem['type'] == 'local') return photoItem['photo'].title;
    if (photoItem['type'] == 'server') return photoItem['photo']?['id'];
    return photoItem['id'];
  }

  Future<void> _addSharedUser() async {
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid;
    final excludedUids = <String>[
      if (currentUserUid != null) currentUserUid,
      ..._sharedUsers.keys,
    ];
    final result = await showSearch<Map<String, dynamic>?>(
      context: context,
      delegate: UserSearchDelegate(excludedUserIds: excludedUids),
    );
    if (result != null && result['uid'] != null) {
      final permissions = await _choosePermissions();
      if (permissions != null) {
        setState(() {
          _sharedUsers[result['uid']] = {
            'nickname': result['nickname'] ?? '',
            'email': result['email'] ?? '',
            'permissions': permissions,
          };
        });
      }
    }
  }

  Future<void> _saveAlbum() async {
    if (_nameController.text.isEmpty) {
      _showCustomMessage("Введите название альбома.", icon: Icons.error_outline, backgroundColor: Colors.redAccent);
      return;
    }
    if (_selectedPhotos.isEmpty) {
      _showCustomMessage("Выберите хотя бы одну фотографию.", icon: Icons.error_outline, backgroundColor: Colors.redAccent);
      return;
    }
    setState(() => _saving = true);
    try {
      final firestore = FirebaseFirestore.instance;
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        _showCustomMessage("Ошибка: пользователь не авторизован.", icon: Icons.error_outline, backgroundColor: Colors.redAccent);
        setState(() => _saving = false);
        return;
      }
      List<Map<String, dynamic>> photosData = [];
      for (var photoItem in _selectedPhotos) {
        String? downloadUrl;
        String photoId;
        if (photoItem['type'] == 'local') {
          downloadUrl =
              await _photoService.uploadPhotoToServer(photoItem['photo']);
          photoId = photoItem['photo'].title ?? "";
        } else {
          downloadUrl = photoItem['photo']?['url'] ?? photoItem['url'];
          photoId = photoItem['photo']?['id'] ?? photoItem['id'];
        }
        if (downloadUrl != null && downloadUrl.isNotEmpty) {
          photosData.add({'url': downloadUrl, 'id': photoId});
        }
      }
      if (photosData.isEmpty) {
        _showCustomMessage("Ошибка: не удалось загрузить фотографии.", icon: Icons.error_outline, backgroundColor: Colors.redAccent);
        setState(() => _saving = false);
        return;
      }
      final albumOwner = (widget.albumData != null &&
              widget.albumData!.containsKey('owner'))
          ? widget.albumData!['owner']
          : currentUser.uid;
          
      final albumData = {
        'name': _nameController.text,
        'duration': _duration,
        'createdAt': FieldValue.serverTimestamp(),
        'owner': albumOwner,
        'sharedWith': _sharedUsers.map((key, value) => MapEntry(key, value['permissions'])),
        'photos': photosData,
        'theme': _selectedTheme.toString().split('.').last,
      };
      if (widget.albumData != null && widget.albumData!.containsKey('id')) {
        await firestore.collection('albums').doc(widget.albumData!['id']).update(albumData);
      } else {
        final docRef = await firestore.collection('albums').add(albumData);
        albumData['id'] = docRef.id;
      }
      setState(() {
        _saving = false;
        _nameController.text = '';
        _selectedPhotos.clear();
      });
      _showCustomMessage("Альбом успешно ${widget.albumData != null ? 'отредактирован' : 'создан'}!");
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      _showCustomMessage("Ошибка: $e", icon: Icons.error_outline, backgroundColor: Colors.redAccent);
    }
  }

  Future<void> _exportToPDF() async {
    if (_selectedPhotos.isEmpty) {
      _showCustomMessage("Нет фотографий для экспорта.", icon: Icons.error_outline, backgroundColor: Colors.redAccent);
      return;
    }
    try {
      final fontData = await rootBundle.load("assets/fonts/NotoSans-Bold.ttf");
      final customFont = pw.Font.ttf(fontData);

      final pdf = pw.Document();
      PdfColor backgroundColor;
      pw.TextStyle titleStyle;
      switch (_selectedTheme) {
        case AlbumTheme.classic:
          backgroundColor = PdfColor.fromInt(0xFFB0C4DE);
          titleStyle = pw.TextStyle(
              fontSize: 32,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromInt(0xFF708090),
              font: customFont);
          break;
        case AlbumTheme.modern:
          backgroundColor = PdfColor.fromInt(0xFFFC5C7D);
          titleStyle = pw.TextStyle(
              fontSize: 32,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromInt(0xFF6A82FB),
              font: customFont);
          break;
        case AlbumTheme.event:
          backgroundColor = PdfColor.fromInt(0xFFFFA07A);
          titleStyle = pw.TextStyle(
              fontSize: 32,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromInt(0xFFFF4500),
              font: customFont);
          break;
        case AlbumTheme.vintage:
          backgroundColor = PdfColor.fromInt(0xFFDEB887);
          titleStyle = pw.TextStyle(
              fontSize: 32,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromInt(0xFF8B4513),
              font: customFont);
          break;
        case AlbumTheme.bright:
          backgroundColor = PdfColor.fromInt(0xFFFFC107);
          titleStyle = pw.TextStyle(
              fontSize: 32,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromInt(0xFFFF5722),
              font: customFont);
          break;
        case AlbumTheme.night:
          backgroundColor = PdfColors.black;
          titleStyle = pw.TextStyle(
              fontSize: 32,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
              font: customFont);
          break;
        case AlbumTheme.pastel:
          backgroundColor = PdfColor.fromInt(0xFFB2DFDB);
          titleStyle = pw.TextStyle(
              fontSize: 32,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromInt(0xFFE0F7FA),
              font: customFont);
          break;
      }
      pdf.addPage(pw.Page(
        build: (pw.Context context) {
          return pw.Container(
            decoration: pw.BoxDecoration(
              color: backgroundColor,
              border: pw.Border.all(color: PdfColors.black, width: 2),
            ),
            child: pw.Center(
              child: pw.Text(
                _nameController.text,
                style: titleStyle,
              ),
            ),
          );
        },
      ));
      for (var photoItem in _selectedPhotos) {
        Uint8List? imageData;
        if (photoItem['type'] == 'local') {
          imageData = await photoItem['photo'].originBytes;
          if (imageData == null) {
            imageData = await photoItem['photo']
                .thumbnailDataWithSize(const ThumbnailSize(600, 600));
          }
        } else {
          final url = photoItem['photo']?['url'] ?? photoItem['url'];
          if (url != null) {
            final response = await http.get(Uri.parse(url));
            if (response.statusCode == 200) {
              imageData = response.bodyBytes;
            }
          }
        }
        if (imageData != null) {
          pdf.addPage(pw.Page(
            build: (pw.Context context) {
              return pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.black, width: 4),
                  gradient: pw.LinearGradient(
                    colors: [backgroundColor, PdfColors.white],
                    begin: pw.Alignment.topLeft,
                    end: pw.Alignment.bottomRight,
                  ),
                ),
                padding: const pw.EdgeInsets.all(8),
                child: pw.Center(
                  child: pw.Image(pw.MemoryImage(imageData!), fit: pw.BoxFit.contain),
                ),
              );
            },
          ));
        }
      }
      final fileName = _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : "album";
      await Printing.sharePdf(bytes: await pdf.save(), filename: '$fileName.pdf');
    } catch (e) {
      _showCustomMessage("Ошибка при экспорте в PDF: $e", icon: Icons.error_outline, backgroundColor: Colors.redAccent);
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF89CFFD), Color(0xFFB084CC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(child: _buildAlbumForm()),
          ),
          if (_saving) _buildSavingOverlay(),
        ],
      ),
    );
  }

  Widget _buildSavingOverlay() {
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
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFC5C7D), Color(0xFF6A82FB)],
                  ),
                ),
                child: const Icon(
                  Icons.photo_album,
                  size: 50,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Сохранение альбома...",
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            )
          ],
        ),
      ),
    );
  }


}
