#!/usr/bin/env bash

set -euo pipefail

# Garante porta fixa para o servidor web do Flutter.
export FLUTTER_WEB_PORT=5000
export FLUTTER_WEB_HOSTNAME=localhost

echo "Iniciando Flutter Web em http://localhost:${FLUTTER_WEB_PORT}"
flutter run -d chrome "$@"
