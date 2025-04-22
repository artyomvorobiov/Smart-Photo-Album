import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:trip/screens/gallery_screen.dart';

// ignore: must_be_immutable
class TagsScreen extends StatefulWidget {
  final Map<String, List<AssetEntity>>? photoTags;
  Map<AssetEntity, List<String>> localPhotoTags;

  TagsScreen({required this.photoTags, required this.localPhotoTags});

  @override
  _TagsScreenState createState() => _TagsScreenState();
}

class _TagsScreenState extends State<TagsScreen> {
  final _searchController = TextEditingController();
  List<String> _filteredTags = [];
  late Map<String, List<AssetEntity>>? _photoTags;
  Set<String> _selectedTags = {};
  Set<AssetEntity> _selectedPhotos = {};
  bool _multiSelectMode = false;
  final Color kBackgroundColor = const Color(0xFFF5EEDC); 
  final Color kPrimaryColor = const Color(0xFF27548A); 
  final Color kAppBarColor = const Color(0xFF183B4E); 
  final Color kAccentColor = const Color(0xFFDDA853); 

  @override
  void initState() {
    super.initState();
    _photoTags = widget.photoTags;
    _filteredTags = widget.photoTags!.keys
        .where((tag) => RegExp(r'[А-Яа-я]').hasMatch(tag))
        .toList();
  }

  void _filterTags(String query) {
    final filtered = widget.photoTags!.keys
        .where((tag) => tag.toLowerCase().contains(query.toLowerCase()))
        .toList();
    setState(() {
      _filteredTags = filtered;
    });
  }
  void _toggleMultiSelect() {
    setState(() {
      _multiSelectMode = !_multiSelectMode;
      if (!_multiSelectMode) {
        _selectedTags.clear();
        _selectedPhotos.clear();
      }
    });
  }

  void _toggleTagSelection(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
        _selectedPhotos.removeAll(widget.photoTags![tag] ?? []);
      } else {
        _selectedTags.add(tag);
        _selectedPhotos.addAll(widget.photoTags![tag] ?? []);
      }
    });
  }

  Future<void> _deleteSelectedPhotos() async {
    if (_selectedPhotos.isEmpty) return;

    final toDeleteCount = _selectedPhotos.length;
    for (var photo in _selectedPhotos) {
      await PhotoManager.editor.deleteWithIds([photo.id]);
    }
    setState(() {
      widget.photoTags?.forEach((tag, photos) {
        photos.removeWhere((photo) => _selectedPhotos.contains(photo));
      });
      _selectedPhotos.clear();
      _selectedTags.clear();
      _multiSelectMode = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$toDeleteCount фото удалено')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: _buildCustomAppBar(),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: kPrimaryColor.withOpacity(0.5)),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _filterTags,
                  decoration: InputDecoration(
                    hintText: 'Поиск тегов',
                    prefixIcon: Icon(Icons.search, color: kPrimaryColor),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Card(
                  color: Colors.white.withOpacity(0.9),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _filteredTags.isEmpty
                      ? Center(
                          child: Text(
                            'Ничего не найдено',
                            style: TextStyle(
                              fontSize: 18,
                              color: kAppBarColor,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredTags.length,
                          itemBuilder: (context, index) {
                            final tag = _filteredTags[index];
                            bool isSelected = _selectedTags.contains(tag);
                            return Card(
                              color: isSelected
                                  ? kPrimaryColor.withOpacity(0.2)
                                  : Colors.white,
                              elevation: 1,
                              margin: const EdgeInsets.symmetric(
                                  vertical: 4, horizontal: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: isSelected
                                    ? BorderSide(color: kAccentColor, width: 2)
                                    : BorderSide(color: Colors.transparent),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                title: Text(
                                  tag,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: kAppBarColor,
                                  ),
                                ),
                                trailing: _multiSelectMode
                                    ? Icon(
                                        isSelected
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                        color: isSelected
                                            ? kAccentColor
                                            : kAppBarColor,
                                      )
                                    : Icon(Icons.arrow_forward_ios,
                                        size: 16, color: kAppBarColor),
                                onTap: () {
  final tagPhotos = widget.photoTags?[tag] ?? [];
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => GalleryScreen(
        source: "tags",
        preFilteredPhotos: tagPhotos, 
        localPhotoTags: widget.localPhotoTags,
        selectedTags: [tag],
      ),
    ),
  );
},

                              ),
                            );
                          },
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildCustomAppBar() {
    return AppBar(
      backgroundColor: kPrimaryColor,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: kAccentColor),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'Теги',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: kAccentColor,
        ),
      ),
    );
  }
}
