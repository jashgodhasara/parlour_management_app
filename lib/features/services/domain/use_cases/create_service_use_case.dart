import '../../../../core/utils/result.dart';
import '../service.dart';
import '../service_catalog_repository.dart';

class CreateServiceUseCase {
  final ServiceCatalogRepository _repository;
  CreateServiceUseCase(this._repository);

  Future<Result<ParlourService>> call({
    required String name,
    required double price,
    required String categoryId,
  }) async {
    if (name.trim().isEmpty) {
      return Failure(const InvalidServiceFailure('Service name cannot be empty.'));
    }
    if (price < 0) {
      return Failure(const InvalidServiceFailure('Price must be ₹0 or more.'));
    }
    return _repository.createService(
      name: name.trim(),
      price: price,
      categoryId: categoryId,
    );
  }
}
