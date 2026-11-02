# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины

- VirtualBox, Ubuntu Server 24.04.5 LTS, 64-bit.
- Оперативная память: 2048 МБ.
- Процессоры: 2.
- Диск: 25 ГБ, VDI.
- EFI отключён.
- Установочный ISO после установки извлечён.

## 2. Сетевые интерфейсы

| Интерфейс | Режим | IPv4 | Назначение |
|---|---|---|---|
| enp0s3 | NAT | 10.0.2.15/24 | Интернет и SSH через проброс портов |
| enp0s8 | Host-only | 192.168.56.101/24 | Прямой доступ с Windows |

Host-only адаптер: VirtualBox Host-Only Ethernet Adapter.
Адрес Windows в этой сети: 192.168.56.1.
Оба интерфейса получают адреса по DHCP.

Проверка адресов в Ubuntu:

```bash
ip -brief address
```

Имя машины и полное доменное имя:

```bash
sudo hostnamectl set-hostname devops-vm
sudo sed -i 's/^127.0.1.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
hostname -f
```

Ожидаемый результат: devops-vm.devops.local.

На Windows в файл C:\Windows\System32\drivers\etc\hosts добавлена строка:

```text
192.168.56.101 devops.local
```

Проверка из PowerShell:

```powershell
ping -n 1 devops.local
```

Если DHCP выдаст другой адрес Host-only, запись в hosts нужно обновить.

## 3. Правило проброса портов

VirtualBox → Настроить → Сеть → Адаптер 1 → Проброс портов.

| Поле | Значение после настройки |
|---|---|
| Имя | ssh |
| Протокол | TCP |
| Адрес хоста | 127.0.0.1 |
| Порт хоста | 2222 |
| Адрес гостя | пусто |
| Порт гостя | 2222 |

В снимке 01-clean-install порт гостя равен 22.
После переноса SSH на порт 2222 нужно изменить порт гостя в правиле на 2222.
Порт хоста остаётся 2222.

## 4. Учётные записи

- student — исходная учётная запись с sudo. Используется для первоначальной настройки и локальной консоли.
- devops — рабочая учётная запись, группы devops, sudo и users.
- SSH-вход разрешён только пользователю devops, по отдельному ключу Ed25519.
- Для sudo используется пароль devops. Пароли в документе не хранятся.

После отката на 01-clean-install подключиться из PowerShell:

```powershell
ssh student@127.0.0.1 -p 2222
```

Создать пользователя в Ubuntu:

```bash
sudo adduser devops
sudo usermod -aG sudo devops
id devops
```

Ключи уже созданы на Windows:

- закрытый: C:\Users\Artmb\.ssh\devops_vm
- открытый: C:\Users\Artmb\.ssh\devops_vm.pub

При восстановлении используется существующая пара.
Закрытый ключ остаётся на Windows.

Скопировать открытый ключ из PowerShell:

```powershell
scp -P 2222 "$env:USERPROFILE\.ssh\devops_vm.pub" student@127.0.0.1:/tmp/devops_vm.pub
```

Установить ключ в Ubuntu под student:

```bash
sudo install -d -m 700 -o devops -g devops /home/devops/.ssh
sudo install -m 600 -o devops -g devops /tmp/devops_vm.pub /home/devops/.ssh/authorized_keys
sudo stat -c '%a %n' /home/devops/.ssh /home/devops/.ssh/authorized_keys
```

Ожидаемые права: 700 для папки и 600 для authorized_keys.

Проверить вход из PowerShell:

```powershell
ssh -i "$env:USERPROFILE\.ssh\devops_vm" -p 2222 devops@127.0.0.1
```

Вход должен происходить без запроса пароля пользователя.

## 5. Служба SSH

Основной файл /etc/ssh/sshd_config сохранён без изменений.
Резервная копия: /etc/ssh/sshd_config.backup.

Файл /etc/ssh/sshd_config.d/99-hardening.conf:

```text
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

Для восстановления сначала сохранить исходный файл:

```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
sudo nano /etc/ssh/sshd_config.d/99-hardening.conf
```

Вставить приведённые выше параметры и сохранить файл.

В /etc/ssh/sshd_config.d/50-cloud-init.conf строка должна быть закомментирована:

```text
#PasswordAuthentication yes
```

Без этого файл 50-cloud-init.conf разрешает парольный вход раньше, чем читается 99-hardening.conf.

Проверить конфигурацию до перезапуска:

```bash
sudo sshd -t
sudo sshd -T | grep -Ei '^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers) '
```

Ожидается:

```text
port 2222
maxauthtries 3
permitrootlogin no
passwordauthentication no
allowusers devops
```

В Ubuntu 24.04 отключена активация SSH через сокет и включена обычная служба:

```bash
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh.service
sudo ss -tlnp | grep sshd
```

SSH должен слушать 0.0.0.0:2222 и [::]:2222.

После этого изменить порт гостя в пробросе VirtualBox с 22 на 2222.
Действующее SSH-соединение сохранять открытым до проверки нового входа в отдельной вкладке.

На Windows файл C:\Users\Artmb\.ssh\config содержит:

```text
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes

Host devops.local
    HostName devops.local
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

Файл называется config, без расширения .txt.

Отпечаток ключа сервера Ed25519:

```text
SHA256:58sFmT/WyQLeC8AA+GPP66sOtn/IS8fTyb+E3lotchY
```

Команды проверки из PowerShell:

```powershell
ssh devops
ssh devops.local
ssh -p 2222 root@127.0.0.1
ssh -p 2222 -o PubkeyAuthentication=no devops@127.0.0.1
```

Первые две команды должны подключаться по ключу.
Последние две должны завершаться отказом Permission denied (publickey).

Просмотр записей журнала в Ubuntu:

```bash
sudo journalctl -u ssh --since "10 min ago" --no-pager | grep -Ei 'not allowed|invalid|failed|denied|preauth'
```

## 6. Правила межсетевого экрана

UFW включён, автоматически запускается вместе с системой.

- Входящий трафик по умолчанию: deny.
- Исходящий трафик по умолчанию: allow.
- 2222/tcp: LIMIT IN, SSH.
- 80/tcp: ALLOW IN, HTTP.
- 443/tcp: ALLOW IN, HTTPS.
- Правила действуют для IPv4 и IPv6.
- Уровень журналирования: medium.

Команды восстановления конечных правил:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw --force enable
sudo ufw logging medium
sudo ufw status verbose
```

Разрешение SSH создаётся до включения UFW.
В работе сначала использовалось ALLOW для 2222/tcp, затем оно было заменено на LIMIT.
Параметр --force позволяет включить UFW без интерактивного подтверждения.

После включения проверить новое SSH-соединение в отдельной вкладке.

Проверка закрытого порта из PowerShell:

```powershell
curl.exe -m 3 http://192.168.56.101:8080
```

Ожидается тайм-аут.

Просмотр блокировок в Ubuntu:

```bash
sudo grep 'UFW BLOCK' /var/log/ufw.log | tail -5
```

В проверенной записи:

- SRC=192.168.56.1 — Windows.
- DST=192.168.56.101 — Ubuntu.
- PROTO=TCP — протокол.
- DPT=8080 — заблокированный порт назначения.

## 7. Снимки состояния

| Снимок | Момент создания |
|---|---|
| 01-clean-install | Ubuntu установлена и обновлена, сеть настроена, выполнен первый SSH-вход |
| 02-keys-configured | Создан devops с sudo, настроены ключ и команда ssh devops |
| 03-ssh-hardened | SSH перенесён на 2222, отключён парольный вход и проверены запреты |

После снимка 03-ssh-hardened дополнительно настроены UFW и доменное имя.

Скрипт проверки хранится в scripts/audit.sh.
При правильной конфигурации проходят 6 проверок, код возврата равен 0.
При временной замене MaxAuthTries 3 на MaxAuthTries 10 одна проверка завершается ошибкой, код возврата равен 1.
После проверки значение 3 восстановлено, синтаксис SSH проверен, аудит снова возвращает 0.
