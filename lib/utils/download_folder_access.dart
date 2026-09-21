/// Helpers for the user-chosen download folder.
///
/// On Android 11+ the Rust downloader writes with plain file paths, which only
/// works for arbitrary shared-storage folders when the app holds "All files
/// access" (MANAGE_EXTERNAL_STORAGE). These helpers centralise that permission
/// flow and provide a real write probe, so the settings screen and the
/// downloader cubit share the same logic.
import 'dart:developer';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class DownloadFolderAccess {
  DownloadFolderAccess._();

  /// Android 11 (API 30) is where scoped storage starts blocking direct
  /// writes to arbitrary shared folders and "All files access" appears.
  static const int _manageStorageMinSdk = 30;

  /// Whether the app currently may write to arbitrary folders.
  ///
  /// Non-Android platforms have no such gate and always return `true`.
  static Future<bool> hasAccess() async {
    if (!Platform.isAndroid) return true;
    try {
      final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      if (sdk >= _manageStorageMinSdk) {
        return Permission.manageExternalStorage.isGranted;
      }
      return Permission.storage.isGranted;
    } catch (e) {
      log('hasAccess failed: $e', name: 'DownloadFolderAccess');
      return false;
    }
  }

  /// Requests the access needed to write to a user-chosen folder.
  ///
  /// On Android 11+ the system has no dialog for this: it sends the user to
  /// the "All files access" settings page, and this future completes once
  /// they return. Returns whether access is granted afterwards.
  static Future<bool> request() async {
    if (!Platform.isAndroid) return true;
    try {
      final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      final status = sdk >= _manageStorageMinSdk
          ? await Permission.manageExternalStorage.request()
          : await Permission.storage.request();
      return status.isGranted;
    } catch (e) {
      log('request failed: $e', name: 'DownloadFolderAccess');
      return false;
    }
  }

  /// Whether [dirPath] lives inside one of this app's own directories.
  ///
  /// Those are writable without any permission (this is where the old default
  /// `Android/data/<package>/files/downloads` lives), so only folders outside
  /// them need "All files access".
  static Future<bool> isAppOwnedPath(String dirPath) async {
    if (!Platform.isAndroid) return true;
    try {
      final roots = <String>[
        (await getApplicationDocumentsDirectory()).path,
        (await getApplicationSupportDirectory()).path,
        (await getTemporaryDirectory()).path,
        ...?(await getExternalStorageDirectories())?.map((d) => d.path),
      ];
      final target = Directory(dirPath).absolute.path;
      return roots.any((root) =>
          target == root || target.startsWith('$root${Platform.pathSeparator}'));
    } catch (e) {
      log('isAppOwnedPath failed: $e', name: 'DownloadFolderAccess');
      return false;
    }
  }

  /// Checks that [dirPath] exists (creating it if needed) and can be written
  /// to, by creating and deleting a small probe file.
  ///
  /// Returns `null` when the folder is writable, otherwise a short,
  /// human-readable reason. This is a real write test rather than a
  /// permission check, because a granted permission does not guarantee that a
  /// given folder (e.g. a read-only SD card) is writable.
  static Future<String?> checkWritable(String dirPath) async {
    if (dirPath.trim().isEmpty) return 'No download folder is set.';
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final probe = File(
        '${dir.path}${Platform.pathSeparator}.bloomee_write_test',
      );
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return null;
    } on FileSystemException catch (e) {
      log('checkWritable failed for $dirPath: $e',
          name: 'DownloadFolderAccess');
      return "Can't write to '$dirPath': "
          '${e.osError?.message ?? e.message}';
    } catch (e) {
      log('checkWritable failed for $dirPath: $e',
          name: 'DownloadFolderAccess');
      return "Can't write to '$dirPath'.";
    }
  }
}
