import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:learner/db/app_database.dart';
import 'package:learner/db/repository.dart';
import 'package:learner/services/secret_store.dart';

void main() {
  test('API key round-trips through DPAPI and is not stored in plain text', () async {
    final tmp = await Directory.systemTemp.createTemp('learner_secret');
    final db = await AppDatabase.open(dir: tmp.path);
    final repo = Repository(db);
    final store = SecretStore(repo);
    expect(await store.read(), '');
    await store.write('sk-ant-test-123');
    expect(await store.read(), 'sk-ant-test-123');
    final rows = await db.db.query('settings');
    expect(rows.any((r) => '${r['value']}'.contains('sk-ant')), isFalse);
    await store.write('');
    expect(await store.read(), '');
    await db.db.close();
  });
}
