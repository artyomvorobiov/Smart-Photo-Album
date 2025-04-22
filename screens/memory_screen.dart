import 'dart:math';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:trip/screens/create_album_screen.dart';
import 'package:trip/screens/slideshow_screen.dart';
import 'package:trip/services/albums_service.dart';
import 'package:trip/services/photo_service.dart';
const Color kBackgroundColor = Color(0xFFF5EEDC);
const Color kPrimaryColor = Color(0xFF27548A); 
const Color kAppBarColor = Color(0xFF183B4E); 
const Color kAccentColor = Color(0xFFDDA853); 

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
  if (!isOwner && album['sharedWith'] != null && currentUser != null) {
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
  if (!isOwner && album['sharedWith'] != null && currentUser != null) {
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
    backgroundColor: kBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(Icons.visibility, color: kAccentColor),
              title: Text(
                "Просмотреть альбом",
                style: TextStyle(color: kPrimaryColor),
              ),
              onTap: () {
                Navigator.pop(context);
                _onAlbumTap(album);
              },
            ),
            if (isOwner || canEdit)
              ListTile(
                leading: Icon(Icons.edit, color: kAccentColor),
                title: Text(
                  "Редактировать альбом",
                  style: TextStyle(color: kPrimaryColor),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          CreateAlbumScreen(albumData: album),
                    ),
                  );
                  _fetchAlbums();
                },
              ),
            if (canDelete)
              ListTile(
                leading: Icon(Icons.delete, color: kAccentColor),
                title: Text(
                  "Удалить альбом",
                  style: TextStyle(color: kPrimaryColor),
                ),
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


  Widget _buildAlbumCover(Map<String, dynamic> album) {
    final photos = album['photos'] as List<dynamic>? ?? [];
    if (photos.isNotEmpty && photos[0] is Map<String, dynamic>) {
      final firstPhoto = photos[0] as Map<String, dynamic>;
      final imageUrl = firstPhoto['url'];
      if (imageUrl != null && imageUrl is String && imageUrl.isNotEmpty) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            image: DecorationImage(
              image: NetworkImage(imageUrl),
              fit: BoxFit.cover,
            ),
          ),
        );
      }
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey.shade300,
      ),
      child: const Icon(Icons.photo_album, size: 32, color: Colors.white),
    );
  }

  Widget _buildAlbumCard(Map<String, dynamic> album) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _onAlbumTap(album),
      child: Card(
        color: kBackgroundColor,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: kPrimaryColor.withOpacity(0.5))),
        elevation: 4,
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(child: _buildAlbumCover(album)),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withOpacity(0.4),
                      Colors.black.withOpacity(0.1)
                    ],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 8,
              left: 8,
              right: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album['name'] ?? "Без названия",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      shadows: [
                        Shadow(
                            offset: Offset(1, 1),
                            blurRadius: 3,
                            color: Colors.black),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${(album['photos'] as List).length} фото",
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      shadows: [
                        Shadow(
                            offset: Offset(1, 1),
                            blurRadius: 2,
                            color: Colors.black),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onPressed: () {
                  _showAlbumOptions(album);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumGrid(List<Map<String, dynamic>> albums) {
    return RefreshIndicator(
      onRefresh: _fetchAlbums,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: albums.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.8,
        ),
        itemBuilder: (context, index) {
          return _buildAlbumCard(albums[index]);
        },
      ),
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
              _onAlbumTap(album);
            },
            child: Text("Просмотреть"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Map<String, dynamic> newAlbumData =
                  Map<String, dynamic>.from(album);
              newAlbumData.remove('id');
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      CreateAlbumScreen(albumData: newAlbumData),
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
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    List<Map<String, dynamic>> suggestedAlbums =
        await _generateSuggestedAlbums();
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: kBackgroundColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 50,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: kPrimaryColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Предложенные альбомы",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: kPrimaryColor,
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kAccentColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const Center(
                                child: CircularProgressIndicator()),
                          );
                          List<Map<String, dynamic>> newAlbums =
                              await _generateSuggestedAlbums();
                          Navigator.pop(context);
                          setModalState(() {
                            suggestedAlbums = newAlbums;
                          });
                        },
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        label: const Text("Новые",
                            style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Чтобы предложения отображались, фотографии должны быть сохранены на сервере.",
                    style: const TextStyle(
                        fontSize: 14,
                        color: Colors.redAccent,
                        fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: suggestedAlbums.length,
                      itemBuilder: (context, index) {
                        final album = suggestedAlbums[index];
                        return Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 3,
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            leading: album['photos'].isNotEmpty
                                ? _buildSuggestedAlbumCover(album['photos'][0])
                                : Container(
                                    width: 60, height: 60, color: Colors.grey),
                            title: Text(
                              album['name'],
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: kPrimaryColor,
                              ),
                            ),
                            subtitle: Text(
                              "${album['photos'].length} фото",
                              style: TextStyle(color: kPrimaryColor),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              _handleSuggestedAlbumSelection(album);
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: kAppBarColor,
        appBar: AppBar(
          backgroundColor: kAppBarColor,
          title:
              const Text("Фотоальбомы", style: TextStyle(color: kBackgroundColor)),
          bottom: TabBar(
            indicator: BoxDecoration(
              color: kAccentColor, 
              borderRadius: BorderRadius.circular(10),
            ),
            indicatorSize:
                TabBarIndicatorSize.tab, 
            labelColor:
                kPrimaryColor, 
            unselectedLabelColor:
                Colors.white70, 
            labelStyle:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            tabs: const [
              Tab(text: "Мои альбомы"),
              Tab(text: "Чужие альбомы"),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.auto_awesome, color: kBackgroundColor),
              tooltip: "Предложенные альбомы",
              onPressed: _showSuggestedAlbums,
            ),
          ],
        ),

        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildAlbumGrid(_userAlbums),
                  _buildAlbumGrid(_sharedAlbums),
                ],
              ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: kAccentColor,
          child: const Icon(Icons.add),
          tooltip: "Создать альбом",
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
      ),
    );
  }
}
