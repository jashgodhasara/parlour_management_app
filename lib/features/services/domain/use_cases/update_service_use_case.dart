import '../../../../core/utils/result.dart';
import '../service.dart';
import '../service_catalog_repository.dart';

class UpdateServiceUseCase {
  final ServiceCatalogRepository _repository;
  UpdateServiceUseCase(this._repository);

  Future<Result<ParlourService>> call(ParlourService service) async {
    if (service.name.trim().isEmpty) {
      return Failure(const InvalidServiceFailure('Service name cannot be empty.'));
    }
    if (service.price < 0) {
      return Failure(const InvalidServiceFailure('Price must be ₹0 or more.'));
    }
    return _repository.updateService(service);
  }
}
