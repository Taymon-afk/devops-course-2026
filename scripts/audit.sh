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

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
