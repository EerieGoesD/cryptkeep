import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<bool> saveFileBytes(String fileName, Uint8List bytes) async {
  final result = await FilePicker.platform.saveFile(
    dialogTitle: 'Save vault export',
    fileName: fileName,
    bytes: bytes,
  );
  return result != null;
}
