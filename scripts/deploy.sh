#!/usr/bin/env bash
set -euo pipefail

fail() {
    printf 'Ошибка: %s\n' "$*" >&2
    exit 1
}

DRY_RUN=0
if [[ $# -gt 0 ]]; then
    [[ $# -eq 1 && "$1" == "--dry-run" ]] ||
        fail "Использование: deploy.sh [--dry-run]"
    DRY_RUN=1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
LOCAL_DIR="$ROOT/site/"
REMOTE="devops"
REMOTE_DIR="/var/www/devops-site/"
SITE_URL="https://devops.local/"
CA_CERT="$HOME/devops.crt"

[[ -f "${LOCAL_DIR}index.html" ]] ||
    fail "Отсутствует site/index.html"

[[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=all)" ]] ||
    fail "Есть незафиксированные изменения. Сначала сделайте коммит."

COMMIT="$(git -C "$ROOT" rev-parse --short HEAD)"

if [[ "$DRY_RUN" -eq 0 ]]; then
    [[ -r "$CA_CERT" ]] || fail "Не найден сертификат $CA_CERT"
fi

OPTIONS=(-avz --delete --chmod=D755,F644)
if [[ "$DRY_RUN" -eq 1 ]]; then
    OPTIONS+=(--dry-run)
fi

if ! rsync "${OPTIONS[@]}" \
    -e "ssh -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1" \
    "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}"; then
    fail "Передать файлы не удалось"
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "Пробный запуск завершён. Файлы сервера не изменены."
    exit 0
fi

if ! curl --noproxy devops.local --fail --silent --show-error \
    --connect-timeout 5 --max-time 10 \
    --cacert "$CA_CERT" --output /dev/null "$SITE_URL"; then
    fail "Файлы переданы, но проверка HTTPS не пройдена"
fi

printf 'Деплой выполнен. Коммит: %s\n' "$COMMIT"
