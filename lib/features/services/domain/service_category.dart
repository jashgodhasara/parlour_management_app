class ServiceCategory {
  final String id;
  final String name;

  const ServiceCategory({required this.id, required this.name});

  ServiceCategory copyWith({String? id, String? name}) =>
      ServiceCategory(id: id ?? this.id, name: name ?? this.name);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServiceCategory &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'ServiceCategory(id: $id, name: $name)';
}
