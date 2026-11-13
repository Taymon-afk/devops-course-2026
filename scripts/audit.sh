#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "[OK] $desc"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] $desc (ожидалось: $expected, получено: $actual)"
        FAIL=$((FAIL + 1))
    fi
}

sudo -v || exit 1
ssh_config=$(sudo /usr/sbin/sshd -T) || exit 1
ufw_status=$(sudo env LC_ALL=C /usr/sbin/ufw status verbose) || exit 1

ssh_value() {
    awk -v name="$1" '$1 == name {print $2; exit}' <<< "$ssh_config"
}

echo "Аудит конфигурации: $(hostname -f)"

echo "[1] Служба SSH"
check "Вход под root запрещён" "no" "$(ssh_value permitrootlogin)"
check "Парольный вход отключён" "no" "$(ssh_value passwordauthentication)"

port_ok=$(awk '
    $1 == "port" {found=1; if ($2 == 22) bad=1}
    END {print (found && !bad) ? "yes" : "no"}
' <<< "$ssh_config")

check "Порт SSH отличается от 22" "yes" "$port_ok"
check "MaxAuthTries равен 3" "3" "$(ssh_value maxauthtries)"

echo "[2] Межсетевой экран"
check "UFW активен" "active" "$(awk '/^Status:/ {print $2}' <<< "$ufw_status")"
check "Входящие соединения по умолчанию запрещены" "deny" "$(awk '/^Default:/ {print $2}' <<< "$ufw_status")"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "  %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер"

result() {
    if "$@" > /dev/null 2>&1; then
        echo yes
    else
        echo no
    fi
}

CERT_MIN_DAYS="${CERT_MIN_DAYS:-30}"
[[ "$CERT_MIN_DAYS" =~ ^[0-9]+$ ]] || exit 1

check "Nginx активен" "yes" \
    "$(result systemctl is-active --quiet nginx)"

check "Конфигурация Nginx корректна" "yes" \
    "$(result sudo /usr/sbin/nginx -t)"

check "Сертификат действует ещё минимум ${CERT_MIN_DAYS} дней" "yes" \
    "$(result openssl x509 -in /etc/ssl/certs/devops.crt -noout -checkend "$((CERT_MIN_DAYS * 86400))")"

permissions_ok=no
if writable=$(find /var/www/devops-site -perm -o+w -print) &&
   key_mode=$(sudo stat -c '%a:%U' /etc/ssl/private/devops.key) &&
   [[ -z "$writable" && "$key_mode" == "600:root" ]]; then
    permissions_ok=yes
fi

check "Нет записи для всех, ключ имеет права 600 и владельца root" \
    "yes" "$permissions_ok"
echo "[5] Контейнеризация"

check "Docker активен" "yes" \
    "$(result systemctl is-active --quiet docker)"

db_health=$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null || true)
check "База данных healthy" "healthy" "$db_health"

ports_ok=$(ss -tln | awk '
    $4 ~ /:(5000|5432)$/ && $4 !~ /^127\.0\.0\.1:/ {bad=1}
    END {print bad ? "no" : "yes"}
')
check "Порты контейнеров закрыты для внешней сети" "yes" "$ports_ok"

env_mode=$(stat -c '%a' "$HOME/app/.env" 2>/dev/null || true)
check "Права файла .env равны 600" "600" "$env_mode"
echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
