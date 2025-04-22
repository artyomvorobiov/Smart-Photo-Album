import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class UserSearchDelegate extends SearchDelegate<Map<String, dynamic>?> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final List<String> excludedUserIds;


  final Color backgroundColor = const Color(0xFFF5EEDC); 
  final Color primaryColor = const Color(0xFF27548A); 
  final Color secondaryColor = const Color(0xFF183B4E); 
  final Color accentColor = const Color(0xFFDDA853); 

  UserSearchDelegate({this.excludedUserIds = const []});

  @override
  String get searchFieldLabel => 'Найти пользователя...';

  @override
  ThemeData appBarTheme(BuildContext context) {
    return ThemeData(
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColor,
      appBarTheme: AppBarTheme(
        backgroundColor: primaryColor,
        elevation: 0,
        iconTheme: IconThemeData(color: accentColor),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: Colors.white70, fontSize: 18),
        border: InputBorder.none,
      ),
      textTheme: TextTheme(
        titleLarge: TextStyle(color: accentColor, fontSize: 20),
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
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            backgroundColor,
            accentColor,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: query.isEmpty
          ? Center(
              child: Text(
                'Введите ник или email для поиска',
                style: TextStyle(
                  fontSize: 20,
                  color: secondaryColor.withOpacity(0.8),
                ),
              ),
            )
          : FutureBuilder<List<Map<String, dynamic>>>(
              future: _searchUsers(query),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(accentColor),
                    ),
                  );
                } else if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Ошибка: ${snapshot.error}',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 18,
                      ),
                    ),
                  );
                }
                final results = snapshot.data;
                if (results == null || results.isEmpty) {
                  return Center(
                    child: Text(
                      'Пользователь не найден',
                      style: TextStyle(
                        color: secondaryColor,
                        fontSize: 20,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final user = results[index];
                    final nickname = (user['nickname'] ?? '').toString();
                    final email = (user['email'] ?? '').toString();
                    return Card(
                      color: Colors.white.withOpacity(0.9),
                      elevation: 3,
                      margin: const EdgeInsets.symmetric(
                          vertical: 6, horizontal: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                            color: primaryColor.withOpacity(0.5), width: 1),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(12),
                        leading: CircleAvatar(
                          backgroundColor: primaryColor,
                          radius: 28,
                          child: Text(
                            nickname.isNotEmpty
                                ? nickname[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              color: accentColor,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          nickname,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: secondaryColor,
                          ),
                        ),
                        subtitle: Text(
                          email,
                          style: TextStyle(
                            fontSize: 16,
                            color: secondaryColor.withOpacity(0.8),
                          ),
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
