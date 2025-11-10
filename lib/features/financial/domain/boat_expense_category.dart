enum BoatExpenseCategory {
  maintenance('manutencao', 'Manutenção'),
  document('documento', 'Documento'),
  marina('marina', 'Marina'),
  fuel('combustivel', 'Combustível'),
  accessories('acessorios', 'Acessórios'),
  other('outros', 'Outros');

  const BoatExpenseCategory(this.value, this.label);

  final String value;
  final String label;

  static BoatExpenseCategory fromValue(String? value) {
    return values.firstWhere(
      (item) => item.value == value,
      orElse: () => BoatExpenseCategory.other,
    );
  }

  static BoatExpenseCategory? maybeFromValue(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return values.firstWhere(
      (item) => item.value == value,
      orElse: () => BoatExpenseCategory.other,
    );
  }
}
