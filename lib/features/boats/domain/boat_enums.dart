enum BoatPropulsionType {
  vela('vela', 'À vela'),
  remo('remo', 'A remo'),
  mecanica('mecanica', 'Com propulsão mecânica'),
  semPropulsao('sem_propulsao', 'Sem propulsão');

  const BoatPropulsionType(this.value, this.label);

  final String value;
  final String label;

  static BoatPropulsionType fromValue(String? value) {
    for (final type in BoatPropulsionType.values) {
      if (type.value == value) {
        return type;
      }
    }
    return BoatPropulsionType.semPropulsao;
  }
}

extension BoatPropulsionTypeX on BoatPropulsionType {
  bool get requiresEngineDetails => this == BoatPropulsionType.mecanica;
}

enum BoatUsageType {
  esporteRecreio('esporte_recreio', 'Esporte e recreio'),
  comercial('comercial', 'Comercial'),
  pesca('pesca', 'Pesca'),
  militarNaval('militar_naval', 'Militar/Naval'),
  servicoPublico('servico_publico', 'Serviço público');

  const BoatUsageType(this.value, this.label);

  final String value;
  final String label;

  static BoatUsageType fromValue(String? value) {
    for (final type in BoatUsageType.values) {
      if (type.value == value) {
        return type;
      }
    }
    return BoatUsageType.esporteRecreio;
  }
}

enum BoatSize {
  miuda('miuda', 'Miúda'),
  medioPorte('medio', 'Médio porte'),
  grandePorte('grande', 'Grande porte');

  const BoatSize(this.value, this.label);

  final String value;
  final String label;

  static BoatSize fromValue(String? value) {
    for (final size in BoatSize.values) {
      if (size.value == value) {
        return size;
      }
    }
    return BoatSize.miuda;
  }
}
