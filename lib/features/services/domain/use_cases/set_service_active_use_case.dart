import '../../../../core/utils/result.dart';
import '../service_catalog_repository.dart';

class SetServiceActiveUseCase {
  final ServiceCatalogRepository _repository;
  SetServiceActiveUseCase(this._repository);

  Future<Result<void>> call(String serviceId, bool active) async {
    return _repository.setServiceActive(serviceId, active);
  }
}
