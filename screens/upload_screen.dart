import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:trip/services/photo_service.dart';

const Color kBackgroundColor = Color(0xFFF5EEDC);
const Color kPrimaryColor = Color(0xFF27548A); 
const Color kAppBarColor = Color(0xFF183B4E);
const Color kAccentColor = Color(0xFFDDA853); 

class UploadScreen extends StatefulWidget {
  @override
  _UploadScreenState createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen>
    with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;
  final PhotoService _photoService = PhotoService();
  late AnimationController _loadingController;

  @override
  void initState() {
    super.initState();
    _loadingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _loadingController.dispose();
    super.dispose();
  }

  Future<void> _selectImage() async {
    final image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  Future<void> _uploadImage() async {
    if (_selectedImage == null) {
      _showCustomMessage('Сначала выберите фото для загрузки.',
          icon: Icons.error_outline, backgroundColor: Colors.redAccent);
      return;
    }
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        _showCustomMessage('Пользователь не авторизован.',
            icon: Icons.error_outline, backgroundColor: Colors.redAccent);
        return;
      }
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            buildCustomLoadingOverlay('Загрузка фото на сервер...'),
      );
      bool uploaded =
          await _photoService.uploadImage(_selectedImage, currentUser);
      Navigator.pop(context); 
      if (!uploaded) {
        _showCustomMessage('Фото уже сохранено на сервере.',
            icon: Icons.info_outline, backgroundColor: Colors.orange);
      } else {
        _showCustomMessage('Фото успешно загружено!');
        setState(() {
          _selectedImage = null;
        });
      }
    } catch (e) {
      Navigator.pop(context);
      print("Ошибка при загрузке изображения: $e");
      _showCustomMessage('Ошибка при загрузке фото.',
          icon: Icons.error_outline, backgroundColor: Colors.redAccent);
    }
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
                      colors: [kPrimaryColor, kAccentColor],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
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

  Widget _buildCustomAppBar() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: kAppBarColor.withOpacity(0.9),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: kBackgroundColor),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          const Text(
            'Загрузка фотографии',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: kBackgroundColor,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              kBackgroundColor,
              kPrimaryColor.withOpacity(0.1),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildCustomAppBar(),
              Expanded(
                child: Center(
                  child: Card(
                    color: kBackgroundColor.withOpacity(0.95),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    elevation: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Загрузка фото',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: kPrimaryColor,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_selectedImage != null)
                            Column(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(
                                    _selectedImage!,
                                    height: 200,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                            ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 50),
                              backgroundColor: kAccentColor,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _selectImage,
                            child: const Text('Выбрать фото', style: TextStyle(color: kPrimaryColor),),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 50),
                              backgroundColor: kPrimaryColor,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _uploadImage,
                            child: const Text('Загрузить фото', style: TextStyle(color: kBackgroundColor),),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
