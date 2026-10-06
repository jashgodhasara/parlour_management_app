class AppSettingsEntity {
  final String parlourName;
  final String ownerName;
  final String? ownerPhone;
  final String currencySymbol;
  final bool notificationsEnabled;

  const AppSettingsEntity({
    required this.parlourName,
    required this.ownerName,
    this.ownerPhone,
    required this.currencySymbol,
    required this.notificationsEnabled,
  });

  static const AppSettingsEntity defaults = AppSettingsEntity(
    parlourName: 'My Parlour',
    ownerName: '',
    currencySymbol: '₹',
    notificationsEnabled: true,
  );

  AppSettingsEntity copyWith({
    String? parlourName,
    String? ownerName,
    String? ownerPhone,
    String? currencySymbol,
    bool? notificationsEnabled,
  }) {
    return AppSettingsEntity(
      parlourName: parlourName ?? this.parlourName,
      ownerName: ownerName ?? this.ownerName,
      ownerPhone: ownerPhone ?? this.ownerPhone,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettingsEntity &&
          runtimeType == other.runtimeType &&
          parlourName == other.parlourName &&
          ownerName == other.ownerName &&
          ownerPhone == other.ownerPhone &&
          currencySymbol == other.currencySymbol &&
          notificationsEnabled == other.notificationsEnabled;

  @override
  int get hashCode =>
      Object.hash(parlourName, ownerName, ownerPhone, currencySymbol, notificationsEnabled);

  @override
  String toString() => 'AppSettingsEntity(parlourName: $parlourName, ownerName: $ownerName)';
}
