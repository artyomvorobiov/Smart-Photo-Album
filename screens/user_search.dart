import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class UserSearchDelegate extends SearchDelegate<Map<String, dynamic>?> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final List<String> excludedUserIds;

  UserSearchDelegate({this.excludedUserIds = const []});

  @override
  String get searchFieldLabel => 'Найти пользователя...';

  @override
  ThemeData appBarTheme(BuildContext context) {
    return ThemeData(
      primaryColor: Colors.transparent,
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor:  Color.fromARGB(185, 122, 137, 206),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: Colors.white70, fontSize: 18),
        border: InputBorder.none,
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: Colors.white, fontSize: 20),
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          tooltip: 'Очистить',
          icon: const Icon(Icons.clear),
          onPressed: () {
            query = '';
            showSuggestions(context);
          },
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      tooltip: 'Назад',
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, null);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSearchResults();
  }

  Widget _buildSearchResults() {
    return Container(
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
      child: query.isEmpty
          ? Center(
              child: Text(
                'Введите ник или email для поиска',
                style: TextStyle(fontSize: 20, color: Colors.white70),
              ),
            )
          : FutureBuilder<List<Map<String, dynamic>>>(
              future: _searchUsers(query),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Ошибка: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }
                final results = snapshot.data;
                if (results == null || results.isEmpty) {
                  return Center(
                    child: Text(
                      'Пользователь не найден',
                      style: TextStyle(color: Colors.white, fontSize: 20),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final user = results[index];
                    final nickname = (user['nickname'] ?? '').toString();
                    final email = (user['email'] ?? '').toString();
                    return Card(
                      color: Colors.white.withOpacity(0.8),
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(12),
                        leading: CircleAvatar(
                          backgroundColor: Colors.blueGrey,
                          radius: 28,
                          child: Text(
                            nickname.isNotEmpty ? nickname[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white, fontSize: 22),
                          ),
                        ),
                        title: Text(
                          nickname,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          email,
                          style: const TextStyle(fontSize: 16),
                        ),
                        onTap: () {
                          close(context, user);
                        },
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  Future<List<Map<String, dynamic>>> _searchUsers(String query) async {
    try {
      final snapshot = await _firestore.collection('users').limit(50).get();
      final lowerQuery = query.toLowerCase();
      List<Map<String, dynamic>> results = [];
      for (var doc in snapshot.docs) {
        if (excludedUserIds.contains(doc.id)) continue;
        final data = doc.data();
        final nickname = (data['nickname'] ?? '').toString().toLowerCase();
        final email = (data['email'] ?? '').toString().toLowerCase();
        if (nickname.contains(lowerQuery) || email.contains(lowerQuery)) {
          results.add({
            'uid': doc.id,
            ...data,
          });
        }
      }
      return results;
    } catch (e) {
      print("Ошибка при поиске пользователей: $e");
      return [];
    }
  }
}
