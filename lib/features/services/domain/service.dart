class ParlourService {
  final String id;
  final String name;
  final double price;
  final String categoryId;
  final bool isActive;

  const ParlourService({
    required this.id,
    required this.name,
    required this.price,
    required this.categoryId,
    required this.isActive,
  });

  ParlourService copyWith({
    String? id,
    String? name,
    double? price,
    String? categoryId,
    bool? isActive,
  }) {
    return ParlourService(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      categoryId: categoryId ?? this.categoryId,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParlourService &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          price == other.price &&
          categoryId == other.categoryId &&
          isActive == other.isActive;

  @override
  int get hashCode => Object.hash(id, name, price, categoryId, isActive);

  @override
  String toString() => 'ParlourService(id: $id, name: $name, price: $price, isActive: $isActive)';
}
