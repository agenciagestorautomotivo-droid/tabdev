#!/usr/bin/env bash
# Cria o projeto Flutter "notia" e copia os arquivos deste pacote por cima.
# Uso: bash setup.sh   (rode dentro da pasta onde este setup.sh está)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."

flutter create notia --org com.notia.os --platforms android
cd notia

flutter pub add webview_flutter 'installed_apps:^1.6.0' shared_preferences http \
  speech_to_text flutter_tts sqflite connectivity_plus 'permission_handler:^11.3.1' 'flutter_secure_storage:^9.2.2' math_expressions \
  supabase_flutter audioplayers path_provider 'google_sign_in:^6.2.2' url_launcher \
  'flutter_contacts:^1.1.9' geolocator battery_plus image_picker google_mlkit_text_recognition \
  'local_auth:^2.3.0'

rm -f test/widget_test.test.dart test/widget_test.dart
rm -rf lib
cp -r "$HERE/lib" ./lib

MAIN=android/app/src/main
cp "$HERE/$MAIN/AndroidManifest.xml" "$MAIN/AndroidManifest.xml"
mkdir -p "$MAIN/kotlin/com/notia/os/notia"
rm -f "$MAIN/kotlin/com/notia/os/notia/MainActivity.kt"
cp "$HERE/$MAIN/kotlin/com/notia/os/notia/"*.kt "$MAIN/kotlin/com/notia/os/notia/"
# Recursos Android (configuração do serviço de acessibilidade, textos, ícone do atalho)
mkdir -p "$MAIN/res"
cp -r "$HERE/$MAIN/res/"* "$MAIN/res/"

# ML Kit (OCR) e geolocalização pedem Android 6+; o tablet é Android 13, então 26 é seguro.
for f in android/app/build.gradle.kts android/app/build.gradle; do
  [ -f "$f" ] && sed -i -E 's/minSdk(Version)?( =|) +flutter\.minSdkVersion/minSdk = 26/' "$f" || true
done
# Sem R8: o ML Kit referencia classes de idiomas que não estão no app e o R8 falharia.
f=android/app/build.gradle.kts
[ -f "$f" ] && sed -i 's/signingConfig = signingConfigs.getByName("debug")/signingConfig = signingConfigs.getByName("debug")\n            isMinifyEnabled = false\n            isShrinkResources = false/' "$f" || true

# local_auth (biometria) exige um tema AppCompat.
for f in "$MAIN/res/values/styles.xml" "$MAIN/res/values-night/styles.xml"; do
  [ -f "$f" ] && sed -i -E 's#parent="@android:style/Theme\.(Light|Black)\.NoTitleBar"#parent="Theme.AppCompat.NoActionBar"#' "$f" || true
done

echo "Pronto. Agora: cd notia && flutter pub get && flutter run   (ou: flutter build apk --release)"
