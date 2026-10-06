import 'package:uuid/uuid.dart';
import '../../../../core/utils/result.dart';
import '../domain/service.dart';
import '../domain/service_catalog_repository.dart';
import '../domain/service_category.dart';
import 'services_dao.dart';

class ServiceCatalogRepositoryImpl implements ServiceCatalogRepository {
  final ServicesDao _dao;
  final _uuid = const Uuid();

  ServiceCatalogRepositoryImpl(this._dao);

  @override
  Future<Result<ParlourService>> createService({
    required String name,
    required double price,
    required String categoryId,
  }) async {
    try {
      final service = ParlourService(
        id: _uuid.v4(),
        name: name,
        price: price,
        categoryId: categoryId,
        isActive: true,
      );
      await _dao.insertService(service);
      return Success(service);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<ParlourService>> updateService(ParlourService service) async {
    try {
      await _dao.updateService(service);
      return Success(service);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> setServiceActive(String id, bool active) async {
    try {
      await _dao.setActive(id, active);
      return const Success(null);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Stream<List<ParlourService>> watchActiveServices() {
    return _dao.watchActiveServices();
  }

  @override
  Future<Result<List<ParlourService>>> getActiveServices() async {
    try {
      // Since watchActiveServices returns a Stream, we need to get the first value
      // or create a separate method in the DAO. Let me check if getAllServices exists.
      final allServices = await _dao.getAllServices();
      final activeServices = allServices.where((s) => s.isActive).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return Success(activeServices);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<List<ParlourService>>> getServicesByCategory(String categoryId) async {
    try {
      final services = await _dao.getServicesByCategory(categoryId);
      return Success(services);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<List<ServiceCategory>>> getCategories() async {
    try {
      final categories = await _dao.getAllCategories();
      return Success(categories);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<ServiceCategory>> createCategory(String name) async {
    try {
      final category = ServiceCategory(id: _uuid.v4(), name: name);
      await _dao.insertCategory(category);
      return Success(category);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }
}
