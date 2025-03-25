import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_cluster_manager/google_maps_cluster_manager.dart';

class PhotoItem with ClusterItem {
  final String id;
  final String url;
  final List<String> tags;
  final String creationDate;
  final double lat;
  final double lng;
  final String ocrText;
  final Map<String, dynamic>? owner;     
  final Map<String, dynamic>? sharedWith;   

  PhotoItem({
    required this.id,
    required this.lat,
    required this.lng,
    required this.url,
    required this.tags,
    required this.creationDate,
    this.ocrText = "",
    this.owner,       
    this.sharedWith,   
  });

  @override
  LatLng get location => LatLng(lat, lng);
}
