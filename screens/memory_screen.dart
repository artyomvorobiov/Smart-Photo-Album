import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:trip/screens/create_album_screen.dart';
import 'package:trip/screens/slideshow_screen.dart';
import 'package:trip/services/albums_service.dart';
import 'package:trip/services/photo_service.dart';
import 'package:intl/intl.dart';
import 'dart:math';

class PhotoAlbumsScreen extends StatefulWidget {
  @override
  _PhotoAlbumsScreenState createState() => _PhotoAlbumsScreenState();
}

class _PhotoAlbumsScreenState extends State<PhotoAlbumsScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final AlbumsService _albumService = AlbumsService();
  final PhotoService _photoService = PhotoService();

  List<Map<String, dynamic>> _userAlbums = [];
  List<Map<String, dynamic>> _sharedAlbums = [];
  bool _loading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchAlbums();
  }

  Future<void> _fetchAlbums() async {
    setState(() => _loading = true);
    try {
      final myAlbums = await _albumService.getUserAlbums();
      final sharedAlbums = await _albumService.getSharedAlbums();
      setState(() {
        _userAlbums = myAlbums;
        _sharedAlbums = sharedAlbums;
        _loading = false;
      });
    } catch (e) {
      print("Ошибка при загрузке альбомов: $e");
      setState(() => _loading = false);
    }
  }
  void _onAlbumTap(Map<String, dynamic> album) {
    final photos = album['photos'] as List<dynamic>;
    final duration = album['duration'] as double? ?? 5.0;
    final name = album['name'] as String;
    final theme = album['theme'] ?? 'classic';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SlideshowScreen(
          name: name,
          photos: photos.map((photo) => photo as Map<String, dynamic>).toList(),
          duration: duration,
          theme: theme,
        ),
      ),
    );
  }

  void _showAlbumOptions(Map<String, dynamic> album) {
    final currentUser = _auth.currentUser;
    bool isOwner = album['owner'] == currentUser?.uid;
    bool canEdit = false;
    if (!isOwner &&
        album['sharedWith'] != null &&
        currentUser != null) {
      final userPerms = album['sharedWith'][currentUser.uid];
      if (userPerms != null) {
        if (userPerms is Map) {
          canEdit = userPerms['editAlbumSettings'] == true ||
              userPerms['addPhotos'] == true ||
              userPerms['deletePhotos'] == true ||
              userPerms['manageAccess'] == true;
        } else if (userPerms is String) {
          canEdit = (userPerms == 'edit' || userPerms == 'add');
        }
      }
    }
    bool canDelete = isOwner;
    if (!isOwner &&
        album['sharedWith'] != null &&
        currentUser != null) {
      final userPerms = album['sharedWith'][currentUser.uid];
      if (userPerms != null) {
        if (userPerms is Map) {
          canDelete = userPerms['deletePhotos'] == true;
        } else if (userPerms is String) {
          canDelete = (userPerms == 'edit');
        }
      }
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white.withOpacity(0.95),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.visibility),
                title: const Text("Просмотреть альбом"),
                onTap: () {
                  Navigator.pop(context);
                  _onAlbumTap(album);
                },
              ),
              if (isOwner || canEdit)
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text("Редактировать альбом"),
                  onTap: () async {
                    Navigator.pop(context);
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              CreateAlbumScreen(albumData: album)),
                    );
                    _fetchAlbums();
                  },
                ),
              if (canDelete)
                ListTile(
                  leading: const Icon(Icons.delete),
                  title: const Text("Удалить альбом"),
                  onTap: () async {
                    Navigator.pop(context);
                    await _albumService.deleteAlbum(album);
                    setState(() {
                      _userAlbums.removeWhere((a) => a['id'] == album['id']);
                    });
                  },
                ),
            ],
          ),
        );
      },
    );
  }
  Future<List<Map<String, dynamic>>> _fetchAllPhotos() async {
    List<Map<String, dynamic>> serverPhotos =
        await _photoService.fetchPhotosFromFirestore();
    serverPhotos = serverPhotos.map((photo) {
      photo['type'] = 'server';
      return photo;
    }).toList();
    return serverPhotos;
  }

  Future<List<Map<String, dynamic>>> _generateSuggestedAlbums() async {
    List<Map<String, dynamic>> allPhotos = await _fetchAllPhotos();
    final random = Random();
    Map<String, int> tagCounts = {};
    for (var photo in allPhotos) {
      List<dynamic> tags = photo['tags'] ?? [];
      for (var tag in tags) {
        if (tag is String && tag.isNotEmpty) {
          tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
        }
      }
    }
    var sortedTags = tagCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    List<Map<String, dynamic>> suggestedAlbums = [];
    int topN = sortedTags.length < 5 ? sortedTags.length : 5;
    List<MapEntry<String, int>> topTags = sortedTags.sublist(0, topN);
    topTags.shuffle(random);
    for (int i = 0; i < min(2, topTags.length); i++) {
      String tag = topTags[i].key;
      List<Map<String, dynamic>> albumPhotos = allPhotos.where((photo) {
        List<dynamic> tags = photo['tags'] ?? [];
        return tags.any((t) => t.toString().toLowerCase() == tag.toLowerCase());
      }).toList();
      albumPhotos.shuffle(random);
      suggestedAlbums.add({
        'name': tag,
        'photos': albumPhotos,
      });
    }
    Map<String, List<Map<String, dynamic>>> groups = {};
    for (var photo in allPhotos) {
      DateTime date;
      var exifMap = photo['exif'];
      if (exifMap != null &&
          exifMap is Map &&
          exifMap['EXIF DateTimeOriginal'] != null) {
        String exifDateStr = exifMap['EXIF DateTimeOriginal'];
        try {
          String formattedExifDate = exifDateStr.replaceFirstMapped(
            RegExp(r'^(\d{4}):(\d{2}):(\d{2})'),
            (match) => '${match.group(1)}-${match.group(2)}-${match.group(3)}',
          );
          date = DateTime.parse(formattedExifDate);
        } catch (e) {
          date = DateTime.now();
        }
      } else if (photo['creation_date'] != null) {
        try {
          date = DateTime.parse(photo['creation_date']);
        } catch (e) {
          date = DateTime.now();
        }
      } else if (photo['timestamp'] != null) {
        if (photo['timestamp'] is Timestamp) {
          date = (photo['timestamp'] as Timestamp).toDate();
        } else if (photo['timestamp'] is DateTime) {
          date = photo['timestamp'];
        } else {
          date = DateTime.now();
        }
      } else {
        date = DateTime.now();
      }
      String dateKey = DateFormat('yyyy-MM-dd').format(date);
      groups.putIfAbsent(dateKey, () => []).add(photo);
    }
    List<String> allDateKeys = groups.keys.toList();
    if (allDateKeys.isNotEmpty) {
      allDateKeys.shuffle(random);
      String chosenKey = allDateKeys.first;
      DateTime dt = DateTime.parse(chosenKey);
      String albumName = DateFormat('dd MMMM yyyy', 'ru_RU').format(dt);
      List<Map<String, dynamic>> datePhotos = groups[chosenKey]!;
      suggestedAlbums.add({
        'name': albumName,
        'photos': datePhotos,
      });
    }
    
    return suggestedAlbums;
  }
  Widget _buildSuggestedAlbumCover(Map<String, dynamic> photo) {
    if (photo['type'] == 'server') {
      final imageUrl = photo['url'];
      if (imageUrl != null &&
          imageUrl is String &&
          imageUrl.isNotEmpty) {
        return Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            image: DecorationImage(
              image: NetworkImage(imageUrl),
              fit: BoxFit.cover,
            ),
          ),
        );
      }
    }
    return Container(width: 60, height: 60, color: Colors.grey);
  }
  void _handleSuggestedAlbumSelection(Map<String, dynamic> album) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Действие с альбомом"),
        content: Text(
          "Чтобы предложения альбомов появлялись, фотографии должны быть сохранены на сервере.\n\nВыберите действие:",
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SlideshowScreen(
                    name: album['name'],
                    photos: (album['photos'] as List)
                        .map<Map<String, dynamic>>((photo) {
                      return Map<String, dynamic>.from(photo);
                    }).toList(),
                    duration: 5.0,
                    theme: album['theme'] ?? 'classic',
                  ),
                ),
              );
            },
            child: Text("Просмотреть"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Map<String, dynamic> newAlbumData = Map<String, dynamic>.from(album);
              newAlbumData.remove('id');
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CreateAlbumScreen(albumData: newAlbumData),
                ),
              ).then((albumSaved) {
                if (albumSaved == true) {
                  _fetchAlbums();
                }
              });
            },
            child: Text("Сохранить альбом"),
          ),
        ],
      ),
    );
  }
  void _showSuggestedAlbums() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(child: CircularProgressIndicator()),
    );
    List<Map<String, dynamic>> suggestedAlbums =
        await _generateSuggestedAlbums();
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          "Предложенные альбомы",
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) =>
                                Center(child: CircularProgressIndicator()),
                          );
                          List<Map<String, dynamic>> newAlbums =
                              await _generateSuggestedAlbums();
                          Navigator.pop(context);
                          setModalState(() {
                            suggestedAlbums = newAlbums;
                          });
                        },
                        icon: Icon(Icons.refresh),
                        label: Text("Сгенерировать новые"),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Чтобы предложения отображались, фотографии должны быть сохранены на сервере.",
                    style: TextStyle(fontSize: 14, color: Colors.redAccent),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 12),
                  ListView.builder(
                    shrinkWrap: true,
                    itemCount: suggestedAlbums.length,
                    itemBuilder: (context, index) {
                      final album = suggestedAlbums[index];
                      return Card(
                        margin: EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: album['photos'].isNotEmpty
                              ? _buildSuggestedAlbumCover(album['photos'][0])
                              : Container(width: 60, height: 60, color: Colors.grey),
                          title: Text(album['name']),
                          subtitle: Text("${album['photos'].length} фото"),
                          onTap: () {
                            Navigator.pop(context);
                            _handleSuggestedAlbumSelection(album);
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
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
          const Text(
            "Фотоальбомы",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.auto_awesome, color: Colors.white),
            tooltip: "Предложенные альбомы",
            onPressed: _showSuggestedAlbums,
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () async {
              final albumCreated = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => CreateAlbumScreen()),
              );
              if (albumCreated == true) {
                _fetchAlbums();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumCover(Map<String, dynamic> album) {
    final photos = album['photos'] as List<dynamic>? ?? [];
    if (photos.isNotEmpty && photos[0] is Map<String, dynamic>) {
      final firstPhoto = photos[0] as Map<String, dynamic>;
      final imageUrl = firstPhoto['url'];
      if (imageUrl != null && imageUrl is String && imageUrl.isNotEmpty) {
        return Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            image: DecorationImage(
              image: NetworkImage(imageUrl),
              fit: BoxFit.cover,
            ),
          ),
        );
      }
    }
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey.shade300,
      ),
      child: const Icon(Icons.photo_album, size: 32, color: Colors.white),
    );
  }

  Widget _buildAlbumList(List<Map<String, dynamic>> albums) {
    if (albums.isEmpty) {
      return Center(
        child: Text(
          "Нет доступных альбомов.",
          style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 18),
        ),
      );
    }
    return ListView.separated(
      itemCount: albums.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      padding: const EdgeInsets.all(12),
      itemBuilder: (context, index) {
        final album = albums[index];
        return Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: _buildAlbumCover(album),
            title: Text(
              album['name'] ?? "Без названия",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              "${(album['photos'] as List).length} фото",
              style: const TextStyle(color: Colors.black54),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => _showAlbumOptions(album),
            ),
            onTap: () => _onAlbumTap(album),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF89CFFD), Color(0xFFB084CC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildCustomAppBar(),
              if (_loading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(20),
                            bottomRight: Radius.circular(20),
                          ),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          indicatorSize: TabBarIndicatorSize.tab,
                          tabs: const [
                            Tab(text: "Мои альбомы"),
                            Tab(text: "Чужие альбомы"),
                          ],
                          labelColor: Colors.white,
                          unselectedLabelColor: Colors.white70,
                          indicator: BoxDecoration(
                            color: Colors.white.withOpacity(0.3),
                          ),
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildAlbumList(_userAlbums),
                            _buildAlbumList(_sharedAlbums),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
