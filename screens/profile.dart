import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:minio/minio.dart';
import 'package:path/path.dart' as Path;
import 'package:trip/screens/login_screen.dart';
import 'package:trip/screens/user_search.dart';
import 'package:trip/services/fcm_service.dart';
import 'package:trip/services/profile_service.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);
  
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  String _profilePhotoUrl = '';
  String _privacySetting = 'От всех пользователей';
  Map<String, dynamic> _allowedUsers = {};
  List<String> _suggestedUsers = [];
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();
  final ProfileService _profileService = ProfileService();
  final Minio _minio = Minio(
    endPoint: '91.197.98.163',
    port: 9000,
    accessKey: 'minioadmin',
    secretKey: 'minioadminpassword',
    useSSL: false,
  );
  User? _currentUser;
  bool _isNicknameTaken = false;
  bool _isProcessing = false;
  late AnimationController _loadingController;

  @override
  void initState() {
    super.initState();
    _loadingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _loadUserData();
  }

  @override
  void dispose() {
    _loadingController.dispose();
    _nicknameController.dispose();
    _searchController.dispose();
    super.dispose();
  }
  Future<void> _loadUserData() async {
    _currentUser = _auth.currentUser;
    if (_currentUser != null) {
      final userDoc = await _firestore.collection('users').doc(_currentUser!.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data()!;
        setState(() {
          _nicknameController.text = data['nickname'] ?? '';
          _profilePhotoUrl = data['profilePhotoUrl'] ?? '';
          _privacySetting = data['privacySetting'] ?? 'От всех пользователей';
          _allowedUsers = data['allowedUsers'] != null
              ? Map<String, dynamic>.from(data['allowedUsers'])
              : {};
        });
      } else {
        await _firestore.collection('users').doc(_currentUser!.uid).set({
          'nickname': _currentUser!.email?.split('@')[0] ?? 'Пользователь',
          'profilePhotoUrl': '',
          'privacySetting': 'От всех пользователей',
          'allowedUsers': {},
        });
      }
    }
  }
  Future<void> _checkNicknameUnique(String nickname) async {
    final query = await _firestore.collection('users').where('nickname', isEqualTo: nickname).get();
    setState(() {
      _isNicknameTaken = query.docs.isNotEmpty;
    });
  }
  Future<void> _pickAndUploadProfilePhoto() async {
    final ImageSource? source = await showDialog<ImageSource>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Выбрать источник'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ImageSource.gallery),
            child: const Text('Галерея'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ImageSource.camera),
            child: const Text('Камера'),
          ),
        ],
      ),
    );
    if (source == null) return;
    try {
      final image = await _picker.pickImage(source: source);
      if (image != null) {
        setState(() {
          _isProcessing = true;
        });
        File file = File(image.path);
        String fileName = 'profile_${_currentUser!.uid}_${Path.basename(file.path)}';
        String bucketName = 'profile-photos';
        bool bucketExists = await _minio.bucketExists(bucketName);
        if (!bucketExists) {
          await _minio.makeBucket(bucketName);
        }
        var stream = file.openRead().transform(
          StreamTransformer<List<int>, Uint8List>.fromHandlers(
            handleData: (data, sink) {
              sink.add(Uint8List.fromList(data));
            },
          ),
        );
        await _minio.putObject(bucketName, fileName, stream);
        String downloadUrl = await _minio.presignedGetObject(bucketName, fileName, expires: 7 * 24 * 3600);
        await _firestore.collection('users').doc(_currentUser!.uid).update({'profilePhotoUrl': downloadUrl});
        setState(() {
          _profilePhotoUrl = downloadUrl;
          _isProcessing = false;
        });
        _showCustomMessage('Фото профиля успешно обновлено!');
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      _showCustomMessage('Ошибка загрузки фото профиля',
          icon: Icons.error_outline, backgroundColor: Colors.redAccent);
    }
  }
  Future<void> _saveNickname() async {
    if (_nicknameController.text.trim().isNotEmpty) {
      await _checkNicknameUnique(_nicknameController.text.trim());
      if (_isNicknameTaken) {
        _showCustomMessage('Такой никнейм уже занят, выберите другой',
            icon: Icons.error_outline, backgroundColor: Colors.redAccent);
        return;
      }
      await _firestore.collection('users').doc(_currentUser!.uid).update({
        'nickname': _nicknameController.text.trim()
      });
      _showCustomMessage('Никнейм успешно обновлен');
    } else {
      _showCustomMessage('Никнейм не может быть пустым',
          icon: Icons.error_outline, backgroundColor: Colors.redAccent);
    }
  }
  Future<void> _addAllowedUserViaSearch() async {
    final currentUserUid = _currentUser?.uid;
    final excludedUids = <String>[
      if (currentUserUid != null) currentUserUid,
      ..._allowedUsers.keys,
    ];
    final result = await showSearch<Map<String, dynamic>?>(
      context: context,
      delegate: UserSearchDelegate(excludedUserIds: excludedUids),
    );
    if (result != null && result['uid'] != null) {
      final recipientDoc = await _firestore.collection('users').doc(result['uid']).get();
      final data = recipientDoc.data();
      bool allowReceive = data != null ? (data['allowReceive'] ?? true) : true;
      if (!allowReceive) {
        _showCustomMessage(
          "Пользователь ${result['nickname'] ?? result['email']} не разрешает получать фотографии.",
          icon: Icons.error_outline,
          backgroundColor: Colors.redAccent,
        );
        return;
      }
      setState(() {
        _allowedUsers[result['uid']] = {
          'nickname': result['nickname'] ?? '',
          'email': result['email'] ?? '',
        };
      });
      await _firestore.collection('users').doc(_currentUser!.uid).update({'allowedUsers': _allowedUsers});
      _showCustomMessage('Пользователь успешно добавлен в разрешенные');
    }
  }
  Future<void> _sendSupportRequest() async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'support@app.com',
      query: 'subject=Поддержка&body=Описание проблемы:',
    );
    if (await canLaunch(emailLaunchUri.toString())) {
      await launch(emailLaunchUri.toString());
    } else {
      _showCustomMessage('Не удалось открыть приложение электронной почты',
          icon: Icons.error_outline, backgroundColor: Colors.redAccent);
    }
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
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }
  Widget _buildProcessingOverlay({String message = "Загрузка..."}) {
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
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFC5C7D), Color(0xFF6A82FB)],
                  ),
                ),
                child: const Icon(
                  Icons.person,
                  size: 50,
                  color: Colors.white,
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
              ),
            )
          ],
        ),
      ),
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
              _buildCustomAppBar(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      _buildProfilePhotoSection(),
                      const SizedBox(height: 16),
                      _buildNicknameSection(),
                      const SizedBox(height: 16),
                      _buildPrivacySection(),
                      const SizedBox(height: 16),
                      _buildSupportButton(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      extendBody: true,
      bottomSheet: _isProcessing ? _buildProcessingOverlay(message: "Обработка...") : null,
    );
  }

  Widget _buildCustomAppBar(BuildContext context) {
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
            'Профиль',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          IconButton(
  icon: const Icon(Icons.logout, color: Colors.white),
  onPressed: () async {
    await FcmService.removeToken();
    await _auth.signOut();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  },
),

        ],
      ),
    );
  }

  Widget _buildProfilePhotoSection() {
    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: _pickAndUploadProfilePhoto,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.black26, blurRadius: 8, offset: const Offset(2, 2)),
                ],
              ),
              child: CircleAvatar(
                radius: 50,
                backgroundImage: _profilePhotoUrl.isNotEmpty ? NetworkImage(_profilePhotoUrl) : null,
                child: _profilePhotoUrl.isEmpty ? const Icon(Icons.person, size: 50, color: Colors.grey) : null,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Нажмите на фото, чтобы изменить', style: TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildNicknameSection() {
    return Card(
      color: Colors.white.withOpacity(0.8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nicknameController,
                decoration: InputDecoration(
                  labelText: 'Никнейм',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _saveNickname,
              icon: const Icon(Icons.save),
              label: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacySection() {
    return Card(
      color: Colors.white.withOpacity(0.8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Настройки приватности', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _privacySetting,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (value) async {
                if (value == null) return;
                setState(() {
                  _privacySetting = value;
                });
                await _firestore.collection('users').doc(_currentUser!.uid).update({'privacySetting': _privacySetting});
              },
              items: const [
                DropdownMenuItem(value: 'От всех пользователей', child: Text('От всех пользователей')),
                DropdownMenuItem(value: 'От некоторых пользователей', child: Text('От некоторых пользователей')),
                DropdownMenuItem(value: 'Нет', child: Text('Нет')),
              ],
            ),
            if (_privacySetting == 'От некоторых пользователей') ...[
              const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Поиск пользователей',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.white,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () async {
                      await _addAllowedUserViaSearch();
                    },
                  ),
                ),
                onChanged: (value) async {
                  if (value.isEmpty) {
                    setState(() {
                      _suggestedUsers = [];
                    });
                  } else {
                    final suggestions = await _profileService.searchNicknames(
                        value, _currentUser, _allowedUsers.keys.toList());
                    setState(() {
                      _suggestedUsers = suggestions;
                    });
                  }
                },
              ),
              const SizedBox(height: 8),
              if (_suggestedUsers.isNotEmpty)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _suggestedUsers.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        title: Text(_suggestedUsers[index]),
                        trailing: IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () => _addAllowedUserViaSearch(),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
              const Divider(),
              const Text('Разрешенные пользователи:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _allowedUsers.isNotEmpty
                  ? Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _allowedUsers.length,
                        itemBuilder: (context, index) {
                          String uid = _allowedUsers.keys.toList()[index];
                          var data = _allowedUsers[uid];
                          String displayName = data['nickname'] ?? uid;
                          String email = data['email'] ?? '';
                          return Card(
                            elevation: 2,
                            child: ListTile(
                              tileColor: Colors.blue.withOpacity(0.1),
                              leading: CircleAvatar(
                                backgroundColor: Colors.blueAccent,
                                child: Text(
                                  displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              title: Text(displayName),
                              subtitle: Text(email),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () async {
                                  setState(() {
                                    _allowedUsers.remove(uid);
                                  });
                                  await _firestore.collection('users').doc(_currentUser!.uid).update({'allowedUsers': _allowedUsers});
                                  _showCustomMessage("Пользователь удален из разрешенных");
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  : const Text('Пока никого нет', style: TextStyle(color: Colors.black54)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSupportButton() {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: _sendSupportRequest,
      icon: const Icon(Icons.help_outline),
      label: const Text('Связаться с поддержкой'),
    );
  }
}
