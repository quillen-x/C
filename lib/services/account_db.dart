import 'package:sqlite3/sqlite3.dart';

import '../models.dart';
import 'io_helpers.dart';

class AccountDb {
  Database? _db;

  Future<Database> _open() async {
    final existing = _db;
    if (existing != null) {
      _migrate(existing);
      return existing;
    }
    await IoHelpers.supportDir.create(recursive: true);
    final db = sqlite3.open('${IoHelpers.supportDir.path}/accounts.db');
    db.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
        username TEXT PRIMARY KEY COLLATE NOCASE,
        user_id TEXT NOT NULL DEFAULT '',
        name TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        avatar_url TEXT NOT NULL DEFAULT '',
        profile_url TEXT NOT NULL DEFAULT '',
        followers INTEGER NOT NULL DEFAULT 0,
        following INTEGER NOT NULL DEFAULT 0,
        tweets INTEGER NOT NULL DEFAULT 0,
        protected INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0,
        category TEXT NOT NULL DEFAULT '',
        special INTEGER NOT NULL DEFAULT 0
      )
    ''');
    _migrate(db);
    _db = db;
    return db;
  }

  void _migrate(Database db) {
    final columns = db
        .select('PRAGMA table_info(accounts)')
        .map((row) => '${row['name']}')
        .toSet();
    if (!columns.contains('category')) {
      db.execute(
        "ALTER TABLE accounts ADD COLUMN category TEXT NOT NULL DEFAULT ''",
      );
      db.execute("UPDATE accounts SET category = 'sex'");
    }
    if (!columns.contains('special')) {
      db.execute(
        'ALTER TABLE accounts ADD COLUMN special INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  static String get filePath => '${IoHelpers.supportDir.path}/accounts.db';

  Future<int> count() async {
    final row = (await _open()).select('SELECT COUNT(*) AS total FROM accounts').first;
    return (row['total'] as int?) ?? 0;
  }

  Future<Set<String>> syncedUsernames() async {
    final rows = (await _open()).select(
      'SELECT username FROM accounts WHERE updated_at > 0',
    );
    return rows
        .map((row) => '${row['username']}'.toLowerCase())
        .where((item) => item.isNotEmpty)
        .toSet();
  }

  Future<Map<String, XAccount>> loadMap() async {
    final rows = (await _open()).select('SELECT * FROM accounts');
    final map = <String, XAccount>{};
    for (final row in rows) {
      final account = _fromRow(row);
      final key = account.username.toLowerCase();
      if (key.isEmpty) {
        continue;
      }
      map[key] = account;
    }
    return map;
  }

  XAccount _fromRow(Row row) {
    return XAccount(
      id: '${row['user_id'] ?? ''}',
      username: '${row['username'] ?? ''}',
      name: '${row['name'] ?? ''}',
      description: '${row['description'] ?? ''}',
      avatarUrl: '${row['avatar_url'] ?? ''}',
      profileUrl: '${row['profile_url'] ?? ''}',
      followers: (row['followers'] as num?)?.toInt() ?? 0,
      following: (row['following'] as num?)?.toInt() ?? 0,
      tweets: (row['tweets'] as num?)?.toInt() ?? 0,
      protected: (row['protected'] as num?)?.toInt() == 1,
      updatedAt: (row['updated_at'] as num?)?.toInt() ?? 0,
      category: '${row['category'] ?? ''}',
      special: (row['special'] as num?)?.toInt() == 1,
    );
  }

  Future<List<XAccount>> loadAll() async {
    final rows = (await _open()).select(
      'SELECT * FROM accounts ORDER BY username COLLATE NOCASE',
    );
    return rows
        .map(_fromRow)
        .where((account) => account.username.isNotEmpty)
        .toList();
  }

  Future<XAccount?> get(String username) async {
    final name = username.trim();
    if (name.isEmpty) {
      return null;
    }
    final rows = (await _open()).select(
      'SELECT * FROM accounts WHERE username = ? COLLATE NOCASE',
      <Object>[name],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _fromRow(rows.first);
  }

  Future<Map<String, int>> categoryCounts() async {
    final rows = (await _open()).select(
      'SELECT category, COUNT(*) AS total FROM accounts GROUP BY category',
    );
    final counts = <String, int>{};
    for (final row in rows) {
      final key = '${row['category'] ?? ''}'.trim().toLowerCase();
      counts[key] = (counts[key] as int? ?? 0) + ((row['total'] as int?) ?? 0);
    }
    return counts;
  }

  Future<void> updateCategory(String username, String category) async {
    final name = username.trim();
    if (name.isEmpty) {
      return;
    }
    (await _open()).execute(
      'UPDATE accounts SET category = ? WHERE username = ? COLLATE NOCASE',
      <Object>[category.trim(), name],
    );
  }

  Future<void> updateSpecial(String username, bool special) async {
    final name = username.trim();
    if (name.isEmpty) {
      return;
    }
    (await _open()).execute(
      'UPDATE accounts SET special = ? WHERE username = ? COLLATE NOCASE',
      <Object>[special ? 1 : 0, name],
    );
  }

  Future<void> delete(String username) async {
    await deleteUsernames(<String>[username]);
  }

  Future<List<String>> usernamesWithTweetsLessThan(int maxTweets) async {
    return _usernamesWhere('tweets < ?', <Object>[maxTweets]);
  }

  Future<List<String>> usernamesWithFollowersLessThan(int maxFollowers) async {
    return _usernamesWhere('followers < ?', <Object>[maxFollowers]);
  }

  Future<List<String>> usernamesWithEmptyDescription() async {
    return _usernamesWhere("TRIM(description) = ''");
  }

  Future<List<String>> usernamesInCategory(String category) async {
    return _usernamesWhere(
      'LOWER(TRIM(category)) = ?',
      <Object>[category.trim().toLowerCase()],
    );
  }

  Future<List<String>> _usernamesWhere(String where, [List<Object>? args]) async {
    final rows = (await _open()).select(
      'SELECT username FROM accounts WHERE $where',
      args ?? const <Object>[],
    );
    return rows
        .map((row) => '${row['username']}'.trim())
        .where((name) => name.isNotEmpty)
        .toList();
  }

  Future<void> deleteUsernames(List<String> usernames) async {
    final names = usernames
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (names.isEmpty) {
      return;
    }
    final db = await _open();
    final stmt = db.prepare(
      'DELETE FROM accounts WHERE username = ? COLLATE NOCASE',
    );
    try {
      db.execute('BEGIN');
      for (final name in names) {
        stmt.execute(<Object>[name]);
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      stmt.dispose();
    }
  }

  Future<void> upsert(XAccount account) async {
    await upsertAll(<XAccount>[account]);
  }

  Future<void> upsertAll(List<XAccount> accounts) async {
    if (accounts.isEmpty) {
      return;
    }
    final db = await _open();
    final stmt = db.prepare('''
      INSERT INTO accounts (
        username, user_id, name, description, avatar_url, profile_url,
        followers, following, tweets, protected, updated_at, category, special
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(username) DO UPDATE SET
        user_id = excluded.user_id,
        name = excluded.name,
        description = excluded.description,
        avatar_url = excluded.avatar_url,
        profile_url = excluded.profile_url,
        followers = excluded.followers,
        following = excluded.following,
        tweets = excluded.tweets,
        protected = excluded.protected,
        updated_at = excluded.updated_at
    ''');
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      db.execute('BEGIN');
      for (final account in accounts) {
        stmt.execute(<Object?>[
          account.username,
          account.id,
          account.name,
          account.description,
          account.avatarUrl,
          account.profileUrl,
          account.followers,
          account.following,
          account.tweets,
          account.protected ? 1 : 0,
          now,
          account.category,
          account.special ? 1 : 0,
        ]);
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      stmt.dispose();
    }
  }

  void close() {
    _db?.dispose();
    _db = null;
  }
}
