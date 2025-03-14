import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trip/screens/gallery_screen.dart';
import 'package:trip/screens/user_search.dart';
import 'package:trip/services/photo_service.dart';

class FolderScreen extends StatefulWidget {
  @override
  _FolderScreenState createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Map<String, String> _nicknameCache = {};

  bool _isProcessing = false;

  late AnimationController _loadingController;

  @override
  void initState() {
    super.initState();
    _loadingController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();
  }

  @override
  void dispose() {
    _loadingController.dispose();
    super.dispose();
  }

  Future<String> _fetchNickname(String uid) async {
    if (_nicknameCache.containsKey(uid)) {
      return _nicknameCache[uid]!;
    }
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      final data = doc.data();
      final nickname = data?['nickname'] ?? uid;
      _nicknameCache[uid] = nickname;
      return nickname;
    } catch (e) {
      return uid;
    }
  }

  Widget _buildPermissionIcons(Map<String, dynamic> perms) {
  final List<Widget> iconWidgets = [];

  if (perms['addPhotos'] == true) {
    iconWidgets.add(
      Tooltip(
        message: "Добавление фото",
        child: Icon(Icons.add_a_photo, color: Colors.green),
      ),
    );
  }
  if (perms['deleteFolder'] == true) {
    iconWidgets.add(
      Tooltip(
        message: "Удаление папки",
        child: Icon(Icons.delete_forever, color: Colors.red),
      ),
    );
  }
  if (perms['deletePhotos'] == true) {
    iconWidgets.add(
      Tooltip(
        message: "Удаление фото",
        child: Icon(Icons.delete, color: Colors.orange),
      ),
    );
  }
  if (perms['autoSharePhotos'] == true) {
    iconWidgets.add(
      Tooltip(
        message: "Автоподелиться",
        child: Icon(Icons.autorenew, color: Colors.purple),
      ),
    );
  }

  if (iconWidgets.isEmpty) {
    return const Text(
      "Только просмотр",
      style: TextStyle(color: Colors.grey),
    );
  }

  return Wrap(
    spacing: 6,
    runSpacing: 4,
    children: iconWidgets,
  );
}


  void _showCustomMessage(String message,
      {IconData icon = Icons.check_circle_outline,
      Color backgroundColor = Colors.green}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: backgroundColor,
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
                child: Text(message,
                    style: const TextStyle(color: Colors.white))),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildProcessingOverlay() {
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
                  Icons.folder,
                  size: 50,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Обработка...",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _createFolder() async {
    final _nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Создать папку"),
        content: TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: "Название папки",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Отмена"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_nameController.text.isNotEmpty) {
                Navigator.pop(context);
                setState(() {
                  _isProcessing = true;
                });
                final currentUser = _auth.currentUser;
                if (currentUser != null) {
                  await _firestore.collection('folders').add({
                    'name': _nameController.text,
                    'owner': currentUser.uid,
                    'photos': [],
                    'createdAt': FieldValue.serverTimestamp(),
                    'sharedWith': {}
                  });
                  setState(() {
                    _isProcessing = false;
                  });
                  _showCustomMessage("Папка успешно создана!");
                }
              }
            },
            child: const Text("Создать"),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteFolder(
    Map<String, dynamic> folder,
    bool isOwner,
    Map<String, dynamic>? permissions,
  ) async {
    if (!isOwner && (permissions?['deleteFolder'] != true)) {
      _showCustomMessage("У вас нет прав на удаление этой папки",
          icon: Icons.error_outline, backgroundColor: Colors.redAccent);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Удалить папку?"),
        content: Text(
            'Вы уверены, что хотите удалить папку "${folder['name']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Отмена"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Удалить"),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() {
        _isProcessing = true;
      });
      await _firestore.collection('folders').doc(folder['id']).delete();
      setState(() {
        _isProcessing = false;
      });
      _showCustomMessage("Папка удалена");
    }
  }

  void _openFolder(String folderId, List<dynamic> photoIds) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GalleryScreen(
          folderFilter: photoIds,
          folderId: folderId,
        ),
      ),
    );
  }

Future<void> _selectPhotosForFolder(
  Map<String, dynamic> folder,
  bool isOwner,
  Map<String, dynamic>? permissions,
) async {
  if (!isOwner && (permissions?['addPhotos'] != true)) {
    _showCustomMessage("У вас нет прав на добавление фотографий",
        icon: Icons.error_outline, backgroundColor: Colors.redAccent);
    return;
  }
  final result = await Navigator.push<List<dynamic>?>(context,
      MaterialPageRoute(builder: (context) => GalleryScreen(
        multiSelectMode: true,
        source: "folder_selection",
      )));
  if (result != null) {
    final selectedPhotoIds = result.map((photoItem) {
      if (photoItem['type'] == 'server') {
        return photoItem['photo']['id'];
      } else if (photoItem['type'] == 'local') {
        return photoItem['photo'].title;
      }
      return "";
    }).where((id) => id.isNotEmpty).toList();

    setState(() {
      _isProcessing = true;
    });
    await _firestore.collection('folders').doc(folder['id']).update({
      'photos': FieldValue.arrayUnion(selectedPhotoIds),
    });
    final folderSnapshot = await _firestore.collection('folders').doc(folder['id']).get();
    final folderData = folderSnapshot.data();
    final sharedWith = folderData?['sharedWith'] ?? {};
    for (String photoId in selectedPhotoIds) {
      final photoDoc = await _firestore.collection('photos').doc(photoId).get();
      if (photoDoc.exists) {
        await photoDoc.reference.update({
          'folderIds': FieldValue.arrayUnion([folder['id']]),
          'folderShares.${folder['id']}': sharedWith,
        });
      }
    }
    await PhotoService().updatePhotosSharingForFolder(folder['id'], sharedWith);
    setState(() {
      _isProcessing = false;
    });
    _showCustomMessage("Фото успешно добавлены и доступ обновлён");
  }
}





  Future<void> _shareFolder(Map<String, dynamic> folder) async {
    final currentUser = _auth.currentUser;
    if (folder['owner'] != currentUser?.uid) {
      _showCustomMessage("У вас нет прав на управление этой папкой",
          icon: Icons.error_outline, backgroundColor: Colors.redAccent);
      return;
    }
    await _editSharedUsers(folder);
  }

  Future<void> _editSharedUsers(Map<String, dynamic> folder) async {
  Map<String, dynamic> currentSharedWith = {};
  if (folder['sharedWith'] != null) {
    currentSharedWith = Map<String, dynamic>.from(folder['sharedWith']);
  }
  final result = await showDialog<Map<String, dynamic>?>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text("Управление доступом"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Серверные фотографии будут автоматически отправляться тем пользователям, у которых включена функция 'Автоподелиться'.",
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  currentSharedWith.isEmpty
                      ? const Text(
                          "Папка пока не поделена.\nНажмите 'Добавить пользователя' для настройки доступа.",
                          textAlign: TextAlign.center,
                        )
                      : ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: ListView(
                            shrinkWrap: true,
                            children: currentSharedWith.entries.map((entry) {
                              final uid = entry.key;
                              final perms = Map<String, dynamic>.from(entry.value);
                              return FutureBuilder<String>(
                                future: _fetchNickname(uid),
                                builder: (context, snap) {
                                  if (!snap.hasData) {
                                    return ListTile(
                                      title: Text("Загрузка… ($uid)"),
                                    );
                                  }
                                  final nickname = snap.data!;
                                  return ListTile(
                                    contentPadding:
                                        const EdgeInsets.symmetric(horizontal: 0),
                                    title: Text(nickname),
                                    subtitle: _buildPermissionIcons(perms),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit, color: Colors.blue),
                                          tooltip: "Изменить права",
                                          onPressed: () async {
                                            final newPerms =
                                                await _editSinglePermissionChipBased(uid, perms);
                                            if (newPerms != null) {
                                              setStateDialog(() {
                                                currentSharedWith[uid] = newPerms;
                                              });
                                            }
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete, color: Colors.red),
                                          tooltip: "Удалить пользователя",
                                          onPressed: () {
                                            setStateDialog(() {
                                              currentSharedWith.remove(uid);
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            }).toList(),
                          ),
                        ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final currentUserUid = _auth.currentUser?.uid;
                      final excludedUserIds = <String>[
                        if (currentUserUid != null) currentUserUid,
                        ...currentSharedWith.keys,
                      ];
                      final resultUser = await showSearch<Map<String, dynamic>?>(
                        context: context,
                        delegate: UserSearchDelegate(excludedUserIds: excludedUserIds),
                      );
                      if (resultUser != null && resultUser['uid'] != null) {
                        final newUid = resultUser['uid'] as String;
                        setStateDialog(() {
                          currentSharedWith[newUid] = {
                            'addPhotos': true,
                            'deleteFolder': false,
                            'deletePhotos': true,
                            'autoSharePhotos': true,
                          };
                        });
                      }
                    },
                    icon: const Icon(Icons.person_add),
                    label: const Text("Добавить пользователя"),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text("Отмена"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, currentSharedWith),
                child: const Text("Сохранить"),
              ),
            ],
          );
        },
      );
    },
  );
  if (result != null) {
    setState(() {
      _isProcessing = true;
    });
    await _firestore.collection('folders').doc(folder['id']).update({'sharedWith': result});
    await PhotoService().updatePhotosSharingForFolder(folder['id'], result);
    setState(() {
      _isProcessing = false;
    });
    _showCustomMessage("Доступ успешно обновлён");
  }
}



  Future<Map<String, dynamic>?> _editSinglePermissionChipBased(
  String uid,
  Map<String, dynamic> perms,
) async {
  bool addPhotos = perms['addPhotos'] ?? false;
  bool deleteFolder = perms['deleteFolder'] ?? false;
  bool deletePhotos = perms['deletePhotos'] ?? false;
  bool autoSharePhotos = perms['autoSharePhotos'] ?? false;

  final List<Map<String, dynamic>> permissionOptions = [
    {
      'key': 'addPhotos',
      'label': 'Добавление фото',
      'icon': Icons.add_a_photo,
      'color': Colors.green,
    },
    {
      'key': 'deleteFolder',
      'label': 'Удаление папки',
      'icon': Icons.delete_forever,
      'color': Colors.red,
    },
    {
      'key': 'deletePhotos',
      'label': 'Удаление фото',
      'icon': Icons.delete,
      'color': Colors.orange,
    },
    {
      'key': 'autoSharePhotos',
      'label': 'Автоподелиться',
      'icon': Icons.autorenew,
      'color': Colors.purple,
    },
  ];

  final localPerms = <String, bool>{
    'addPhotos': addPhotos,
    'deleteFolder': deleteFolder,
    'deletePhotos': deletePhotos,
    'autoSharePhotos': autoSharePhotos,
  };

  final nickname = await _fetchNickname(uid);

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              "Разрешения для $nickname",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: permissionOptions.map((option) {
                  final key = option['key'] as String;
                  final label = option['label'] as String;
                  final icon = option['icon'] as IconData;
                  final color = option['color'] as Color;
                  final isSelected = localPerms[key] ?? false;

                  return FilterChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: color, size: 18),
                        const SizedBox(width: 4),
                        Text(label, style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      setStateDialog(() {
                        localPerms[key] = selected;
                      });
                    },
                    selectedColor: color.withOpacity(0.2),
                    checkmarkColor: color,
                    showCheckmark: true,
                    backgroundColor: Colors.grey[200],
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text("Отмена"),
              ),
              ElevatedButton(
                onPressed: () {
                  final newPerms = {
                    'addPhotos': localPerms['addPhotos'] ?? false,
                    'deleteFolder': localPerms['deleteFolder'] ?? false,
                    'deletePhotos': localPerms['deletePhotos'] ?? false,
                    'autoSharePhotos': localPerms['autoSharePhotos'] ?? false,
                  };
                  Navigator.pop(context, newPerms);
                },
                child: const Text("Сохранить"),
              ),
            ],
          );
        },
      );
    },
  );
}


  Stream<List<Map<String, dynamic>>> _folderStream() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return Stream.value([]);

    return _firestore.collection('folders').snapshots().map((querySnapshot) {
      final allFolders = querySnapshot.docs.map((doc) {
        return {'id': doc.id, ...doc.data() as Map<String, dynamic>};
      }).toList();

      final myFolders =
          allFolders.where((f) => f['owner'] == currentUser.uid).toList();
      final sharedFolders = allFolders.where((f) {
        return f['owner'] != currentUser.uid &&
            f['sharedWith'] != null &&
            (f['sharedWith'] as Map).containsKey(currentUser.uid);
      }).toList();

      return [...myFolders, ...sharedFolders];
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text("Пользователь не авторизован")),
      );
    }
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Папки", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black.withOpacity(0.1),
        elevation: 0,
        actions: [
          IconButton(
            icon:
                const Icon(Icons.create_new_folder, color: Colors.white),
            onPressed: _createFolder,
            tooltip: "Создать папку",
          ),
        ],
      ),
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
            child: SafeArea(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _folderStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: _buildProcessingOverlay());
                  }
                  if (snapshot.hasError) {
                    return const Center(
                        child: Text("Ошибка загрузки папок",
                            style: TextStyle(color: Colors.white)));
                  }
                  final folders = snapshot.data ?? [];
                  if (folders.isEmpty) {
                    return const Center(
                      child: Text(
                        "Нет папок",
                        style:
                            TextStyle(fontSize: 18, color: Colors.white),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: folders.length,
                    itemBuilder: (context, index) {
                      final folder = folders[index];
                      final isOwner = folder['owner'] == currentUser.uid;
                      Map<String, dynamic>? permissions;
                      if (!isOwner && folder['sharedWith'] != null) {
                        permissions = folder['sharedWith'][currentUser.uid];
                      }
                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 4,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        child: ListTile(
                          onTap: () =>
                              _openFolder(folder['id'], folder['photos']),
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 16),
                          leading: CircleAvatar(
                            backgroundColor: Colors.blueAccent,
                            radius: 22,
                            child: const Icon(Icons.folder,
                                color: Colors.white, size: 20),
                          ),
                          title: Text(
                            folder['name'],
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            "${(folder['photos'] as List).length} фото" +
                                (isOwner ? "" : " (общая)"),
                            style: const TextStyle(fontSize: 14),
                          ),
                          trailing: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert),
                            onSelected: (value) async {
                              switch (value) {
                                case 'share':
                                  await _shareFolder(folder);
                                  break;
                                case 'edit_permissions':
                                  await _editSharedUsers(folder);
                                  break;
                                case 'add_photos':
                                  _selectPhotosForFolder(
                                      folder, isOwner, permissions);
                                  break;
                                case 'delete':
                                  await _confirmDeleteFolder(
                                      folder, isOwner, permissions);
                                  break;
                              }
                            },
                            itemBuilder: (context) {
                              final items = <PopupMenuEntry<String>>[];
                              if (isOwner) {
                                items.add(
                                  PopupMenuItem(
                                    value: 'share',
                                    child: ListTile(
                                      leading: const Icon(Icons.share,
                                          color: Colors.blue),
                                      title: const Text("Поделиться и управлять"),
                                    ),
                                  ),
                                );
                              } else {
                                items.add(
                                  PopupMenuItem(
                                    value: 'edit_permissions',
                                    child: ListTile(
                                      leading: const Icon(Icons.share,
                                          color: Colors.blueGrey),
                                      title: const Text("Настроить разрешения"),
                                    ),
                                  ),
                                );
                              }
                              items.add(
                                PopupMenuItem(
                                  value: 'add_photos',
                                  child: ListTile(
                                    leading: Icon(
                                      Icons.add,
                                      color: (isOwner ||
                                              (permissions?['addPhotos'] == true))
                                          ? Colors.green
                                          : Colors.grey,
                                    ),
                                    title: const Text("Добавить фото"),
                                  ),
                                ),
                              );
                              items.add(
                                PopupMenuItem(
                                  value: 'delete',
                                  child: ListTile(
                                    leading: Icon(
                                      Icons.delete,
                                      color: (isOwner ||
                                              (permissions?['deleteFolder'] ==
                                                  true))
                                          ? Colors.red
                                          : Colors.grey,
                                    ),
                                    title: const Text("Удалить папку"),
                                  ),
                                ),
                              );
                              return items;
                            },
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
          if (_isProcessing) _buildProcessingOverlay(),
        ],
      ),
    );
  }
}
