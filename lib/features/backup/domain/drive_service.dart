abstract class DriveService {
  Future<void> signIn();
  Future<void> uploadFile(String fileName, List<int> bytes);
  Future<List<int>?> downloadFile(String fileName);
  Future<DateTime?> getFileModifiedTime(String fileName);
  Future<void> signOut();
}
