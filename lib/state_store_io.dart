import 'dart:io';

import 'package:path_provider/path_provider.dart';

Directory? _directory;

Future<Directory> _storeDirectory() async {
  if (_directory != null) return _directory!;
  _directory = await getApplicationSupportDirectory();
  return _directory!;
}

String _safeKey(String key) => key.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');

Future<File> _storeFile(String key) async {
  final directory = await _storeDirectory();
  return File(
    '${directory.path}${Platform.pathSeparator}${_safeKey(key)}.json',
  );
}

Future<String?> readStoredValue(String key) async {
  final file = await _storeFile(key);
  if (!await file.exists()) return null;
  return file.readAsString();
}

Future<void> writeStoredValue(String key, String value) async {
  final file = await _storeFile(key);
  await file.parent.create(recursive: true);
  await file.writeAsString(value);
}

Future<void> deleteStoredValue(String key) async {
  final file = await _storeFile(key);
  if (await file.exists()) {
    await file.delete();
  }
}
