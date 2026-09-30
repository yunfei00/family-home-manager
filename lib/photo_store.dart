import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PhotoStore {
  PhotoStore._();

  static final PhotoStore instance = PhotoStore._();

  final ImagePicker _picker = ImagePicker();

  Future<String?> pickAndSave(
    ImageSource source, {
    String? replacePath,
  }) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (picked == null) return null;

    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'photos'));
    await directory.create(recursive: true);

    final pickedExtension = p.extension(picked.path);
    final extension = pickedExtension.isEmpty ? '.jpg' : pickedExtension;
    final filename =
        'photo_${DateTime.now().microsecondsSinceEpoch}$extension';
    final target = File(p.join(directory.path, filename));
    await File(picked.path).copy(target.path);

    if (replacePath != null && replacePath != target.path) {
      await deletePhoto(replacePath);
    }
    return target.path;
  }

  Future<void> deletePhoto(String? path) async {
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  bool exists(String? path) {
    if (path == null || path.isEmpty) return false;
    return File(path).existsSync();
  }
}
