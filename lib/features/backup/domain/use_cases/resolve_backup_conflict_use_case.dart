import '../backup_data.dart';

class ResolveBackupConflictUseCase {
  const ResolveBackupConflictUseCase();

  /// Returns the most recent backup snapshot.
  /// When timestamps are equal, local wins.
  BackupData call(BackupData local, BackupData remote) {
    if (remote.updatedAt.isAfter(local.updatedAt)) {
      return remote;
    }
    return local;
  }
}
