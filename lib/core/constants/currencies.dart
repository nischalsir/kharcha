/// Supported currencies for the app.
///
/// The [code] is what is persisted in settings; [symbol] is what the
/// [CurrencyFormatter] renders in front of an amount, and [name] is the
/// human-readable label shown in the picker.
class CurrencyOption {
  const CurrencyOption(this.code, this.symbol, this.name);

  final String code;
  final String symbol;
  final String name;

  String get label => '$code  •  $name';
}

const List<CurrencyOption> kCurrencies = <CurrencyOption>[
  CurrencyOption('NPR', 'NPR', 'Nepalese Rupee'),
  CurrencyOption('INR', '₹', 'Indian Rupee'),
  CurrencyOption('USD', '\$', 'US Dollar'),
  CurrencyOption('EUR', '€', 'Euro'),
  CurrencyOption('GBP', '£', 'British Pound'),
  CurrencyOption('AED', 'AED', 'UAE Dirham'),
  CurrencyOption('SAR', 'SAR', 'Saudi Riyal'),
  CurrencyOption('QAR', 'QAR', 'Qatari Riyal'),
  CurrencyOption('AUD', 'A\$', 'Australian Dollar'),
  CurrencyOption('CAD', 'C\$', 'Canadian Dollar'),
  CurrencyOption('JPY', '¥', 'Japanese Yen'),
  CurrencyOption('CNY', '¥', 'Chinese Yuan'),
  CurrencyOption('KRW', '₩', 'South Korean Won'),
  CurrencyOption('MYR', 'RM', 'Malaysian Ringgit'),
];

CurrencyOption currencyFor(String code) {
  for (final option in kCurrencies) {
    if (option.code == code) return option;
  }
  return kCurrencies.first;
}

String currencySymbol(String code) => currencyFor(code).symbol;

String currencyLabel(String code) => currencyFor(code).label;
