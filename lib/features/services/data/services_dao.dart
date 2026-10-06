import '../domain/service.dart';
import '../domain/service_category.dart';

/// In-memory DAO for services and categories.
class ServicesDao {
  final Map<String, ServiceCategory> _categories = {};
  final Map<String, ParlourService> _services = {};

  // Categories
  Future<void> insertCategory(ServiceCategory category) async {
    _categories[category.id] = category;
  }

  Future<List<ServiceCategory>> getAllCategories() async {
    return _categories.values.toList();
  }

  // Services
  Future<void> insertService(ParlourService service) async {
    _services[service.id] = service;
  }

  Future<void> updateService(ParlourService service) async {
    _services[service.id] = service;
  }

  Future<void> setActive(String id, bool active) async {
    final service = _services[id];
    if (service != null) {
      _services[id] = service.copyWith(isActive: active);
    }
  }

  Stream<List<ParlourService>> watchActiveServices() async* {
    final active = _services.values
        .where((s) => s.isActive)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    yield active;
  }

  Future<List<ParlourService>> getServicesByCategory(String categoryId) async {
    return _services.values
        .where((s) => s.categoryId == categoryId && s.isActive)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<ParlourService?> findById(String id) async {
    return _services[id];
  }

  Future<List<ParlourService>> getAllServices() async {
    return _services.values.toList();
  }
}
