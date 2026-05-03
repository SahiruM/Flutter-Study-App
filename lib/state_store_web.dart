// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

String _storeKey(String key) => 'suustudy_$key';

Future<String?> readStoredValue(String key) async {
  return html.window.localStorage[_storeKey(key)];
}

Future<void> writeStoredValue(String key, String value) async {
  html.window.localStorage[_storeKey(key)] = value;
}

Future<void> deleteStoredValue(String key) async {
  html.window.localStorage.remove(_storeKey(key));
}
