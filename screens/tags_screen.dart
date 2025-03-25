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
  Set<AssetEntity> _selectedPhotos = {};
  bool _multiSelectMode = false;

  @override
  void initState() {
    super.initState();
    _photoTags = widget.photoTags;
    _filteredTags = widget.photoTags!.keys.toList();
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
        _selectedPhotos.clear();
      }
    });
  }

  void _deleteSelectedPhotos() async {
    if (_selectedPhotos.isEmpty) return;

    final toDeleteCount = _selectedPhotos.length;

    for (var photo in _selectedPhotos) {
      await PhotoManager.editor.deleteWithIds([photo.id]);
    }

    setState(() {
      _selectedPhotos.clear();
      _multiSelectMode = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$toDeleteCount фото удалено')),
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
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Card(
                  color: Colors.white.withOpacity(0.85),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _filterTags,
                    decoration: InputDecoration(
                      labelText: 'Поиск тегов',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Card(
                  color: Colors.white.withOpacity(0.7),
                  margin: const EdgeInsets.all(8.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.builder(
                    itemCount: _filteredTags.length,
                    itemBuilder: (context, index) {
                      final tag = _filteredTags[index];
                      return ListTile(
                        title: Text(
                          tag,
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        trailing: Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => GalleryScreen(selectedTags: [tag], localPhotoTags: widget.localPhotoTags, source: "tags"),
  ),
);
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomAppBar() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const Text(
            'Теги',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Row(
            children: [
              if (_multiSelectMode)
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.white),
                  onPressed: _deleteSelectedPhotos,
                ),
              IconButton(
                icon: const Icon(Icons.select_all, color: Colors.white),
                onPressed: _toggleMultiSelect,
              ),
            ],
          )
        ],
      ),
    );
  }
}
