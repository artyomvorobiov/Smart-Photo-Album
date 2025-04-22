import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:trip/screens/map_screen.dart';
import 'package:trip/screens/memory_screen.dart';
import 'package:trip/screens/profile.dart';
import 'gallery_screen.dart';
import 'upload_screen.dart';
import 'package:trip/screens/folders_screen.dart';

const Color kBackgroundColor = Color(0xFFF5EEDC); 
const Color kPrimaryColor = Color(0xFF27548A); 
const Color kAppBarColor = Color(0xFF183B4E); 
const Color kAccentColor = Color(0xFFDDA853);

class HomeScreen extends StatefulWidget {
  HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildMenuButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return _AnimatedMenuButton(
      icon: icon,
      label: label,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color.lerp(kAppBarColor, kAccentColor, _controller.value)!
                          .withOpacity(0.9),
                      Color.lerp(kBackgroundColor, kBackgroundColor,
                              _controller.value)!
                          .withOpacity(0.9),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              );
            },
          ),
          CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                pinned: true,
                expandedHeight: 200,
                flexibleSpace: FlexibleSpaceBar(
                  title: const Text(
                    'Умный фотоальбом',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  background: Container(),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.account_circle, size: 28),
                    color: Colors.white,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ProfileScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 30),
              ),
              SliverPadding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, 
                    mainAxisSpacing: 30, 
                    crossAxisSpacing: 30, 
                    childAspectRatio:
                        0.8, 
                  ),
                  delegate: SliverChildListDelegate(
                    [
                      _buildMenuButton(
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
                        icon: Icons.star,
                        label: 'Избранное',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                GalleryScreen(source: "favorites"),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnimatedMenuButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AnimatedMenuButton({
    Key? key,
    required this.icon,
    required this.label,
    required this.onTap,
  }) : super(key: key);

  @override
  __AnimatedMenuButtonState createState() => __AnimatedMenuButtonState();
}

class __AnimatedMenuButtonState extends State<_AnimatedMenuButton>
    with SingleTickerProviderStateMixin {
  double _scale = 1.0;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0,
    );
    _animController.addListener(() {
      setState(() {
        _scale = _animController.value;
      });
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: _scale,
      child: GestureDetector(
        onTapDown: (_) => _animController.reverse(),
        onTapUp: (_) {
          _animController.forward();
          widget.onTap();
        },
        onTapCancel: () => _animController.forward(),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
            color: Colors.white.withOpacity(0.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(widget.icon, size: 60, color: Colors.white),
                    const SizedBox(height: 8),
                    Flexible(
                      child: Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              offset: Offset(1, 1),
                              blurRadius: 4,
                              color: Colors.black45,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
