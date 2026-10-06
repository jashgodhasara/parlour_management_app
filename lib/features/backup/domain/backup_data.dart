enum ConflictResolution { useLocal, useRemote }

class BackupData {
  final DateTime updatedAt;
  final Map<String, dynamic> data;

  const BackupData({required this.updatedAt, required this.data});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackupData && runtimeType == other.runtimeType && updatedAt == other.updatedAt;

  @override
  int get hashCode => updatedAt.hashCode;

  @override
  String toString() => 'BackupData(updatedAt: $updatedAt)';
}

class BackupConflict {
  final BackupData local;
  final BackupData remote;

  const BackupConflict({required this.local, required this.remote});
}
