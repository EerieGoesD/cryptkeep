// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html; // ignore: deprecated_member_use
import 'dart:typed_data';

Future<bool> saveFileBytes(String fileName, Uint8List bytes) async {
  final blob = html.Blob([bytes], 'application/octet-stream');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
  return true;
}
