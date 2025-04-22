import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:trip/services/photo_service.dart';

const Color kBackgroundColor = Color(0xFFF5EEDC); 
const Color kPrimaryColor = Color(0xFF27548A); 
const Color kAppBarColor = Color(0xFF183B4E); 
const Color kAccentColor = Color(0xFFDDA853);

class PhotoEditScreen extends StatefulWidget {
  final AssetEntity? localPhoto;
  final Map<String, dynamic>? serverPhoto;

  const PhotoEditScreen({Key? key, this.localPhoto, this.serverPhoto})
      : super(key: key);

  @override
  _PhotoEditScreenState createState() => _PhotoEditScreenState();
}

class _PhotoEditScreenState extends State<PhotoEditScreen>
    with SingleTickerProviderStateMixin {
  Uint8List? originalImageBytes;
  Uint8List? editedImageBytes;
  bool isLoading = true;

  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this, 
      duration: const Duration(seconds: 2),
    )..repeat();
    _loadImage();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _showMessage(String message,
      {IconData icon = Icons.check_circle_outline, Color backgroundColor = Colors.green}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
          ],
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _loadImage() async {
    try {
      if (widget.localPhoto != null) {
        File? file = await widget.localPhoto!.file;
        if (file != null) {
          originalImageBytes = await file.readAsBytes();
        }
      } else if (widget.serverPhoto != null) {
        String url = widget.serverPhoto!['url'] ?? '';
        if (url.isNotEmpty) {
          final response = await http.get(Uri.parse(url));
          if (response.statusCode == 200) {
            originalImageBytes = response.bodyBytes;
          }
        }
      }
      if (originalImageBytes != null) {
        editedImageBytes = originalImageBytes;
      }
    } catch (e) {
      debugPrint("Ошибка загрузки изображения: $e");
    }
    setState(() {
      isLoading = false;
    });
  }

  Future<void> _cropImage() async {
    if (editedImageBytes == null) return;
    final tempDir = await getTemporaryDirectory();
    final tempFile = File(p.join(tempDir.path, "temp_image.png"));
    await tempFile.writeAsBytes(editedImageBytes!);

    CroppedFile? croppedFile = await ImageCropper().cropImage(
      sourcePath: tempFile.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Обрезка изображения',
          toolbarColor: kAppBarColor,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
          activeControlsWidgetColor: kAccentColor,
        ),
        IOSUiSettings(
          title: 'Обрезка изображения',
        ),
      ],
    );

    if (croppedFile != null) {
      editedImageBytes = await File(croppedFile.path).readAsBytes();
      setState(() {});
    }
  }

  void _rotateImage() {
    if (editedImageBytes == null) return;
    img.Image? image = img.decodeImage(editedImageBytes!);
    if (image == null) return;
    img.Image rotated = img.copyRotate(image, angle: 90);
    editedImageBytes = Uint8List.fromList(img.encodePng(rotated));
    setState(() {});
  }

  void _resetImage() {
    if (originalImageBytes != null) {
      editedImageBytes = originalImageBytes;
      setState(() {});
    }
  }

  Future<void> _saveEditedImage() async {
    if (editedImageBytes == null) return;
    final tempDir = await getTemporaryDirectory();
    final fileName = "edited_${DateTime.now().millisecondsSinceEpoch}.png";
    final filePath = p.join(tempDir.path, fileName);
    final editedFile = File(filePath);
    await editedFile.writeAsBytes(editedImageBytes!);

    try {
      if (widget.localPhoto != null) {
        AssetEntity? savedAsset = await PhotoManager.editor.saveImage(
          editedImageBytes!,
          title: fileName,
          filename: fileName,
        );
        _showMessage("Фото успешно сохранено в галерее");
        Navigator.pop(context, savedAsset);
      } else if (widget.serverPhoto != null) {
        PhotoService photoService = PhotoService();
        String downloadUrl = await photoService.uploadEditedFileToServer(editedFile, fileName);
        Map<String, dynamic> newServerPhoto = Map<String, dynamic>.from(widget.serverPhoto!);
        newServerPhoto['id'] = fileName;
        newServerPhoto['url'] = downloadUrl;
        newServerPhoto['timestamp'] = DateTime.now().toIso8601String();
        final currentUser = FirebaseAuth.instance.currentUser;
        newServerPhoto['owner'] = {
          'uid': currentUser?.uid,
          'email': currentUser?.email ?? "Не указан",
          'displayName': currentUser?.displayName ?? "Аноним",
          'photoURL': currentUser?.photoURL ?? "",
        };
        newServerPhoto['sharedWith'] = {};
        await FirebaseFirestore.instance.collection('photos').doc(fileName).set(newServerPhoto);
        _showMessage("Отредактированное фото успешно сохранено на сервере");
        Navigator.pop(context, newServerPhoto);
      } else {
        Navigator.pop(context, editedFile);
      }
    } catch (e) {
      _showMessage("Ошибка при сохранении: $e", icon: Icons.error_outline, backgroundColor: Colors.redAccent);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        title: const Text(
          "Редактирование фото",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: kAppBarColor,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: "Сохранить",
            onPressed: () async {
              await _saveEditedImage();
            },
          )
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [kBackgroundColor, const Color(0xFFE5D8C8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: isLoading
            ? Center(child: CircularProgressIndicator(color: kPrimaryColor))
            : Column(
                children: [
                  Expanded(
                    child: editedImageBytes != null
                        ? Image.memory(
                            editedImageBytes!,
                            fit: BoxFit.contain,
                          )
                        : Center(child: Text("Не удалось загрузить изображение", style: TextStyle(color: kPrimaryColor))),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: kPrimaryColor,
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: kPrimaryColor.withOpacity(0.5)),
                              ),
                              textStyle: const TextStyle(fontSize: 12),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: _cropImage,
                            icon: const Icon(Icons.crop, size: 18),
                            label: const Text("Обрезать"),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: kPrimaryColor,
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: kPrimaryColor.withOpacity(0.5)),
                              ),
                              textStyle: const TextStyle(fontSize: 12),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: _rotateImage,
                            icon: const Icon(Icons.rotate_right, size: 18),
                            label: const Text("Повернуть"),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: kPrimaryColor,
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: kPrimaryColor.withOpacity(0.5)),
                              ),
                              textStyle: const TextStyle(fontSize: 12),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: _resetImage,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text("Сбросить"),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
      ),
    );
  }
}
 
