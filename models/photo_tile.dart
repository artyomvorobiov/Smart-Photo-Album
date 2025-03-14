import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

class PhotoItemWidget extends StatefulWidget {
  final dynamic photoItem;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool? isFavoriteOverride; 

  const PhotoItemWidget({
    Key? key,
    required this.photoItem,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    this.isFavoriteOverride,
  }) : super(key: key);

  @override
  _PhotoItemWidgetState createState() => _PhotoItemWidgetState();
}

class _PhotoItemWidgetState extends State<PhotoItemWidget> {
  Future<Uint8List?>? _thumbnailFuture;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    if (widget.photoItem['type'] == 'local') {
      _thumbnailFuture = widget.photoItem['photo']
          .thumbnailDataWithSize(const ThumbnailSize(200, 200));
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isServerPhoto = false;
    bool isSharedPhoto = false;
    bool isFavorite = false;
    if (widget.photoItem['type'] == 'server') {
      final owner = widget.photoItem['photo']['owner'];
      if (owner != null && owner['uid'] != null) {
        if (owner['uid'] == _auth.currentUser?.uid) {
          isServerPhoto = true;
        } else {
          isSharedPhoto = true;
        }
      }
      if (widget.photoItem['photo'] != null &&
          widget.photoItem['photo']['favorites'] != null) {
        String currentUid = _auth.currentUser?.uid ?? "";
        isFavorite = (widget.photoItem['photo']['favorites'] as List<dynamic>)
            .contains(currentUid);
      }
    } else {
      if (widget.isFavoriteOverride != null) {
        isFavorite = widget.isFavoriteOverride!;
      }
    }

    Widget imageWidget;
    if (widget.photoItem['type'] == 'server') {
      imageWidget = Image.network(
        widget.photoItem['photo']['url'],
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    } else {
      imageWidget = FutureBuilder<Uint8List?>(
        future: _thumbnailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              snapshot.hasData) {
            return Image.memory(
              snapshot.data!,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            );
          } else if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else {
            return Container(color: Colors.grey[300]);
          }
        },
      );
    }

    return GestureDetector(
      onLongPress: widget.onLongPress,
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            Positioned.fill(child: imageWidget),
            if (widget.isSelected)
              const Positioned(
                top: 4,
                left: 4,
                child: Icon(Icons.check_circle, size: 20, color: Colors.green),
              ),
            if (isFavorite)
              const Positioned(
                top: 4,
                right: 4,
                child: Icon(Icons.star, size: 20, color: Colors.yellow),
              ),
            if (isServerPhoto)
              const Positioned(
                bottom: 4,
                left: 4,
                child: Icon(Icons.cloud, size: 20, color: Colors.blue),
              ),
            if (isSharedPhoto)
              const Positioned(
                bottom: 4,
                right: 4,
                child: Icon(Icons.share, size: 20, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }
}
