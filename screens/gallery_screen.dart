import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:translator/translator.dart';
import 'package:intl/intl.dart';
import 'package:trip/screens/create_album_screen.dart';
import 'package:trip/models/photo_tile.dart';
import 'package:trip/screens/photo_view_screen.dart';
import 'package:trip/screens/tags_screen.dart';
import 'package:trip/services/photo_service.dart';
import 'package:trip/services/profile_service.dart';

class MergeAndGroupPhotosParams {
  final List<AssetEntity> localPhotos;
  final List<dynamic> serverPhotos;
  final List<dynamic>? folderFilter;

  MergeAndGroupPhotosParams({
    required this.localPhotos,
    required this.serverPhotos,
    this.folderFilter,
  });
}

Map<String, List<dynamic>> mergeAndGroupPhotos(
  List<AssetEntity> localPhotos,
  List<dynamic> serverPhotos, {
  List<dynamic>? folderFilter,
}) {
  Set<String> serverPhotoIds = {};
  for (var serverPhoto in serverPhotos) {
    final id = serverPhoto['id'];
    if (id != null) {
      serverPhotoIds.add(id);
    }
  }

  List<Map<String, dynamic>> localList = [];
  for (var photo in localPhotos) {
    if (photo.title != null && serverPhotoIds.contains(photo.title)) continue;
    if (folderFilter != null && folderFilter.isNotEmpty) {
      if (!folderFilter.contains(photo.title)) continue;
    }
    localList.add({
      'type': 'local',
      'photo': photo,
      'date': photo.createDateTime,
    });
  }

  List<Map<String, dynamic>> serverList = [];
  for (var serverPhoto in serverPhotos) {
    Map<String, dynamic> exifData = serverPhoto['exif'] ?? {};
    DateTime date;
    if (exifData.containsKey('EXIF DateTimeOriginal')) {
      String dateTimeString = exifData['EXIF DateTimeOriginal'];
      try {
        date = DateFormat('yyyy:MM:dd HH:mm:ss').parse(dateTimeString);
      } catch (e) {
        date = DateTime.now();
      }
    } else {
      date = DateTime.now();
    }
    if (folderFilter != null && folderFilter.isNotEmpty) {
      if (!folderFilter.contains(serverPhoto['id'])) continue;
    }
    serverList.add({
      'type': 'server',
      'photo': serverPhoto,
      'date': date,
    });
  }
  serverList.sort((a, b) => b['date'].compareTo(a['date']));
  int i = 0, j = 0;
  List<Map<String, dynamic>> merged = [];
  while (i < localList.length && j < serverList.length) {
    if (localList[i]['date'].isAfter(serverList[j]['date'])) {
      merged.add(localList[i]);
      i++;
    } else {
      merged.add(serverList[j]);
      j++;
    }
  }
  while (i < localList.length) {
    merged.add(localList[i]);
    i++;
  }
  while (j < serverList.length) {
    merged.add(serverList[j]);
    j++;
  }

  Map<String, List<dynamic>> groupedPhotos = {};
  DateFormat formatter = DateFormat('yyyy-MM-dd');
  for (var photo in merged) {
    String dateKey = formatter.format(photo['date']);
    groupedPhotos[dateKey] ??= [];
    groupedPhotos[dateKey]!.add(photo);
  }

  return groupedPhotos;
}

Map<String, List<dynamic>> _mergeAndGroupPhotosWrapper(
    MergeAndGroupPhotosParams params) {
  return mergeAndGroupPhotos(
    params.localPhotos,
    params.serverPhotos,
    folderFilter: params.folderFilter,
  );
}

// ignore: must_be_immutable
class GalleryScreen extends StatefulWidget {
  bool multiSelectMode;
  final String? source;
  Map<String, List<AssetEntity>>? photoTags;
  final List<String>? selectedTags;
  final List<dynamic>? folderFilter;
  Map<AssetEntity, List<String>>? localPhotoTags;
  final String? folderId;
  final List<AssetEntity>? preFilteredPhotos;

  GalleryScreen({
    this.multiSelectMode = false,
    this.source,
    this.selectedTags,
    this.photoTags,
    this.localPhotoTags,
    this.folderFilter,
    this.folderId,
     this.preFilteredPhotos,
  });

  @override
  _GalleryScreenState createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ProfileService _profileService = ProfileService();
  final PhotoService _photoService = PhotoService();
  List<AssetEntity> _photos = [];
  List<Map<String, dynamic>> _serverPhotos = [];
  Map<AssetEntity, List<String>> localPhotoTags = {};
  Map<String, List<AssetEntity>>? _photoTags = {};
  Map<String, List<dynamic>> _photosGroupedByDate = {};
  Set<dynamic> _selectedPhotos = {};
  bool _loading = true;
  bool _hideLocalPhotos = false;
  bool _tagsLoading = false;
  double _progress = 0.0;
  bool _isFilteredByTag = false;
  bool _cancelTagGeneration = false;
  List<String> _activeTags = [];
  DateTime? _startDate;
  DateTime? _endDate;
  List<dynamic>? _currentFolderFilter;
  List<String> _userLocalFavorites = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<String> _suggestedTags = [];
  String? _source;
  late AnimationController _loadingController;
  Color kBackgroundColor = Color(0xFFF5EEDC); 
  Color kPrimaryColor = Color(0xFF27548A); 
  Color kAppBarColor = Color(0xFF183B4E); 
  Color kAccentColor = Color(0xFFDDA853); 

  @override
void initState() {
  super.initState();

  _source = widget.source;

  if (widget.localPhotoTags != null) {
    localPhotoTags = widget.localPhotoTags!;
  }
  if (widget.selectedTags != null && widget.selectedTags!.isNotEmpty) {
    _activeTags = widget.selectedTags!;
    _isFilteredByTag = true;
  }
  if (widget.folderFilter != null) {
    _currentFolderFilter = widget.folderFilter;
  }

  _setLocale();
  _searchController.addListener(() {
    setState(() {
      _searchQuery = _searchController.text;
    });
    _updateSuggestions(_searchController.text);
  });
  _fetchUserLocalFavorites();
  _fetchPhotosAndGenerateTags();
  _loadingController = AnimationController(
    vsync: this, 
    duration: const Duration(seconds: 2)
  )..repeat();
}


  @override
  void dispose() {
    _searchController.dispose();
    _loadingController.dispose();
    super.dispose();
  }

  Future<void> _setLocale() async {
    await initializeDateFormatting('ru_RU', null);
    Intl.defaultLocale = 'ru_RU';
  }

  void _updateSuggestions(String query) {
    if (query.isEmpty) {
      setState(() => _suggestedTags = []);
    } else {
      Set<String> visibleServerTags = _getVisibleServerTags();
      if (_photoTags != null && _photoTags!.isNotEmpty) {
        visibleServerTags.addAll(_photoTags!.keys);
      }
      List<String> suggestions = visibleServerTags
          .where((tag) => tag.toLowerCase().contains(query.toLowerCase()))
          .take(5)
          .toList();
      setState(() {
        _suggestedTags = suggestions;
      });
    }
  }

  Future<void> _confirmGenerateTags() async {
    List<AssetEntity> filteredLocalPhotos = _startDate != null &&
            _endDate != null
        ? _photos.where((photo) {
            final dt = photo.createDateTime;
            return dt.isAfter(_startDate!.subtract(const Duration(days: 1))) &&
                dt.isBefore(_endDate!.add(const Duration(days: 1)));
          }).toList()
        : _photos;

    if (filteredLocalPhotos.length >= 500) {
      bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFFF5EEDC),
          title: const Text("Предупреждение",
              style: TextStyle(color: Color(0xFF183B4E))),
          content: const Text(
              "Рекомендуем генерировать теги для менее чем 500 локальных фотографий, "
              "иначе процесс займет значительное время. Выберите нужные фото при помощи папок и дат.",
              style: TextStyle(color: Color(0xFF183B4E))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Отмена",
                  style: TextStyle(color: Color(0xFF27548A))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDDA853)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Продолжить",
                  style: TextStyle(color: Color(0xFF183B4E))),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    _generateTagsForPhotos();
  }

  Widget buildCustomLoadingOverlay(String message) {
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
                      colors: [Color(0xFF27548A), Color(0xFFDDA853)],
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
            Text(
              message,
              style: const TextStyle(
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

  Future<void> _fetchUserLocalFavorites() async {
    User? currentUser = _auth.currentUser;
    if (currentUser == null) return;
    DocumentSnapshot doc = await FirebaseFirestore.instance
        .collection('userFavorites')
        .doc(currentUser.uid)
        .get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>?;
      setState(() {
        _userLocalFavorites = List<String>.from(data?['localPhotos'] ?? []);
      });
    }
  }

 Future<void> _fetchPhotosAndGenerateTags() async {
  final PermissionState result = await PhotoManager.requestPermissionExtend();
  if (result == PermissionState.authorized) {
    var fetchedServerPhotos = await _photoService.fetchPhotosFromFirestore();
    if (_source == "favorites") {
      User? currentUser = _auth.currentUser;
      if (currentUser != null) {
        fetchedServerPhotos = fetchedServerPhotos.where((photo) {
          List<dynamic> favs = photo['favorites'] ?? [];
          return favs.contains(currentUser.uid);
        }).toList();
      }
    }
    
    if (_source == "tags" && widget.preFilteredPhotos != null && _activeTags.isNotEmpty) {
      _photos = widget.preFilteredPhotos!;
      List<dynamic> filteredServerPhotos = fetchedServerPhotos.where((serverPhoto) {
        List<dynamic> serverTags = serverPhoto['tags'] ?? [];
        return _activeTags.any((tag) =>
            serverTags.any((serverTag) =>
                serverTag.toString().toLowerCase() ==
                tag.toString().toLowerCase()));
      }).toList();
    
      final params = MergeAndGroupPhotosParams(
        localPhotos: _photos,
        serverPhotos: filteredServerPhotos,
        folderFilter: _currentFolderFilter,
      );
      Map<String, List<dynamic>> groupedPhotos =
          await compute(_mergeAndGroupPhotosWrapper, params);
      setState(() {
        _photosGroupedByDate = groupedPhotos;
        _loading = false;
      });
    } else {
      await _fetchLocalPhotos();
      
      if (_source == "favorites") {
        _photos = _photos.where((p) => _userLocalFavorites.contains(p.title)).toList();
      }
      
      final params = MergeAndGroupPhotosParams(
        localPhotos: _photos,
        serverPhotos: fetchedServerPhotos,
        folderFilter: _currentFolderFilter,
      );
      Map<String, List<dynamic>> groupedPhotos =
          await compute(_mergeAndGroupPhotosWrapper, params);
      setState(() {
        _photosGroupedByDate = groupedPhotos;
        _loading = false;
      });
    }
  } else {
    setState(() {
      _loading = false;
    });
  }
}



  void _updateGroupsIncrementally(List<AssetEntity> newPhotos) {
    DateFormat formatter = DateFormat('yyyy-MM-dd');
    setState(() {
      for (var photo in newPhotos) {
        String key = formatter.format(photo.createDateTime);
        var photoItem = {
          'type': 'local',
          'photo': photo,
          'date': photo.createDateTime,
        };
        if (_photosGroupedByDate.containsKey(key)) {
          _photosGroupedByDate[key]!.add(photoItem);
        } else {
          _photosGroupedByDate[key] = [photoItem];
        }
      }
    });
  }

  Future<void> _fetchLocalPhotos() async {
    List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(
      type: RequestType.image,
    );
    Set<AssetEntity> uniqueImages = {};
    if (widget.folderFilter != null && widget.folderFilter!.isNotEmpty) {
      List<String> requiredPhotoTitles =
          List<String>.from(widget.folderFilter!);
      for (var path in paths) {
        int totalCount = await path.assetCountAsync;
        int end = totalCount > 300 ? 300 : totalCount;
        final List<AssetEntity> assets =
            await path.getAssetListRange(start: 0, end: end);
        for (var asset in assets) {
          if (requiredPhotoTitles.contains(asset.title)) {
            uniqueImages.add(asset);
            requiredPhotoTitles.remove(asset.title);
          }
        }
        if (requiredPhotoTitles.isEmpty) break;
      }
      setState(() {
        _photos = uniqueImages.toList();
      });
    } else if (_source == "favorites") {
      Set<AssetEntity> favoritePhotos = {};
      final Set<String> favoriteTitles = _userLocalFavorites.toSet();
      for (var path in paths) {
        int totalCount = await path.assetCountAsync;
        final List<AssetEntity> assets =
            await path.getAssetListRange(start: 0, end: totalCount);
        for (var asset in assets) {
          if (asset.title != null && favoriteTitles.contains(asset.title)) {
            favoritePhotos.add(asset);
            if (favoritePhotos.length == favoriteTitles.length) break;
          }
        }
        if (favoritePhotos.length == favoriteTitles.length) break;
      }
      setState(() {
        _photos = favoritePhotos.toList();
      });
    } else {
      int fetchedCount = 0;
      for (var path in paths) {
        int totalCount = await path.assetCountAsync;
        if (fetchedCount >= 500) break;
        int toFetch = totalCount;
        if (fetchedCount + totalCount > 500) {
          toFetch = 500 - fetchedCount;
        }
        final List<AssetEntity> assets =
            await path.getAssetListRange(start: 0, end: toFetch);
        uniqueImages.addAll(assets);
        fetchedCount += assets.length;
      }
      setState(() {
        _photos = uniqueImages.toList();
      });

      Future(() async {
        Set<AssetEntity> allImages = {};
        for (var path in paths) {
          int totalCount = await path.assetCountAsync;
          final List<AssetEntity> assets =
              await path.getAssetListRange(start: 0, end: totalCount);
          allImages.addAll(assets);
        }
        final newPhotos = allImages.difference(_photos.toSet()).toList();
        if (newPhotos.isNotEmpty) {
          setState(() {
            _photos.addAll(newPhotos);
          });
          _updateGroupsIncrementally(newPhotos);
        }
      });
    }
  }

  void _groupPhotosByDate() async {
    List<dynamic> allPhotos = [];
    for (var photo in _photos) {
      allPhotos.add({
        'type': 'local',
        'photo': photo,
        'date': photo.createDateTime,
      });
    }
    for (var serverPhoto in _serverPhotos) {
      Map<String, dynamic> exifData = serverPhoto['exif'] ?? {};
      DateTime serverDate;
      if (exifData.containsKey('EXIF DateTimeOriginal')) {
        String dateTimeString = exifData['EXIF DateTimeOriginal'];
        try {
          serverDate = DateFormat('yyyy:MM:dd HH:mm:ss').parse(dateTimeString);
        } catch (e) {
          print("Ошибка парсинга EXIF даты: $e");
          serverDate = DateTime.now();
        }
      } else {
        serverDate = DateTime.now();
      }
      allPhotos.add({
        'type': 'server',
        'photo': serverPhoto,
        'date': serverDate,
      });
    }
    if (_currentFolderFilter != null && _currentFolderFilter!.isNotEmpty) {
      allPhotos = allPhotos.where((item) {
        if (item['type'] == 'server') {
          return _currentFolderFilter!.contains(item['photo']['id']);
        } else if (item['type'] == 'local') {
          return _currentFolderFilter!.contains(item['photo'].title);
        }
        return false;
      }).toList();
    }
    final params = MergeAndGroupPhotosParams(
      localPhotos: _photos,
      serverPhotos: _serverPhotos,
      folderFilter: _currentFolderFilter,
    );

    Map<String, List<dynamic>> groupedPhotos =
        await compute(_mergeAndGroupPhotosWrapper, params);
    setState(() {
      _photosGroupedByDate = groupedPhotos;
      _loading = false;
    });
  }

  String _getFormattedDateFromExif(Map<String, dynamic> exifData) {
    String dateTimeString = exifData['EXIF DateTimeOriginal'] ?? '';
    if (dateTimeString.isEmpty) return '';
    try {
      DateTime dateTime =
          DateFormat('yyyy:MM:dd HH:mm:ss').parse(dateTimeString);
      return DateFormat('yyyy-MM-dd').format(dateTime);
    } catch (e) {
      print("Ошибка парсинга: $e");
      return '';
    }
  }

  Future<void> _updateFolderFilter() async {
    if (widget.folderId != null) {
      final doc = await FirebaseFirestore.instance
          .collection('folders')
          .doc(widget.folderId)
          .get();
      if (doc.exists) {
        setState(() {
          _currentFolderFilter = doc.data()?['photos'] as List<dynamic>?;
        });
      }
    }
  }

  Set<String> _getVisibleServerTags() {
    Set<String> tags = {};
    List<dynamic> visible = _visiblePhotos();
    for (var item in visible) {
      if (item['type'] == 'server') {
        List<dynamic> serverTags = item['photo']['tags'] ?? [];
        for (var tag in serverTags) {
          if (tag is String) {
            tags.add(tag);
          }
        }
      }
    }
    return tags;
  }

  List<dynamic> _visiblePhotos() {
    var allPhotos = _photosGroupedByDate.values.expand((e) => e).toList();
    if (_hideLocalPhotos) {
      allPhotos = allPhotos.where((item) => item['type'] == 'server').toList();
    }
    if (_searchQuery.isNotEmpty) {
      allPhotos = allPhotos.where((item) {
        if (item['type'] == 'server') {
          final sp = item['photo'];
          final tags = (sp['tags'] ?? []) as List<dynamic>;
          final ocrText = (sp['ocrText'] ?? '').toString();
          return tags.any((t) => t
                  .toString()
                  .toLowerCase()
                  .contains(_searchQuery.toLowerCase())) ||
              ocrText.toLowerCase().contains(_searchQuery.toLowerCase());
        } else {
          final lp = item['photo'] as AssetEntity;
          final tags = localPhotoTags[lp];
          if (tags == null) return false;
          return tags.any(
              (tag) => tag.toLowerCase().contains(_searchQuery.toLowerCase()));
        }
      }).toList();
    }
    if (_isFilteredByTag && _activeTags.isNotEmpty) {
      allPhotos = allPhotos.where((item) {
        if (item['type'] == 'server') {
          final tags = (item['photo']['tags'] ?? []) as List<dynamic>;
          return tags.any((tag) => _activeTags.any((activeTag) =>
              tag.toString().toLowerCase() ==
              activeTag.toString().toLowerCase()));
        } else {
          final lp = item['photo'] as AssetEntity;
          final localTags = localPhotoTags[lp];
          return localTags != null &&
              localTags.any((t) => _activeTags.any(
                  (activeTag) => t.toLowerCase() == activeTag.toLowerCase()));
        }
      }).toList();
    }
    if (_startDate != null && _endDate != null) {
      allPhotos = allPhotos.where((item) {
        final dt = item['date'] as DateTime;
        return dt.isAfter(_startDate!.subtract(const Duration(days: 1))) &&
            dt.isBefore(_endDate!.add(const Duration(days: 1)));
      }).toList();
    }
    return allPhotos;
  }

  List<Widget> _buildGallerySlivers() {
    final photos = _visiblePhotos();
    if (photos.isEmpty) {
      return [
        SliverFillRemaining(
          child: Center(
            child: Text(
              "Нет фотографий",
              style: TextStyle(color: const Color(0xFF183B4E), fontSize: 16),
            ),
          ),
        ),
      ];
    }
    Map<String, List<dynamic>> groups = {};
    DateFormat formatter = DateFormat('yyyy-MM-dd', 'ru_RU');
    for (var item in photos) {
      String key = formatter.format(item['date']);
      groups[key] ??= [];
      groups[key]!.add(item);
    }
    List<String> dateKeys = groups.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    List<Widget> slivers = [];
    for (String dateKey in dateKeys) {
      DateTime parsedDate = DateTime.parse(dateKey);
      String formattedDate =
          DateFormat('dd MMMM yyyy', 'ru_RU').format(parsedDate);
      List<dynamic> groupPhotos = groups[dateKey] ?? [];
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
            child: widget.multiSelectMode
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        formattedDate,
                        style: const TextStyle(
                          color: Color(0xFF183B4E),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Checkbox(
                        activeColor: const Color(0xFFDDA853),
                        value: _areAllPhotosSelected(groupPhotos),
                        onChanged: (bool? value) {
                          setState(() {
                            if (value == true) {
                              for (var photoItem in groupPhotos) {
                                _selectedPhotos.add(photoItem);
                              }
                            } else {
                              for (var photoItem in groupPhotos) {
                                _selectedPhotos.remove(photoItem);
                              }
                            }
                          });
                        },
                      ),
                    ],
                  )
                : Text(
                    formattedDate,
                    style: const TextStyle(
                      color: Color(0xFF183B4E),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      );
      slivers.add(
        SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 4.0,
            mainAxisSpacing: 4.0,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final photoItem = groupPhotos[index];
              return _buildPhotoItem(photoItem);
            },
            childCount: groupPhotos.length,
          ),
        ),
      );
    }
    return slivers;
  }

  bool _areAllPhotosSelected(List<dynamic> groupPhotos) {
    for (var photoItem in groupPhotos) {
      if (!_selectedPhotos.contains(photoItem)) {
        return false;
      }
    }
    return true;
  }

  Widget _buildPhotoItem(dynamic photoItem) {
    return PhotoItemWidget(
      key: ValueKey(photoItem.hashCode),
      photoItem: photoItem,
      isSelected: _selectedPhotos.contains(photoItem),
      isFavoriteOverride: _isPhotoFavorite(photoItem),
      onTap: () {
        if (widget.multiSelectMode) {
          setState(() {
            if (_selectedPhotos.contains(photoItem)) {
              _selectedPhotos.remove(photoItem);
            } else {
              _selectedPhotos.add(photoItem);
            }
          });
        } else {
          List<dynamic> visiblePhotos = _visiblePhotos();
          int index = visiblePhotos.indexOf(photoItem);
          if (index < 0) {
            if (photoItem['type'] == 'server') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PhotoViewScreen.server(
                    serverPhoto: photoItem['photo'],
                    folderId: widget.folderId,
                  ),
                ),
              ).then((_) async {
                await _updateFolderFilter();
                await _fetchPhotosAndGenerateTags();
                await _fetchUserLocalFavorites();
              });
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PhotoViewScreen.local(
                    localPhoto: photoItem['photo'],
                    folderId: widget.folderId,
                  ),
                ),
              ).then((_) async {
                await _updateFolderFilter();
                await _fetchPhotosAndGenerateTags();
                await _fetchUserLocalFavorites();
              });
            }
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PhotoViewScreen.multiple(
                  photoList:
                      visiblePhotos.map((item) => item['photo']).toList(),
                  initialIndex: index,
                  folderId: widget.folderId,
                ),
              ),
            ).then((_) async {
              await _updateFolderFilter();
              await _fetchUserLocalFavorites();
              await _fetchPhotosAndGenerateTags();
            });
          }
        }
      },
      onLongPress: () {
        if (!widget.multiSelectMode) {
          setState(() {
            widget.multiSelectMode = true;
            _selectedPhotos.add(photoItem);
          });
        }
      },
    );
  }

  bool _isPhotoFavorite(dynamic photoItem) {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return false;
    if (photoItem['type'] == 'server') {
      final sp = photoItem['photo'];
      final favs = sp['favorites'] ?? [];
      return favs.contains(currentUser.uid);
    } else {
      final lp = photoItem['photo'] as AssetEntity;
      final id = lp.title;
      if (id == null) return false;
      return _userLocalFavorites.contains(id);
    }
  }

  Future<void> _deleteSelectedPhotos() async {
    if (_selectedPhotos.isEmpty) return;
    int serverCount =
        _selectedPhotos.where((photo) => photo['type'] == 'server').length;
    if (serverCount > 1) {
      bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFFF5EEDC),
          title: const Text("Подтверждение",
              style: TextStyle(color: Color(0xFF183B4E))),
          content: Text(
              "Вы выбрали $serverCount серверных фото. Вы уверены, что хотите их удалить?",
              style: const TextStyle(color: Color(0xFF183B4E))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Отмена",
                  style: TextStyle(color: Color(0xFF27548A))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDDA853)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Удалить",
                  style: TextStyle(color: Color(0xFF183B4E))),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (widget.folderId != null) {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFFF5EEDC),
          title: const Text("Подтверждение",
              style: TextStyle(color: Color(0xFF183B4E))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  "Удалить фото только из папки или полностью из галереи?",
                  style: TextStyle(color: Color(0xFF183B4E))),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: const Color(0xFFDDA853),
                      ),
                      onPressed: () => Navigator.pop(context, "folder"),
                      child: const Text(
                        "Из папки",
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFF183B4E)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: const Color(0xFFDDA853),
                      ),
                      onPressed: () => Navigator.pop(context, "gallery"),
                      child: const Text(
                        "Из галереи",
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFF183B4E)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context, "cancel"),
                child: const Text(
                  "Отмена",
                  style: TextStyle(fontSize: 12, color: Color(0xFF27548A)),
                ),
              ),
            ],
          ),
        ),
      );
      if (choice == "cancel" || choice == null) return;
      if (choice == "folder") {
        await _photoService.removePhotosFromFolder(
            _selectedPhotos, widget.folderId);
        await _updateFolderFilter();
      } else {
        await _deletePhotosFromGallery(_selectedPhotos);
      }
    } else {
      await _deletePhotosFromGallery(_selectedPhotos);
    }
    _showCustomMessage('${_selectedPhotos.length} фото удалено');
    _toggleMultiSelect();
    _fetchPhotosAndGenerateTags();
  }

  Future<void> _deletePhotosFromGallery(Set<dynamic> photos) async {
    List<dynamic> serverPhotos = [];
    List<AssetEntity> localPhotos = [];
    for (var photo in photos) {
      if (photo['type'] == 'server') {
        serverPhotos.add(photo);
      } else {
        localPhotos.add(photo['photo']);
      }
    }

    if (serverPhotos.isNotEmpty) {
      bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFFF5EEDC),
          title: const Text("Подтверждение",
              style: TextStyle(color: Color(0xFF183B4E))),
          content: Text(
              "Вы уверены, что хотите удалить ${serverPhotos.length} серверных фото?",
              style: const TextStyle(color: Color(0xFF183B4E))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Отмена",
                  style: TextStyle(color: Color(0xFF27548A))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDDA853)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Удалить",
                  style: TextStyle(color: Color(0xFF183B4E))),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    for (var sp in serverPhotos) {
      await _photoService.deleteServerPhoto(sp['photo']);
    }
    if (localPhotos.isNotEmpty) {
      await PhotoManager.editor
          .deleteWithIds(localPhotos.map((p) => p.id).toList());
    }
  }

  void _toggleMultiSelect() {
    setState(() {
      widget.multiSelectMode = !widget.multiSelectMode;
      if (!widget.multiSelectMode) _selectedPhotos.clear();
    });
  }

  void _showActionsBottomSheet() {
    List<Widget> actions = [];
    if (!_tagsLoading && _source != "tags") {
      actions.add(_buildActionItem(
          Icons.label, "Сгенерировать теги", _confirmGenerateTags));
    }
    if (_source != "tags" && _photoTags != null && _photoTags!.isNotEmpty) {
      actions.add(_buildActionItem(Icons.cloud, "Посмотреть теги", () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TagsScreen(
              photoTags: _photoTags,
              localPhotoTags: localPhotoTags,
            ),
          ),
        );
      }));
    }
    actions.add(_buildActionItem(
      Icons.select_all,
      widget.multiSelectMode ? "Выйти из выбора" : "Выбрать несколько",
      _toggleMultiSelect,
    ));
    if (widget.multiSelectMode) {
      actions.add(_buildActionItem(Icons.done_all, "Выбрать все", () {
        var visible = _visiblePhotos();
        setState(() {
          _selectedPhotos = visible.toSet();
        });
      }));
      actions.add(_buildActionItem(
          Icons.star,
          _selectedPhotos.every((photo) => _isPhotoFavorite(photo))
              ? "Убрать избранное"
              : "Добавить в избранное", () async {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              buildCustomLoadingOverlay("Пожалуйста, подождите..."),
        );
        for (var photo in _selectedPhotos) {
          if (photo['type'] == 'server') {
            await _photoService.toggleFavorite(photo['photo']);
          } else {
            await _photoService.toggleFavoriteLocal(photo['photo']);
          }
        }
        Navigator.pop(context);
        await _fetchUserLocalFavorites();
        await _fetchPhotosAndGenerateTags();
      }));
      actions.add(_buildActionItem(
          Icons.delete, "Удалить выбранные", _deleteSelectedPhotos));
      actions.add(_buildActionItem(
          Icons.share, "Поделиться выбранными", _onPressShareMultiple));
      actions.add(_buildActionItem(
          Icons.cloud_upload, "Загрузить на сервер", _uploadSelectedPhotos));
      if (_source == "album_creation") {
        actions.add(_buildActionItem(Icons.photo_album, "Создать альбом", () {
          Navigator.pop(context, _selectedPhotos.toList());
        }));
      } else if (_source == "folder_selection") {
        actions.add(_buildActionItem(Icons.save, "Сохранить выбранные", () {
          Navigator.pop(context, _selectedPhotos.toList());
        }));
      } else {
        actions.add(_buildActionItem(Icons.photo_album, "Создать альбом", () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  CreateAlbumScreen(selected: _selectedPhotos.toList()),
            ),
          );
        }));
      }
      actions.add(_buildActionItem(Icons.create_new_folder, "Создать папку",
          _createFolderFromSelectedPhotos));
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: const Color(0xFFF5EEDC),
      builder: (context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 50,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 3,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.8,
                    children: actions,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingDialog(String title, String subtitle) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0xFF27548A), Color(0xFFDDA853)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            buildCustomLoadingOverlay("Пожалуйста, подождите..."),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionItem(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        Future.delayed(const Duration(milliseconds: 300), onTap);
      },
      child: SizedBox(
        width: 100,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5EEDC),
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(icon, size: 28, color: const Color(0xFFDDA853)),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF183B4E)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createFolderFromSelectedPhotos() async {
    final folderNameController = TextEditingController();
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFF5EEDC),
        title: const Text("Создать папку",
            style: TextStyle(color: Color(0xFF183B4E))),
        content: TextField(
          controller: folderNameController,
          decoration: const InputDecoration(
            labelText: "Название папки",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Отмена",
                style: TextStyle(color: Color(0xFF27548A))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDDA853)),
            onPressed: () async {
              String folderName = folderNameController.text.trim();
              if (folderName.isNotEmpty) {
                List selectedPhotoIds = _selectedPhotos
                    .map((item) {
                      if (item['type'] == 'server') {
                        return item['photo']['id'];
                      } else {
                        return item['photo'].title;
                      }
                    })
                    .where((id) => id != null && id.toString().isNotEmpty)
                    .toList();
                DocumentReference folderRef =
                    await FirebaseFirestore.instance.collection('folders').add({
                  'name': folderName,
                  'owner': currentUser.uid,
                  'photos': selectedPhotoIds,
                  'createdAt': FieldValue.serverTimestamp(),
                  'sharedWith': {}
                });

                for (var item in _selectedPhotos) {
                  if (item['type'] == 'server') {
                    String photoId = item['photo']['id'];
                    final querySnapshot = await FirebaseFirestore.instance
                        .collection('photos')
                        .where('id', isEqualTo: photoId)
                        .limit(1)
                        .get();
                    if (querySnapshot.docs.isNotEmpty) {
                      final photoDoc = querySnapshot.docs.first;
                      await photoDoc.reference.update({
                        'folderIds': FieldValue.arrayUnion([folderRef.id]),
                        'folderShares.${folderRef.id}': {},
                      });
                    }
                  }
                }

                Navigator.pop(context);
                _showCustomMessage("Папка создана");
                setState(() {
                  widget.multiSelectMode = false;
                  _selectedPhotos.clear();
                });
              }
            },
            child: const Text("Создать",
                style: TextStyle(color: Color(0xFF183B4E))),
          ),
        ],
      ),
    );
  }

  void _onPressShareMultiple() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          buildCustomLoadingOverlay("Пожалуйста, подождите..."),
    );
    try {
      List<Map<String, dynamic>> usersList =
          await _profileService.getUsersList();
      List<Map<String, dynamic>>? selectedUsers =
          await showPermissionSelectionBottomSheet(
        context: context,
        users: usersList
            .where((user) => user['id'] != _auth.currentUser!.uid)
            .toList(),
      );
      Navigator.of(context, rootNavigator: true).pop();
      if (selectedUsers == null || selectedUsers.isEmpty) {
        _showCustomMessage("Никто не выбран для отправки",
            icon: Icons.error_outline, backgroundColor: Colors.redAccent);
        return;
      }
      final _firestore = FirebaseFirestore.instance;
      List<Map<String, dynamic>> allowedUsers = [];
      List<String> notAllowedRecipients = [];
      for (var recipient in selectedUsers) {
        String recipientId = recipient['id'];
        final doc = await _firestore.collection('users').doc(recipientId).get();
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          String privacy = data['privacySetting'] ?? 'От всех пользователей';
          bool isAllowed = true;
          if (privacy == 'От некоторых пользователей') {
            var allowedUsersData = data['allowedUsers'];
            if (allowedUsersData is Map) {
              isAllowed = allowedUsersData.containsKey(_auth.currentUser!.uid);
            } else if (allowedUsersData is List) {
              isAllowed = allowedUsersData.contains(_auth.currentUser!.uid);
            }
          } else if (privacy == 'Нет') {
            isAllowed = false;
          }
          if (isAllowed) {
            allowedUsers.add(recipient);
          } else {
            notAllowedRecipients
                .add(data['nickname'] ?? data['email'] ?? 'Unknown');
          }
        }
      }
      if (allowedUsers.isEmpty) {
        _showCustomMessage(
            "Невозможно отправить фотографии выбранным пользователям",
            icon: Icons.error_outline,
            backgroundColor: Colors.redAccent);
        return;
      }
      for (var photoItem in _selectedPhotos) {
        if (photoItem['type'] == 'server') {
          bool ok = await _shareServerPhoto(photoItem['photo'], allowedUsers);
          if (!ok) {
            print(
                "Ошибка отправки серверного фото: ${photoItem['photo']['id']}");
          }
        } else {
          await _shareLocalPhoto(photoItem['photo'], allowedUsers);
        }
      }
      String message = "Фотографии успешно отправлены";
      if (notAllowedRecipients.isNotEmpty) {
        message += ". Не отправлено для: " + notAllowedRecipients.join(', ');
      }
      _showCustomMessage(message);
    } catch (e) {
      _showCustomMessage("Ошибка при отправке: $e",
          icon: Icons.error_outline, backgroundColor: Colors.redAccent);
    }
  }

  Future<bool> _shareServerPhoto(
    Map<String, dynamic> serverPhoto,
    List<Map<String, dynamic>> selectedUsers,
  ) async {
    try {
      final photoId = serverPhoto['id'];
      final snapshot = await FirebaseFirestore.instance
          .collection('photos')
          .where('id', isEqualTo: photoId)
          .get();
      if (snapshot.docs.isNotEmpty) {
        Map<String, dynamic> sharedWith =
            Map<String, dynamic>.from(serverPhoto['sharedWith'] ?? {});
        for (var u in selectedUsers) {
          sharedWith[u['id']] = u['permission'];
        }
        await snapshot.docs.first.reference.update({'sharedWith': sharedWith});
        return true;
      } else {
        print("Фото с id $photoId не найдено");
        return false;
      }
    } catch (e) {
      print("Ошибка при отправке серверного фото: $e");
      return false;
    }
  }

  Future<void> _shareLocalPhoto(
    AssetEntity localPhoto,
    List<Map<String, dynamic>> selectedUsers,
  ) async {
    try {
      final existing = await FirebaseFirestore.instance
          .collection('photos')
          .where('id', isEqualTo: localPhoto.title)
          .get();
      Map<String, String> sharedWith = {};
      for (var user in selectedUsers) {
        sharedWith[user['id']] = user['permission'];
      }
      if (existing.docs.isNotEmpty) {
        await existing.docs.first.reference.update({'sharedWith': sharedWith});
      } else {
        await _photoService.pickAndUploadImage(localPhoto, null);
        final uploaded = await FirebaseFirestore.instance
            .collection('photos')
            .where('id', isEqualTo: localPhoto.title)
            .get();
        if (uploaded.docs.isNotEmpty) {
          await uploaded.docs.first.reference
              .update({'sharedWith': sharedWith});
        }
      }
    } catch (e) {
      print("Ошибка при отправке локального фото: $e");
    }
  }

  Future<List<Map<String, dynamic>>?> showPermissionSelectionBottomSheet({
    required BuildContext context,
    required List<Map<String, dynamic>> users,
    Map<String, String>? initialSelectedPermissions,
  }) async {
    Map<String, String> userPermissions = initialSelectedPermissions != null
        ? Map.from(initialSelectedPermissions)
        : {};
    final TextEditingController searchController = TextEditingController();
    List<Map<String, dynamic>> filteredUsers = [];

    void _filter(String query) {
      final lowerQuery = query.trim().toLowerCase();
      if (lowerQuery.isEmpty) {
        filteredUsers = [];
      } else {
        filteredUsers = users
            .where((u) {
              final displayName =
                  (u['displayName'] ?? '').toString().toLowerCase();
              final email = (u['email'] ?? '').toString().toLowerCase();
              return displayName.contains(lowerQuery) ||
                  email.contains(lowerQuery);
            })
            .take(10)
            .toList();
        for (final selectedUid in userPermissions.keys) {
          if (!filteredUsers.any((u) => u['id'] == selectedUid)) {
            final found = users.firstWhere((u) => u['id'] == selectedUid,
                orElse: () => {});
            if (found.isNotEmpty) filteredUsers.add(found);
          }
        }
      }
    }

    Widget _buildPermissionChips(String userId, StateSetter setStateModal) {
      final List<Map<String, dynamic>> permissionOptions = [
        {
          'value': 'view',
          'label': 'Только просмотр',
          'icon': Icons.visibility,
          'color': const Color(0xFF27548A),
        },
        {
          'value': 'save',
          'label': 'Просмотр + скачивание',
          'icon': Icons.download,
          'color': const Color(0xFFDDA853),
        },
      ];
      final currentValue = userPermissions[userId];
      return Wrap(
        spacing: 8,
        children: permissionOptions.map((option) {
          final isSelected = option['value'] == currentValue;
          return ChoiceChip(
            selected: isSelected,
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(option['icon'] as IconData,
                    size: 18,
                    color: isSelected ? Colors.white : option['color']),
                const SizedBox(width: 4),
                Text(option['label'] as String,
                    style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black,
                        fontSize: 13)),
              ],
            ),
            selectedColor: (option['color'] as Color).withOpacity(0.8),
            backgroundColor: Colors.grey[200],
            onSelected: (bool selected) {
              setStateModal(() {
                if (selected) {
                  userPermissions[userId] = option['value'] as String;
                }
              });
            },
          );
        }).toList(),
      );
    }

    return await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF5EEDC),
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
                              if (userId == null)
                                return const SizedBox.shrink();
                              final bool isSelected =
                                  userPermissions.containsKey(userId);
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
                                    activeColor: const Color(0xFFDDA853),
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
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        user['email'] ?? '',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(height: 4),
                                      if (isSelected)
                                        _buildPermissionChips(
                                            userId, setStateModal),
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
                            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFDDA853)),
                            onPressed: () {
                              final result = userPermissions.entries
                                  .map((e) =>
                                      {'id': e.key, 'permission': e.value})
                                  .toList();
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

  Future<void> _generateTagsForPhotos() async {
    setState(() {
      _cancelTagGeneration = false;
      _tagsLoading = true;
      _progress = 0.0;
    });
    final imageLabeler = ImageLabeler(options: ImageLabelerOptions());
    final translator = GoogleTranslator();

    final List<AssetEntity> filteredLocalPhotos = _startDate != null &&
            _endDate != null
        ? _photos.where((photo) {
            final dt = photo.createDateTime;
            return dt.isAfter(_startDate!.subtract(const Duration(days: 1))) &&
                dt.isBefore(_endDate!.add(const Duration(days: 1)));
          }).toList()
        : _photos;

    Map<String, List<AssetEntity>> newPhotoTags = {};
    int totalPhotos = filteredLocalPhotos.length;
    List<Future<void>> tasks = filteredLocalPhotos.map((photo) {
      return _processPhoto(
          photo, imageLabeler, translator, newPhotoTags, totalPhotos);
    }).toList();

    await Future.wait(tasks);
    await imageLabeler.close();

    if (!_cancelTagGeneration) {
      setState(() {
        _photoTags!.addAll(newPhotoTags);
      });
    }
    setState(() {
      _tagsLoading = false;
    });
  }

  Future<void> _processPhoto(
    AssetEntity photo,
    ImageLabeler imageLabeler,
    GoogleTranslator translator,
    Map<String, List<AssetEntity>> newPhotoTags,
    int totalPhotos,
  ) async {
    if (_cancelTagGeneration) return;
    final file = await photo.file;
    if (file == null || _cancelTagGeneration) return;
    final inputImage = InputImage.fromFile(file);
    final labels = await imageLabeler.processImage(inputImage);
    if (_cancelTagGeneration) return;

    List<String> photoTags = [];
    bool containsCyrillic(String s) {
      return RegExp(r'[А-Яа-я]').hasMatch(s);
    }

    for (var label in labels) {
      if (label.confidence >= 0.7) {
        String tag = label.label;
        if (!containsCyrillic(tag)) {
          try {
            final translation =
                await translator.translate(tag, from: 'en', to: 'ru');
            tag = translation.text;
          } catch (_) {}
        }
        photoTags.add(tag);
      }
    }
    localPhotoTags[photo] = photoTags;
    for (var tag in photoTags) {
      if (newPhotoTags.containsKey(tag)) {
        newPhotoTags[tag]!.add(photo);
      } else {
        newPhotoTags[tag] = [photo];
      }
    }
    setState(() {
      _progress += 1 / totalPhotos;
    });
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
                      colors: [Color(0xFF27548A), Color(0xFFDDA853)],
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
                child:
                    Text(message, style: const TextStyle(color: Colors.white))),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _uploadSelectedPhotos() async {
    if (_selectedPhotos.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          Center(child: buildCustomLoadingOverlay("Пожалуйста, подождите...")),
    );
    int uploadedCount = 0;
    for (var photoItem in _selectedPhotos) {
      if (photoItem['type'] == 'local') {
        await _photoService.saveLocalPhotoToServer(photoItem['photo'], null);
        uploadedCount++;
      }
    }
    Navigator.pop(context);
    _showCustomMessage("$uploadedCount фото загружено на сервер");
    await _fetchPhotosAndGenerateTags();
    setState(() {
      _selectedPhotos.clear();
      widget.multiSelectMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_tagsLoading) {
          bool shouldCancel = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: const Color(0xFFF5EEDC),
                  title: const Text("Подтверждение",
                      style: TextStyle(color: Color(0xFF183B4E))),
                  content: const Text(
                      "Процесс генерации тегов ещё идёт. Вы действительно хотите выйти и отменить процесс?",
                      style: TextStyle(color: Color(0xFF183B4E))),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text("Нет",
                          style: TextStyle(color: Color(0xFF27548A))),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text("Да",
                          style: TextStyle(color: Color(0xFFDDA853))),
                    ),
                  ],
                ),
              ) ??
              false;
          if (shouldCancel) {
            setState(() {
              _cancelTagGeneration = true;
              _tagsLoading = false;
            });
            return true;
          } else {
            return false;
          }
        }
        return true;
      },
      child: Stack(
        children: [
          Scaffold(
            extendBodyBehindAppBar: true,
            body: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFF5EEDC), Color(0xFF183B4E)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SafeArea(
                child: CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      pinned: true,
                      backgroundColor: const Color(0xFF27548A),
                      elevation: 2,
                      title: Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          controller: _searchController,
                          maxLines: 1,
                          textAlignVertical: TextAlignVertical.center,
                          style: const TextStyle(color: Color(0xFF183B4E)),
                          decoration: InputDecoration(
                            hintText: 'Введите теги...',
                            hintStyle: const TextStyle(
                                fontSize: 10.5, color: Color(0xFF27548A)),
                            prefixIcon: const Icon(
                              Icons.search,
                              size: 22,
                              color: Color(0xFFDDA853),
                            ),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 30, 
                              minHeight: 20,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 8, horizontal: 12),
                          ),
                        ),
                      ),
                      bottom: PreferredSize(
                        preferredSize:
                            Size.fromHeight(_suggestedTags.isNotEmpty ? 50 : 0),
                        child: _suggestedTags.isNotEmpty
                            ? Container(
                                height: 50,
                                alignment: Alignment.centerLeft,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: _suggestedTags.map((tag) {
                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(right: 8.0),
                                      child: ActionChip(
                                        backgroundColor:
                                            const Color(0xFFDDA853),
                                        label: Text(tag,
                                            style: const TextStyle(
                                                color: Color(0xFF183B4E))),
                                        onPressed: () {
                                          _searchController.text = tag;
                                          _searchController.selection =
                                              TextSelection.collapsed(
                                                  offset: tag.length);
                                        },
                                      ),
                                    );
                                  }).toList(),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      actions: [
                        IconButton(
                          icon: Icon(
                            _hideLocalPhotos
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: const Color(0xFFDDA853),
                          ),
                          tooltip: _hideLocalPhotos
                              ? 'Показать все фотографии'
                              : 'Показать только серверные фотографии',
                          onPressed: () {
                            setState(() {
                              _hideLocalPhotos = !_hideLocalPhotos;
                            });
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.date_range,
                              color: Color(0xFFDDA853)),
                          tooltip: "Фильтр по дате",
                          onPressed: _chooseDateRangeInputMethod,
                        ),
                        IconButton(
                          icon: const Icon(Icons.more_horiz,
                              color: Color(0xFFDDA853)),
                          tooltip: "Действия",
                          onPressed: _showActionsBottomSheet,
                        ),
                      ],
                    ),
                    if (_startDate != null && _endDate != null)
                      SliverToBoxAdapter(child: _buildDateFilterWidget()),
                    if (_tagsLoading)
                      SliverFillRemaining(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              "Создание тегов...",
                              style:
                                  TextStyle(fontSize: 16, color: Colors.white),
                            ),
                            const SizedBox(height: 20),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20.0),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: _progress,
                                  minHeight: 8,
                                  backgroundColor: Colors.white54,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                          Color(0xFFDDA853)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20.0),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.8),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.info_outline,
                                        color: Color(0xFFDDA853)),
                                    SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        "Чтобы поиск по тексту на фотографии работал, сохраните её на сервере.",
                                        style: TextStyle(
                                            fontSize: 14,
                                            color: Color(0xFF183B4E)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ..._buildGallerySlivers(),
                  ],
                ),
              ),
            ),
          ),
          if (_loading) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildDateFilterWidget() {
    if (_startDate == null || _endDate == null) return const SizedBox.shrink();
    String formattedStart =
        DateFormat('dd MMM yyyy', 'ru_RU').format(_startDate!);
    String formattedEnd = DateFormat('dd MMM yyyy', 'ru_RU').format(_endDate!);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            const Icon(Icons.date_range, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Фильтр: с $formattedStart по $formattedEnd",
                style: const TextStyle(color: Colors.white),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.white),
              onPressed: () {
                setState(() {
                  _startDate = null;
                  _endDate = null;
                });
              },
            )
          ],
        ),
      ),
    );
  }

  Future<void> _chooseDateRangeInputMethod() async {
    final method = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.calendar_today, color: Color(0xFFDDA853)),
              title: const Text("Выбрать через календарь",
                  style: TextStyle(color: Color(0xFF183B4E))),
              onTap: () => Navigator.pop(context, "calendar"),
            ),
            ListTile(
              leading: const Icon(Icons.keyboard, color: Color(0xFFDDA853)),
              title: const Text("Ввести вручную",
                  style: TextStyle(color: Color(0xFF183B4E))),
              onTap: () => Navigator.pop(context, "manual"),
            ),
          ],
        );
      },
    );
    if (method == "calendar") {
    final picked = await showDateRangePicker(
  context: context,
  locale: const Locale('ru'),
  firstDate: DateTime(2000),
  lastDate: DateTime.now(),
  helpText: 'Выберите диапазон дат',
  cancelText: 'Отмена',
  confirmText: 'Готово',
  builder: (context, child) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.light(
          primary: kAppBarColor,    
          onPrimary: Colors.white,   
          onSurface: kPrimaryColor,  
          secondary: kAccentColor,   
        ),
        datePickerTheme: DatePickerThemeData(
          rangeSelectionBackgroundColor: kAccentColor.withOpacity(0.5),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: kAccentColor),
        ),
      ),
      child: child!,
    );
  },
);

      if (picked != null) {
        setState(() {
          _startDate = picked.start;
          _endDate = picked.end;
        });
      }
    } else if (method == "manual") {
      await _selectDateRangeCustom(context);
    }
  }

  Future<void> _selectDateRangeCustom(BuildContext context) async {
    final maskFormatter = MaskTextInputFormatter(
      mask: '##/##/####',
      filter: {"#": RegExp(r'[0-9]')},
    );
    DateTime? startDate;
    DateTime? endDate;
    final startController = TextEditingController();
    final endController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFFF5EEDC),
          title: const Text('Введите диапазон дат',
              style: TextStyle(color: Color(0xFF183B4E))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: startController,
                keyboardType: TextInputType.datetime,
                inputFormatters: [maskFormatter],
                decoration: const InputDecoration(
                  hintText: 'Начальная дата (дд/мм/гггг)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: endController,
                keyboardType: TextInputType.datetime,
                inputFormatters: [maskFormatter],
                decoration: const InputDecoration(
                  hintText: 'Конечная дата (дд/мм/гггг)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена',
                  style: TextStyle(color: Color(0xFF27548A))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDDA853)),
              onPressed: () {
                try {
                  startDate = DateFormat('dd/MM/yyyy')
                      .parseStrict(startController.text);
                  endDate =
                      DateFormat('dd/MM/yyyy').parseStrict(endController.text);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Неверный формат даты')),
                  );
                  return;
                }
                Navigator.pop(context);
              },
              child: const Text('Готово',
                  style: TextStyle(color: Color(0xFF183B4E))),
            ),
          ],
        );
      },
    );
    if (startDate != null && endDate != null) {
      setState(() {
        _startDate = startDate;
        _endDate = endDate;
      });
    }
  }
}
