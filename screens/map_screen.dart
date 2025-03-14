import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' as intl;
import 'package:trip/models/cluster.dart';
import 'package:google_maps_cluster_manager/google_maps_cluster_manager.dart' as gmc;
import 'package:trip/screens/photo_view_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({Key? key}) : super(key: key);

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late GoogleMapController _mapController;
  String _searchQuery = '';
  bool _isSearching = false;
  gmc.ClusterManager<PhotoItem>? _clusterManager;
  List<PhotoItem> _allPhotoItems = [];
  final LatLng _initialPosition = const LatLng(55.7558, 37.6173);
  final Set<Marker> _markers = {};
  double _currentZoom = 10.0;
  final Map<String, BitmapDescriptor> _photoIconCache = {};
  final Map<int, BitmapDescriptor> _clusterIconCache = {};

  @override
  void initState() {
    super.initState();
    _loadPhotoItemsAndInitClusterManager();
  }

  Future<void> _loadPhotoItemsAndInitClusterManager() async {
  try {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      debugPrint("Пользователь не авторизован");
      return;
    }

    final snapshot =
        await FirebaseFirestore.instance.collection('photos').get();
    final List<PhotoItem> items = [];
    for (var doc in snapshot.docs) {
      final data = doc.data();
      final lat = _toDouble(data['latitude']);
      final lng = _toDouble(data['longitude']);
      if (lat == 0 && lng == 0) continue;
      final owner = data['owner'] != null ? data['owner'] as Map<String, dynamic> : null;
      final sharedWith = data['sharedWith'] != null ? data['sharedWith'] as Map<String, dynamic> : null;
      bool isOwner = owner != null && owner['uid'] == currentUser.uid;
      bool isShared = sharedWith != null && sharedWith.containsKey(currentUser.uid);
      if (!isOwner && !isShared) continue;

      items.add(
        PhotoItem(
          id: doc.id,
          lat: lat,
          lng: lng,
          url: data['url'] ?? '',
          tags: (data['tags'] ?? []).cast<String>(),
          creationDate: data['creation_date'] ?? 'Неизвестно',
          ocrText: data['ocrText'] ?? '',
          owner: owner,
          sharedWith: sharedWith,
        ),
      );
    }

    debugPrint("Loaded ${items.length} photo items");
    _allPhotoItems = items;

    setState(() {
      _clusterManager = gmc.ClusterManager<PhotoItem>(
        items,
        _updateMarkers,
        markerBuilder: _markerBuilder,
      );
    });
  } catch (e, stackTrace) {
    debugPrint("Error initializing cluster manager: $e");
    debugPrint(stackTrace.toString());
  }
}
  double _toDouble(dynamic val) {
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }
  void _updateMarkers(Set<Marker> markers) {
    setState(() {
      _markers
        ..clear()
        ..addAll(markers);
    });
  }

  Future<Marker> _markerBuilder(dynamic cluster) async {
    try {
      final typedCluster = cluster as gmc.Cluster<PhotoItem>;
      if (typedCluster.isMultiple) {
        final allSameLocation = typedCluster.items
            .map((e) => '${e.lat},${e.lng}')
            .toSet()
            .length == 1;

        if (allSameLocation) {
          final icon = await _getClusterBitmap(typedCluster.count);
          return Marker(
            markerId: MarkerId("same_loc_${typedCluster.getId()}"),
            position: typedCluster.location,
            icon: icon,
            onTap: () {
              _showMultiplePhotos(typedCluster.items.toList());
            },
          );
        } else {
          final bitmapDescriptor = await _getClusterBitmap(typedCluster.count);
          return Marker(
            markerId: MarkerId("cl_${typedCluster.getId()}"),
            position: typedCluster.location,
            icon: bitmapDescriptor,
            onTap: () {
              _mapController.animateCamera(
                  CameraUpdate.zoomTo(_currentZoom + 2));
            },
          );
        }
      } else {
        final PhotoItem item = typedCluster.items.first;
        final bitmapDescriptor = await _getPhotoBitmap(item.url);
        return Marker(
          markerId: MarkerId(item.id),
          position: typedCluster.location,
          icon: bitmapDescriptor,
          onTap: () => _showSinglePhotoDetails(item),
        );
      }
    } catch (e) {
      debugPrint("Error creating marker: $e");
      return Marker(
        markerId: const MarkerId("error"),
        position: const LatLng(0, 0),
        icon: BitmapDescriptor.defaultMarker,
      );
    }
  }

  void _showMultiplePhotos(List<PhotoItem> items) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final screenHeight = MediaQuery.of(context).size.height;
        return Container(
          height: screenHeight * 0.7,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Выберите фотографию",
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.builder(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final photo = items[index];
                    return GestureDetector(
                     onTap: () {
  Navigator.pop(context);
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => PhotoViewScreen.multiple(
        photoList: items.map((photo) => {
          'url': photo.url,
          'tags': photo.tags,
          'id': photo.id,
          'creation_date': photo.creationDate,
          'ocrText': photo.ocrText,
          'owner': photo.owner,
          'sharedWith': photo.sharedWith,
        }).toList(),
        initialIndex: index,
      ),
    ),
  );
},

                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          photo.url,
                          fit: BoxFit.cover,
                          errorBuilder:
                              (context, error, stackTrace) => Container(
                            color: Colors.grey[300],
                            child: Icon(Icons.broken_image,
                                color: Colors.grey[700], size: 40),
                          ),
                          loadingBuilder:
                              (context, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              color: Colors.grey[300],
                              child: const Center(
                                  child: CircularProgressIndicator()),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text("Закрыть"),
              ),
            ],
          ),
        );
      },
    );
  }
  Future<BitmapDescriptor> _getClusterBitmap(int count) async {
    if (_clusterIconCache.containsKey(count)) {
      return _clusterIconCache[count]!;
    }
    const int size = 120;
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    final Paint paint = Paint()..color = Colors.deepPurpleAccent;
    final double radius = size / 2;
    canvas.drawCircle(Offset(radius, radius), radius, paint);

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );
    textPainter.text = TextSpan(
      text: count.toString(),
      style: const TextStyle(
        fontSize: 38,
        color: Colors.white,
        fontWeight: FontWeight.bold,
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        radius - textPainter.width / 2,
        radius - textPainter.height / 2,
      ),
    );

    final picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(size, size);
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    final Uint8List pngBytes = byteData!.buffer.asUint8List();

    final descriptor = BitmapDescriptor.fromBytes(pngBytes);
    _clusterIconCache[count] = descriptor;
    return descriptor;
  }
  Future<BitmapDescriptor> _getPhotoBitmap(String imageUrl,
      {int width = 120, int height = 120}) async {
    if (imageUrl.isEmpty) {
      return BitmapDescriptor.defaultMarker;
    }
    if (_photoIconCache.containsKey(imageUrl)) {
      return _photoIconCache[imageUrl]!;
    }
    try {
      final uri = Uri.parse(imageUrl);
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        return BitmapDescriptor.defaultMarker;
      }
      final bytes = response.bodyBytes;
      final ui.Codec markerImageCodec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: width,
        targetHeight: height,
      );
      final ui.FrameInfo frameInfo =
          await markerImageCodec.getNextFrame();
      final byteData = await frameInfo.image
          .toByteData(format: ui.ImageByteFormat.png);
      final resizedBytes = byteData!.buffer.asUint8List();
      final descriptor = BitmapDescriptor.fromBytes(resizedBytes);
      _photoIconCache[imageUrl] = descriptor;
      return descriptor;
    } catch (e) {
      debugPrint("Ошибка загрузки картинки для маркера: $e");
      return BitmapDescriptor.defaultMarker;
    }
  }

  void _showSinglePhotoDetails(PhotoItem photo) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final screenHeight = MediaQuery.of(context).size.height;
        return Container(
          height: screenHeight * 0.7,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PhotoViewScreen.server(
                        serverPhoto: {
  'url': photo.url,
  'tags': photo.tags,
  'id': photo.id,
  'creation_date': photo.creationDate,
  'ocrText': photo.ocrText,
  'owner': photo.owner,        
  'sharedWith': photo.sharedWith,  
},
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 300,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                    ),
                    child: Image.network(
                      photo.url,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.grey[300],
                        child: Icon(
                          Icons.broken_image,
                          color: Colors.grey[700],
                          size: 50,
                        ),
                      ),
                      loadingBuilder:
                          (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Center(child: CircularProgressIndicator());
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "Фотография",
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Builder(builder: (context) {
                String formattedDate = photo.creationDate;
                try {
                  final dt = DateTime.parse(photo.creationDate);
                  formattedDate = intl.DateFormat('dd MMMM yyyy', 'ru_RU')
                      .format(dt);
                } catch (e) {}
                return Text(
                  "Дата создания: $formattedDate",
                  style: TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                );
              }),
              const Spacer(),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text("Закрыть"),
              ),
            ],
          ),
        );
      },
    );
  }
  void _updateSearch(String query) {
    setState(() {
      _searchQuery = query;
      final lowerQuery = query.toLowerCase();
      List<PhotoItem> filtered = _allPhotoItems.where((item) {
        bool tagMatch = item.tags
            .any((tag) => tag.toLowerCase().contains(lowerQuery));
        bool textMatch =
            item.ocrText.toLowerCase().contains(lowerQuery);
        return tagMatch || textMatch;
      }).toList();
      _clusterManager?.setItems(filtered);
      _clusterManager?.updateMap();
    });
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
              Expanded(
                child: Stack(
                  children: [
                    if (_clusterManager == null)
                      const Center(child: CircularProgressIndicator()),
                    if (_clusterManager != null)
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: _initialPosition,
                          zoom: _currentZoom,
                        ),
                        markers: _markers,
                        onMapCreated: (controller) {
                          _mapController = controller;
                          _clusterManager?.setMapId(controller.mapId);
                        },
                        onCameraMove: (position) {
                          _currentZoom = position.zoom;
                          _clusterManager?.onCameraMove(position);
                        },
                        onCameraIdle: () {
                          _clusterManager?.updateMap();
                        },
                        myLocationEnabled: true,
                        myLocationButtonEnabled: true,
                        zoomControlsEnabled: true,
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
        if (_isSearching)
          Expanded(
            child: TextField(
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: const InputDecoration(
                hintText: 'Поиск по тегам и тексту...',
                hintStyle: TextStyle(color: Colors.white70),
                border: InputBorder.none,
              ),
              onChanged: _updateSearch,
            ),
          )
        else
          Expanded(
            child: Text(
              "Фотографии на карте",
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        IconButton(
          icon: Icon(_isSearching ? Icons.close : Icons.search, color: Colors.white),
          onPressed: () {
            setState(() {
              if (_isSearching) {
                _isSearching = false;
                _searchQuery = '';
                _clusterManager?.setItems(_allPhotoItems);
                _clusterManager?.updateMap();
              } else {
                _isSearching = true;
              }
            });
          },
        ),
      ],
    ),
  );
}

}
