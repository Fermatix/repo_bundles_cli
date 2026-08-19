#!/usr/bin/env bash
#
# make_bundles.sh — выгружает список git-репозиториев в полные bundle-файлы.
#
# Каждый репозиторий клонируется зеркалом (--mirror: все ветки + теги),
# упаковывается в один .bundle (git bundle create --all) и проверяется
# (git bundle verify). Имя файла = namespace репозитория (org__name.bundle).
#
# Использование:
#   ./make_bundles.sh urls.txt [output_dir]
#   ./make_bundles.sh <(echo https://gitlab.com/org/repo.git)
#
#   urls.txt — по одному URL репозитория на строку.
#              Пустые строки и строки, начинающиеся с #, игнорируются.
#   output_dir — куда складывать .bundle (по умолчанию: ./bundles).
#
# Поддерживаются https:// и ssh (git@host:org/repo.git) ссылки.

set -euo pipefail

URLS_FILE="${1:-}"
OUT_DIR="${2:-./bundles}"

if [ -z "$URLS_FILE" ] || [ ! -r "$URLS_FILE" ]; then
  echo "Использование: $0 <файл-со-списком-url> [каталог-вывода]" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# URL -> имя bundle: убираем схему/.git/user@, host:path -> host/path,
# отбрасываем host, namespace соединяем через "__".
bundle_name() {
  local url="$1"
  url="${url%.git}"      # отрезать .git
  url="${url%/}"         # отрезать хвостовой /
  url="${url#*://}"      # отрезать схему https:// / ssh://
  url="${url#*@}"        # отрезать user@ (ssh)
  url="${url/:/\/}"      # host:org/repo -> host/org/repo
  local path="${url#*/}" # отбросить host -> org/.../repo
  echo "$path" | tr '/' '_'
}

ok=0; fail=0; total=0
while IFS= read -r url || [ -n "$url" ]; do
  url="$(echo "$url" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [ -z "$url" ] && continue
  case "$url" in \#*) continue;; esac

  total=$((total+1))
  name="$(bundle_name "$url")"
  bundle="$OUT_DIR/$name.bundle"
  mirror="$WORK/$name.git"

  echo "==> [$total] $url"
  echo "    -> $bundle"

  abs_bundle="$(readlink -f "$bundle" 2>/dev/null || echo "$bundle")"
  if git clone --mirror --quiet "$url" "$mirror" \
     && git -C "$mirror" bundle create "$abs_bundle" --all \
     && git -C "$mirror" bundle verify "$abs_bundle" >/dev/null 2>&1; then
    echo "    OK ($(du -h "$bundle" | cut -f1))"
    ok=$((ok+1))
  else
    echo "    ОШИБКА — пропущено" >&2
    fail=$((fail+1))
  fi
  rm -rf "$mirror"
done < "$URLS_FILE"

echo
echo "Готово: успешно $ok из $total (ошибок: $fail). Каталог: $OUT_DIR"
[ "$fail" -eq 0 ]
