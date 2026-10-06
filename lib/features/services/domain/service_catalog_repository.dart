import '../../../core/utils/result.dart';
import 'service.dart';
import 'service_category.dart';

abstract class ServiceCatalogRepository {
  Future<Result<ParlourService>> createService({
    required String name,
    required double price,
    required String categoryId,
  });
  Future<Result<ParlourService>> updateService(ParlourService service);
  Future<Result<void>> setServiceActive(String id, bool active);
  Stream<List<ParlourService>> watchActiveServices();
  Future<Result<List<ParlourService>>> getActiveServices();
  Future<Result<List<ParlourService>>> getServicesByCategory(String categoryId);
  Future<Result<List<ServiceCategory>>> getCategories();
  Future<Result<ServiceCategory>> createCategory(String name);
}
