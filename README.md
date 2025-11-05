# ZapNáutico

Aplicativo Flutter integrado ao Supabase para gerenciamento de cotas náuticas.

## Pré-requisitos

- Flutter 3.9.2 ou superior
- Conta no Supabase com URL e Anon Key configuradas em `--dart-define`

## Execução

### Mobile (Android/iOS)

```bash
flutter run
```

### Web (Chrome)

Use o script dedicado para garantir uma porta fixa e facilitar a autenticação:

```bash
./tool/run_web.sh
```

O script exporta `FLUTTER_WEB_PORT=5000` e `FLUTTER_WEB_HOSTNAME=localhost` antes de chamar `flutter run -d chrome`, mantendo a origem estável entre execuções.

## Configuração do Supabase

No dashboard do Supabase, acesse **Authentication → URL Configuration** e adicione:

- `http://localhost:5000` (para desenvolvimento web)
- `zapnautico://auth-callback` (para Android e iOS)

Esses valores devem corresponder aos parâmetros usados em `lib/core/app_config.dart`.
