class Customer {
  final String id;
  final String fullName;
  final String phoneNumber;
  final String? notes;
  final String? photoPath;
  final DateTime createdAt;
  final DateTime updatedAt;

const Customer({
    required this.id,
    required this.fullName,
    required this.phoneNumber,
    this.notes,
    this.photoPath,
    required this.createdAt,
    required this.updatedAt,
  });

Customer copyWith({
    String? id,
    String? fullName,
    String? phoneNumber,
    String? notes,
    String? photoPath,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Customer(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      notes: notes ?? this.notes,
      photoPath: photoPath ?? this.photoPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Customer &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          fullName == other.fullName &&
          phoneNumber == other.phoneNumber &&
          notes == other.notes &&
          photoPath == other.photoPath &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(id, fullName, phoneNumber, notes, photoPath, createdAt, updatedAt);

  @override
  String toString() => 'Customer(id: $id, fullName: $fullName, phoneNumber: $phoneNumber)';
}
