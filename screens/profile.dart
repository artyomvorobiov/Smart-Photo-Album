import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
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

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final Color kBackgroundColor = const Color(0xFFF5EEDC);
  final Color kPrimaryColor = const Color(0xFF27548A);
  final Color kAppBarColor = const Color(0xFF183B4E);
  final Color kAccentColor = const Color(0xFFDDA853);

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
    endPoint: '****',
    port: ****,
    accessKey: '****',
    secretKey: '****',
    useSSL: ****,
  );
  User? _currentUser;
  bool _isNicknameTaken = false;
  bool _isProcessing = false;
  late AnimationController _loadingController;

  String _tariff = 'basic';
  int _storageUsed = 0;
  int _storageQuota = 100 * 1024 * 1024;

  static const String _premiumProductId = 'premium_subscription';
  late final StreamSubscription<List<PurchaseDetails>> _purchaseSubscription;

  @override
  void initState() {
    super.initState();
    _loadingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _purchaseSubscription = InAppPurchase.instance.purchaseStream
        .listen(_listenToPurchaseUpdated, onDone: () {
      _purchaseSubscription.cancel();
    }, onError: (error) {
      _showCustomMessage("Ошибка платежного потока: $error",
          backgroundColor: Colors.redAccent);
    });
    _loadUserData();
  }

  @override
  void dispose() {
    _purchaseSubscription.cancel();
    _loadingController.dispose();
    _nicknameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    _currentUser = _auth.currentUser;
    if (_currentUser != null) {
      final userDoc =
          await _firestore.collection('users').doc(_currentUser!.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data()!;
        setState(() {
          _nicknameController.text = data['nickname'] ?? '';
          _profilePhotoUrl = data['profilePhotoUrl'] ?? '';
          _privacySetting = data['privacySetting'] ?? 'От всех пользователей';
          _allowedUsers = data['allowedUsers'] != null
              ? Map<String, dynamic>.from(data['allowedUsers'])
              : {};
          _tariff = data['tariff'] ?? 'basic';
          _storageUsed = data['storageUsed'] ?? 0;
          _storageQuota = data['storageQuota'] ?? (100 * 1024 * 1024);
        });
      } else {
        await _firestore.collection('users').doc(_currentUser!.uid).set({
          'nickname': _currentUser!.email?.split('@')[0] ?? 'Пользователь',
          'profilePhotoUrl': '',
          'privacySetting': 'От всех пользователей',
          'allowedUsers': {},
          'tariff': 'basic',
          'storageUsed': 0,
          'storageQuota': 100 * 1024 * 1024,
        });
      }
    }
  }

  Future<void> _checkNicknameUnique(String nickname) async {
    final query = await _firestore
        .collection('users')
        .where('nickname', isEqualTo: nickname)
        .get();
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
        String fileName =
            'profile_${_currentUser!.uid}_${Path.basename(file.path)}';
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
        String downloadUrl = await _minio
            .presignedGetObject(bucketName, fileName, expires: 7 * 24 * 3600);
        await _firestore
            .collection('users')
            .doc(_currentUser!.uid)
            .update({'profilePhotoUrl': downloadUrl});
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
      await _firestore
          .collection('users')
          .doc(_currentUser!.uid)
          .update({'nickname': _nicknameController.text.trim()});
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
      final recipientDoc =
          await _firestore.collection('users').doc(result['uid']).get();
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
      await _firestore
          .collection('users')
          .doc(_currentUser!.uid)
          .update({'allowedUsers': _allowedUsers});
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

  Future<void> _upgradeTariff() async {
    final bool available = await InAppPurchase.instance.isAvailable();
    if (!available) {
      _showCustomMessage("Покупки недоступны на данном устройстве.",
          backgroundColor: Colors.redAccent);
      return;
    }

    const Set<String> _productIds = {_premiumProductId};
    final ProductDetailsResponse response =
        await InAppPurchase.instance.queryProductDetails(_productIds);
    if (response.notFoundIDs.isNotEmpty) {
      _showCustomMessage("Продукт не найден.",
          backgroundColor: Colors.redAccent);
      return;
    }
    final ProductDetails productDetails = response.productDetails.first;

    final PurchaseParam purchaseParam =
        PurchaseParam(productDetails: productDetails);
    InAppPurchase.instance.buyNonConsumable(purchaseParam: purchaseParam);
  }

  void _listenToPurchaseUpdated(
      List<PurchaseDetails> purchaseDetailsList) async {
    for (final purchase in purchaseDetailsList) {
      if (purchase.status == PurchaseStatus.pending) {
      } else if (purchase.status == PurchaseStatus.error) {
        _showCustomMessage("Ошибка платежа: ${purchase.error}",
            backgroundColor: Colors.redAccent);
      } else if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        bool valid = await _verifyPurchase(purchase);
        if (valid) {
          int newQuota = 1024 * 1024 * 1024;
          await _firestore.collection('users').doc(_currentUser!.uid).update({
            'tariff': 'premium',
            'storageQuota': newQuota,
          });
          _showCustomMessage(
              "Тариф успешно обновлен! Теперь у вас 100 ГБ за 300 руб./мес.");
          _loadUserData();
        } else {
          _showCustomMessage("Платеж не прошел проверку!",
              backgroundColor: Colors.redAccent);
        }
        if (purchase.pendingCompletePurchase) {
          await InAppPurchase.instance.completePurchase(purchase);
        }
      }
    }
  }

  Future<bool> _verifyPurchase(PurchaseDetails purchase) async {
    return Future<bool>.value(true);
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
                  gradient: LinearGradient(
                    colors: [kAccentColor, kPrimaryColor],
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

  Widget _buildCustomAppBar(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: kPrimaryColor,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: kBackgroundColor),
            onPressed: () => Navigator.pop(context),
          ),
          Text(
            'Профиль',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: kBackgroundColor),
          ),
          IconButton(
            icon: Icon(Icons.logout, color: kBackgroundColor),
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
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: kAccentColor, width: 3),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: const Offset(2, 2)),
                ],
              ),
              child: CircleAvatar(
                radius: 50,
                backgroundImage: _profilePhotoUrl.isNotEmpty
                    ? NetworkImage(_profilePhotoUrl)
                    : null,
                backgroundColor: kBackgroundColor,
                child: _profilePhotoUrl.isEmpty
                    ? Icon(Icons.person, size: 50, color: kAppBarColor)
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Нажмите на фото, чтобы изменить',
            style: TextStyle(color: kAppBarColor.withOpacity(0.7), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildNicknameSection() {
    return Card(
      color: kBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nicknameController,
                style: TextStyle(color: kAppBarColor),
                decoration: InputDecoration(
                  labelText: 'Никнейм',
                  labelStyle: TextStyle(color: kAppBarColor),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: kBackgroundColor,
                ),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                foregroundColor: kBackgroundColor,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
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

  Widget _buildStorageInfoSection() {
    int availableBytes = _storageQuota - _storageUsed;
    double usedMB = _storageUsed / (1024 * 1024);
    double quotaMB = _storageQuota / (1024 * 1024);
    double availableMB = availableBytes / (1024 * 1024);
    double percentUsed = _storageQuota > 0 ? _storageUsed / _storageQuota : 0.0;
    int percentDisplay = (percentUsed * 100).round();

    return Card(
      color: kBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Информация о хранилище',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: kAppBarColor),
              textAlign: TextAlign.left,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.storage, color: kAppBarColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Тариф: $_tariff',
                    style: TextStyle(fontSize: 16, color: kAppBarColor),
                    textAlign: TextAlign.left,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.data_usage, color: kAppBarColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Использовано: ${usedMB.toStringAsFixed(2)} МБ из ${quotaMB.toStringAsFixed(2)} МБ',
                    style: TextStyle(fontSize: 16, color: kAppBarColor),
                    textAlign: TextAlign.left,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.check_circle_outline, color: kAccentColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Доступно: ${availableMB.toStringAsFixed(2)} МБ',
                    style: TextStyle(fontSize: 16, color: kAppBarColor),
                    textAlign: TextAlign.left,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: percentUsed,
              minHeight: 8,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(kAccentColor),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '$percentDisplay% использовано',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: kAppBarColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTariffUpgradeSection() {
  return Card(
    color: kBackgroundColor,
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    elevation: 3,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Обновить тариф',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: kAppBarColor),
          ),
          const SizedBox(height: 8),
          Text(
            'Оплата: 300 рублей в месяц за 100 ГБ',
            style: TextStyle(fontSize: 16, color: kAppBarColor),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey[400],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            onPressed: null, 
            icon:  Icon(Icons.lock, color: kAppBarColor),
            label: const Text('Функционал в разработке'),
          ),
        ],
      ),
    ),
  );
}



  Widget _buildPrivacySection() {
    return Card(
      color: kBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Настройки приватности',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: kAppBarColor)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _privacySetting,
              decoration: InputDecoration(
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: kBackgroundColor,
              ),
              style: TextStyle(color: kAppBarColor),
              onChanged: (value) async {
                if (value == null) return;
                setState(() {
                  _privacySetting = value;
                });
                await _firestore
                    .collection('users')
                    .doc(_currentUser!.uid)
                    .update({'privacySetting': _privacySetting});
              },
              items: const [
                DropdownMenuItem(
                    value: 'От всех пользователей',
                    child: Text('От всех пользователей')),
                DropdownMenuItem(
                    value: 'От некоторых пользователей',
                    child: Text('От некоторых пользователей')),
                DropdownMenuItem(value: 'Нет', child: Text('Нет')),
              ],
            ),
            if (_privacySetting == 'От некоторых пользователей') ...[
              const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                readOnly: true,
                onTap: () async {
                  await _addAllowedUserViaSearch();
                },
                style: TextStyle(color: kAppBarColor),
                decoration: InputDecoration(
                  labelText: 'Поиск пользователей',
                  labelStyle: TextStyle(color: kAppBarColor),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: kBackgroundColor,
                  suffixIcon: const Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 8),
              if (_suggestedUsers.isNotEmpty)
                Container(
                  decoration: BoxDecoration(
                    color: kBackgroundColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _suggestedUsers.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        title: Text(_suggestedUsers[index],
                            style: TextStyle(color: kAppBarColor)),
                        trailing: IconButton(
                          icon: Icon(Icons.add, color: kPrimaryColor),
                          onPressed: () => _addAllowedUserViaSearch(),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
              const Divider(),
              Text('Разрешенные пользователи:',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Color(0xFF183B4E))),
              const SizedBox(height: 8),
              _allowedUsers.isNotEmpty
                  ? Container(
                      decoration: BoxDecoration(
                        color: kBackgroundColor,
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
                              tileColor: kPrimaryColor.withOpacity(0.1),
                              leading: CircleAvatar(
                                backgroundColor: kPrimaryColor,
                                child: Text(
                                  displayName.isNotEmpty
                                      ? displayName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              title: Text(displayName,
                                  style: TextStyle(color: kAppBarColor)),
                              subtitle: Text(email,
                                  style: TextStyle(color: kAppBarColor)),
                              trailing: IconButton(
                                icon:
                                    const Icon(Icons.delete, color: Colors.red),
                                onPressed: () async {
                                  setState(() {
                                    _allowedUsers.remove(uid);
                                  });
                                  await _firestore
                                      .collection('users')
                                      .doc(_currentUser!.uid)
                                      .update({'allowedUsers': _allowedUsers});
                                  _showCustomMessage(
                                      "Пользователь удален из разрешенных");
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  : Text('Пока никого нет',
                      style: TextStyle(color: kAppBarColor.withOpacity(0.6))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSupportButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
          backgroundColor: kPrimaryColor,
          foregroundColor: kBackgroundColor,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: _sendSupportRequest,
        icon: const Icon(Icons.help_outline),
        label: const Text('Связаться с поддержкой'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [kBackgroundColor, kAccentColor],
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
                      _buildStorageInfoSection(),
                      _buildTariffUpgradeSection(),
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
      bottomSheet: _isProcessing
          ? _buildProcessingOverlay(message: "Обработка...")
          : null,
    );
  }
}
