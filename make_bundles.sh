#!/usr/bin/env bash
#
# make_bundles.sh — выгружает список репозиториев (git и mercurial) в bundle-файлы.
#
# Каждый репозиторий клонируется целиком (все ветки/теги), упаковывается в один
# файл и проверяется. Git -> <namespace>.bundle (git bundle create --all),
# Mercurial -> <namespace>.hgbundle (hg bundle --all).
#
# Для git дополнительно забираются рефы ревью: refs/merge-requests/* (GitLab) и
# refs/pull/* (GitHub). Сервер их не анонсирует, поэтому --mirror сам по себе их
# не тянет — и коммиты незамерженных MR/PR в bundle не попадают.
# Отключить: HIDDEN_REFS=0 ./make_bundles.sh repos.txt
#
# Использование:
#   ./make_bundles.sh repos.txt [output_dir]
#   ./make_bundles.sh <(echo https://gitlab.com/org/repo.git)
#
#   repos.txt  — по одному URL репозитория на строку.
#                Пустые строки и строки, начинающиеся с #, игнорируются.
#   output_dir — куда складывать bundle-файлы (по умолчанию: ./bundles).
#
# Поддерживаются https:// и ssh (git@host:org/repo.git) ссылки.
#
# VCS определяется по ссылке (как в repo_metadata_cli):
#   - префикс hg+<url> / git+<url> — явное указание, приоритетнее всего;
#   - суффикс .git — git;
#   - известные hg-хосты (hg.*, *heptapod*, mercurial-scm.org) — mercurial;
#   - всё остальное — git.
# Для mercurial нужна команда hg (pip install mercurial).

set -euo pipefail

URLS_FILE="${1:-}"
OUT_DIR="${2:-./bundles}"
HIDDEN_REFS="${HIDDEN_REFS:-1}"   # забирать ли refs/merge-requests/* и refs/pull/*

if [ -z "$URLS_FILE" ] || [ ! -r "$URLS_FILE" ]; then
  echo "Использование: $0 <файл-со-списком-url> [каталог-вывода]" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"   # абсолютный путь: bundle создаётся из каталога клона
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export HGPLAIN=1            # стабильный вывод hg без алиасов и пейджера
export GIT_TERMINAL_PROMPT=0

# Убрать префикс схемы hg+ / git+.
strip_scheme() {
  local url="$1"
  case "$url" in
    hg+*|HG+*|Hg+*)   echo "${url#*+}";;
    git+*|GIT+*|Git+*) echo "${url#*+}";;
    *) echo "$url";;
  esac
}

# URL -> "git" | "hg".
detect_vcs() {
  local url="$1"
  case "$url" in
    hg+*|HG+*|Hg+*)    echo hg;  return;;
    git+*|GIT+*|Git+*) echo git; return;;
  esac
  local u="${url%/}"
  case "$u" in *.git|*.GIT) echo git; return;; esac
  # хост: отрезать схему и user@, взять до первого / или :
  local host="${u#*://}"; host="${host#*@}"; host="${host%%[/:]*}"
  host="$(echo "$host" | tr 'A-Z' 'a-z')"
  case "$host" in
    hg.*|*heptapod*|mercurial-scm.org|*.mercurial-scm.org) echo hg;;
    *) echo git;;
  esac
}

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

# Дотянуть рефы ревью в готовое зеркало и напечатать, сколько их набралось.
# Пространства имён нет — не ошибка: fetch просто вернёт ненулевой код.
fetch_hidden_refs() {
  local mirror="$1" ns count=0 got
  for ns in merge-requests pull; do
    git -C "$mirror" fetch --quiet --force origin "+refs/$ns/*:refs/$ns/*" 2>/dev/null || continue
    got="$(git -C "$mirror" for-each-ref --format='.' "refs/$ns" | wc -l | tr -d ' ')"
    count=$((count + got))
  done
  echo "$count"
}

HG_MISSING_WARNED=0
ok=0; fail=0; total=0
while IFS= read -r url || [ -n "$url" ]; do
  url="$(echo "$url" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [ -z "$url" ] && continue
  case "$url" in \#*) continue;; esac

  total=$((total+1))
  vcs="$(detect_vcs "$url")"
  bare="$(strip_scheme "$url")"
  name="$(bundle_name "$bare")"

  if [ "$vcs" = hg ]; then
    bundle="$OUT_DIR/$name.hgbundle"
  else
    bundle="$OUT_DIR/$name.bundle"
  fi
  mirror="$WORK/$name.$vcs"

  echo "==> [$total] ($vcs) $bare"
  echo "    -> $bundle"

  if [ "$vcs" = hg ]; then
    if ! command -v hg >/dev/null 2>&1; then
      if [ "$HG_MISSING_WARNED" -eq 0 ]; then
        echo "    Не найден hg — клиент Mercurial. Установите: pip install mercurial" >&2
        HG_MISSING_WARNED=1
      fi
      echo "    ОШИБКА — пропущено (нет hg)" >&2
      fail=$((fail+1))
      continue
    fi
    # hg bundle --all завершается ошибкой на пустом репозитории ("no changes found").
    if hg clone -U -q "$bare" "$mirror" \
       && hg -R "$mirror" bundle --all -q "$bundle" \
       && hg -R "$mirror" debugbundle "$bundle" >/dev/null 2>&1; then
      echo "    OK ($(du -h "$bundle" | cut -f1))"
      ok=$((ok+1))
    else
      echo "    ОШИБКА — пропущено" >&2
      fail=$((fail+1))
    fi
  else
    hidden=0; cloned=0
    if git clone --mirror --quiet "$bare" "$mirror"; then
      cloned=1
      if [ "$HIDDEN_REFS" != 0 ]; then
        hidden="$(fetch_hidden_refs "$mirror")"
      fi
    fi
    if [ "$cloned" -eq 1 ] \
       && git -C "$mirror" bundle create "$bundle" --all \
       && git -C "$mirror" bundle verify "$bundle" >/dev/null 2>&1; then
      note=""
      [ "$hidden" -gt 0 ] && note=", рефов ревью: $hidden"
      echo "    OK ($(du -h "$bundle" | cut -f1)$note)"
      ok=$((ok+1))
    else
      echo "    ОШИБКА — пропущено" >&2
      fail=$((fail+1))
    fi
  fi
  rm -rf "$mirror"
done < "$URLS_FILE"

echo
echo "Готово: успешно $ok из $total (ошибок: $fail). Каталог: $OUT_DIR"
[ "$fail" -eq 0 ]
