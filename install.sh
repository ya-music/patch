#!/usr/bin/env bash
# Накатывает патчи из patched/ на оригинальную Яндекс Музыку и ставит копию в ~/Applications.
set -euo pipefail

cd "$(dirname "$0")"
SRC="${SRC:-/Applications/Yandex Music.app}"
DST="${DST:-$HOME/Applications/Yandex Music.app}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[ -d "$SRC" ] || { echo "Не найдено оригинальное приложение: $SRC" >&2; exit 1; }
command -v node >/dev/null || { echo "Нужен Node.js (https://nodejs.org)" >&2; exit 1; }

echo "→ Зависимости"
(cd tools && npm install --silent)
ASAR="$PWD/tools/node_modules/.bin/asar"

echo "→ Копия приложения в $DST"
pkill -f "$DST" 2>/dev/null || true
mkdir -p "$(dirname "$DST")"
rm -rf "$DST"
ditto "$SRC" "$DST"

echo "→ Распаковка и патчи"
"$ASAR" extract "$SRC/Contents/Resources/app.asar" "$TMP/work"
while IFS= read -r f; do
  [ -e "$TMP/work/$f" ] || echo "  пропущен (нет в этой версии): $f"
done < <(cd patched && find . -type f -not -path '*/.omc/*' | sed 's|^\./||')
rsync -a --existing --exclude '.omc' patched/ "$TMP/work/"

echo "→ Упаковка"
"$ASAR" pack "$TMP/work" "$TMP/new.asar" --unpack-dir "{node_modules/**}"

echo "→ Подмена asar и контрольной суммы"
OLD=$(node tools/asar-hash.mjs "$DST/Contents/Resources/app.asar")
NEW=$(node tools/asar-hash.mjs "$TMP/new.asar")
cp "$TMP/new.asar" "$DST/Contents/Resources/app.asar"
sed -i '' "s/$OLD/$NEW/" "$DST/Contents/Info.plist"
codesign --force --deep -s - "$DST"

echo "Готово. Запуск:"
echo "  nohup \"$DST/Contents/MacOS/\"* >/dev/null 2>&1 &"
