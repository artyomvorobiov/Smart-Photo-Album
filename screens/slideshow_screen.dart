import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SlideshowScreen extends StatefulWidget {
  final List<Map<String, dynamic>> photos;
  final double duration;
  final String name;
  final String theme;

  const SlideshowScreen({
    required this.photos,
    required this.duration,
    required this.name,
    required this.theme,
    Key? key,
  }) : super(key: key);

  @override
  _SlideshowScreenState createState() => _SlideshowScreenState();
}

class _SlideshowScreenState extends State<SlideshowScreen> {
  int _currentIndex = 0;
  late Timer _timer;
  bool _manualControl = false;
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    _startSlideshow();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _startSlideshow() {
    _timer = Timer.periodic(
      Duration(milliseconds: (widget.duration * 1000).toInt()),
      (timer) {
        if (!_manualControl) {
          setState(() {
            _currentIndex = (_currentIndex + 1) % widget.photos.length;
          });
        }
      },
    );
  }

  void _togglePlayPause() {
    setState(() {
      _manualControl = !_manualControl;
      if (!_manualControl) {
        _startSlideshow();
      } else {
        _timer.cancel();
      }
    });
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
      if (_isFullscreen) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    });
  }

  void _previousPhoto() {
    setState(() {
      _currentIndex = (_currentIndex - 1 + widget.photos.length) % widget.photos.length;
    });
  }

  void _nextPhoto() {
    setState(() {
      _currentIndex = (_currentIndex + 1) % widget.photos.length;
    });
  }

  Gradient _getBackgroundGradient() {
    switch (widget.theme.toLowerCase()) {
      case 'classic':
        return const LinearGradient(
          colors: [Color(0xFFB0C4DE), Color(0xFF708090)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'modern':
        return const LinearGradient(
          colors: [Color(0xFFFC5C7D), Color(0xFF6A82FB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'event':
        return const LinearGradient(
          colors: [Color(0xFFFFA07A), Color(0xFFFF4500)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'vintage':
        return const LinearGradient(
          colors: [Color(0xFFDEB887), Color(0xFF8B4513)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'bright':
        return const LinearGradient(
          colors: [Color(0xFFFFC107), Color(0xFFFF5722)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'night':
        return const LinearGradient(
          colors: [Color(0xFF000000), Color(0xFF434343)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'pastel':
        return const LinearGradient(
          colors: [Color(0xFFB2DFDB), Color(0xFFE0F7FA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      default:
        return const LinearGradient(
          colors: [Color(0xFF000428), Color(0xFF004e92)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPhoto = widget.photos[_currentIndex];
    Gradient backgroundGradient = _getBackgroundGradient();

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(gradient: backgroundGradient),
          ),
          GestureDetector(
            onTap: _toggleFullscreen,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(seconds: 1),
                transitionBuilder: (child, animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: Container(
                  key: ValueKey<int>(_currentIndex),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 4),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: Image.network(
                    currentPhoto['url'],
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
          if (!_isFullscreen) ...[
            _buildCustomAppBar(),
            _buildCustomControls(),
          ]
        ],
      ),
    );
  }

  Widget _buildCustomAppBar() {
    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      color: Colors.black.withOpacity(0.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Text(
            widget.name,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomControls() {
    return Positioned(
      bottom: 20,
      left: 20,
      right: 20,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.skip_previous, size: 30, color: Colors.white),
              onPressed: _previousPhoto,
            ),
            IconButton(
              icon: Icon(
                _manualControl ? Icons.play_arrow : Icons.pause,
                size: 30,
                color: Colors.white,
              ),
              onPressed: _togglePlayPause,
            ),
            IconButton(
              icon: const Icon(Icons.skip_next, size: 30, color: Colors.white),
              onPressed: _nextPhoto,
            ),
            IconButton(
              icon: Icon(
                _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                size: 30,
                color: Colors.white,
              ),
              onPressed: _toggleFullscreen,
            ),
          ],
        ),
      ),
    );
  }
}
