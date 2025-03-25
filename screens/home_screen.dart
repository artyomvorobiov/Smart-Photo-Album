import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:trip/screens/map_screen.dart';
import 'package:trip/screens/memory_screen.dart';
import 'package:trip/screens/profile.dart';
import 'gallery_screen.dart';
import 'upload_screen.dart';
import 'package:trip/screens/folders_screen.dart';

class HomeScreen extends StatelessWidget {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Умный фотоальбом',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle, size: 28),
            color: Colors.white,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ProfileScreen()),
              );
            },
          ),

        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF89CFFD),
              Color(0xFFB084CC),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: kToolbarHeight + 20, left: 16, right: 16, bottom: 20),
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 20,
              mainAxisSpacing: 20,
              children: [
                _buildMenuButton(
                  context,
                  icon: Icons.photo_library,
                  label: 'Галерея',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => GalleryScreen(source: "home"),
                    ),
                  ),
                ),
                _buildMenuButton(
                  context,
                  icon: Icons.folder,
                  label: 'Папки',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FolderScreen(),
                    ),
                  ),
                ),
                _buildMenuButton(
                  context,
                  icon: Icons.cloud_upload,
                  label: 'Загрузить\nфотографию',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UploadScreen(),
                    ),
                  ),
                ),
                _buildMenuButton(
                  context,
                  icon: Icons.photo_album,
                  label: 'Фотоальбомы',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PhotoAlbumsScreen(),
                    ),
                  ),
                ),
                _buildMenuButton(
                  context,
                  icon: Icons.map,
                  label: 'Фото на карте',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MapScreen(),
                    ),
                  ),
                ),
                _buildMenuButton(
                  context,
                  icon: Icons.star,
                  label: 'Избранное',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => GalleryScreen(source: "favorites"),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withOpacity(0.8),
      borderRadius: BorderRadius.circular(16),
      elevation: 4,
      shadowColor: Colors.black26,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 50, color: Colors.blueGrey[700]),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.blueGrey[800],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
