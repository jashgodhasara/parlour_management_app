import '../domain/drive_service.dart';

/// Stub in-memory implementation of DriveService.
/// TODO: Replace with googleapis package implementation when Flutter SDK is available.
class DriveServiceImpl implements DriveService {
  bool _signedIn = false;
  final Map<String, List<int>> _fileStore = {};
  final Map<String, DateTime> _modifiedTimes = {};

  @override
  Future<void> signIn() async {
    // Stub: simulate successful sign-in.
    _signedIn = true;
  }

  @override
  Future<void> uploadFile(String fileName, List<int> bytes) async {
    if (!_signedIn) {
      throw StateError('Not signed in to Google Drive.');
    }
    _fileStore[fileName] = List.unmodifiable(bytes);
    _modifiedTimes[fileName] = DateTime.now();
  }

  @override
  Future<List<int>?> downloadFile(String fileName) async {
    if (!_signedIn) {
      throw StateError('Not signed in to Google Drive.');
    }
    return _fileStore[fileName];
  }

  @override
  Future<DateTime?> getFileModifiedTime(String fileName) async {
    if (!_signedIn) {
      throw StateError('Not signed in to Google Drive.');
    }
    return _modifiedTimes[fileName];
  }

  @override
  Future<void> signOut() async {
    _signedIn = false;
  }
}
