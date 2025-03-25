import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class SharedUserTile extends StatelessWidget {
  final String uid;
  final String permission;
  final VoidCallback onRemove;

  const SharedUserTile({
    Key? key,
    required this.uid,
    required this.permission,
    required this.onRemove,
  }) : super(key: key);

  String _permissionText(String permission) {
    switch (permission) {
      case 'view':
        return "Только просмотр";
      case 'add':
        return "Добавление фотографий";
      case 'edit':
        return "Удаление и добавление фотографий";
      default:
        return permission;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, snapshot) {
        String nickname = uid;
        if (snapshot.connectionState == ConnectionState.waiting) {
          nickname = "Загрузка...";
        } else if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          nickname = data['nickname'] ?? uid;
        }
        return Card(
          color: Colors.white.withOpacity(0.75),
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              child: Text(
                nickname.isNotEmpty ? nickname[0].toUpperCase() : "?",
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.blueAccent,
            ),
            title: Text(nickname),
            subtitle: Text("Права: ${_permissionText(permission)}"),
            trailing: IconButton(
              icon: const Icon(Icons.remove_circle, color: Colors.red),
              onPressed: onRemove,
            ),
          ),
        );
      },
    );
  }
}
