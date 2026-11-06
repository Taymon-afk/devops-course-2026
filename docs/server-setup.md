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
| pr5-before-pr6 | Полная настройка ПР5 перед проверкой восстановления, включая UFW и FQDN |
| 04-nginx-https | После восстановления ПР5 установлен Nginx, настроены HTTPS и перенаправление с HTTP |

После снимка 03-ssh-hardened дополнительно настроены UFW и доменное имя.

Скрипт проверки хранится в scripts/audit.sh.
В версии ПР5 при правильной конфигурации проходят 6 проверок, код возврата равен 0.
При временной замене MaxAuthTries 3 на MaxAuthTries 10 одна проверка завершается ошибкой, код возврата равен 1.
После проверки значение 3 восстановлено, синтаксис SSH проверен, аудит снова возвращает 0.

## 8. Веб-сервер

### Установка и каталог сайта

На сервере установлены nginx, openssl и rsync:

```bash
sudo apt update
sudo apt install -y nginx openssl rsync
sudo install -d -m 755 -o devops -g devops /var/www/devops-site
```

Каталог сайта: /var/www/devops-site. Владелец каталога и файлов — devops:devops.
Права каталогов — 755, файлов — 644. Рабочие процессы Nginx работают от www-data:
они читают содержимое, но не могут его изменять. Главный процесс работает от root.
Исходники главной страницы и страницы ошибки находятся в site/index.html и site/404.html.

### Сертификат и закрытый ключ

Самоподписанный сертификат выпускается на 365 дней для имени devops.local.
Команда для восстановления на чистой машине:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"
sudo chown root:root /etc/ssl/private/devops.key /etc/ssl/certs/devops.crt
sudo chmod 600 /etc/ssl/private/devops.key
sudo chmod 644 /etc/ssl/certs/devops.crt
```

Закрытый ключ остаётся только на сервере и не добавляется в Git.
Главный процесс Nginx читает его от root; www-data доступа к ключу не имеет.
Сертификат — открытый файл, его можно скопировать клиенту через проверенное SSH-соединение.
При замене сертификата ранее скопированную клиентскую копию тоже нужно обновить.

### Конфигурация ресурса

Файл /etc/nginx/sites-available/devops-site:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name devops.local;

    access_log /var/log/nginx/devops-site.access.log;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name devops.local;

    ssl_certificate /etc/ssl/certs/devops.crt;
    ssl_certificate_key /etc/ssl/private/devops.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    root /var/www/devops-site;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    error_page 404 /404.html;
    access_log /var/log/nginx/devops-site.access.log;
    error_log /var/log/nginx/devops-site.error.log;
}
```

Активация конфигурации и отключение стандартного ресурса:

```bash
sudo ln -sfn /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/devops-site
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl enable --now nginx && sudo systemctl reload nginx
sudo ss -tlnp | grep nginx
```

Стандартный файл /etc/nginx/sites-available/default сохраняется: удаляется только ссылка.
Правила UFW для 80/tcp и 443/tcp уже созданы в разделе 6; добавлять дублирующий профиль Nginx Full не нужно.
Для сайта используется Host-only адрес 192.168.56.101, а не проброс HTTP/HTTPS через NAT.
HSTS на учебном сайте не включён.

### Клиент Windows и WSL

Для rsync используется Ubuntu в WSL версии 1. Проверка из PowerShell: wsl -l -v.
Сам веб-сервер работает в VirtualBox, а WSL используется как клиент.
В WSL установлены git, rsync, curl и openssl. Ключ devops_vm, SSH-конфигурация и known_hosts
скопированы из C:\Users\Artmb\.ssh в /home/artmb/.ssh.
Каталог .ssh имеет права 700, закрытый ключ и файл config — 600.

Репозиторий в WSL расположен по пути:

```text
/mnt/c/Users/Artmb/OneDrive/Рабочий стол/девопс/devops-course-2026
```

При работе Windows Git и WSL Git с одной папкой применены локальные настройки:

```bash
git config core.fileMode false
git config core.autocrlf true
```

Первая настройка убирает ложные изменения исполняемых битов на /mnt/c,
вторая согласует обработку CRLF с Windows Git. В .gitattributes для *.sh задано text eol=lf.
Реальные изменения по-прежнему видны в git status.

Вход и получение сертификата выполняются из WSL:

```bash
ssh devops
# После выхода из SSH, в WSL:
scp devops:/etc/ssl/certs/devops.crt ~/devops.crt
curl --noproxy devops.local --cacert ~/devops.crt -I https://devops.local/
```

Файл ~/devops.crt хранится в домашнем каталоге WSL /home/artmb.
Для локального имени явно используется --noproxy devops.local, поскольку на Windows настроен прокси.
Проверка с --cacert проходит без -k. Предупреждение браузера о самоподписанном сертификате ожидаемо:
в curl доверие задано явно, в системное хранилище браузера сертификат не импортировался.

### Доставка содержимого

Первую новую команду синхронизации с --delete проверяют с --dry-run:

```bash
rsync -avz --delete --chmod=D755,F644 --dry-run site/ devops:/var/www/devops-site/
rsync -avz --delete --chmod=D755,F644 site/ devops:/var/www/devops-site/
```

Завершающий / у site/ означает передачу его содержимого.
Нормализация прав обязательна: на /mnt/c исходные файлы видны с правами 777.

Штатный сценарий — scripts/deploy.sh. Он запускается из любого каталога репозитория,
проверяет наличие index.html и чистоту рабочей копии, включая индекс и неотслеживаемые файлы.
За запуск открывается одно SSH-соединение rsync; BatchMode=yes запрещает запрос пароля,
ConnectTimeout ограничивает ожидание подключения. Затем curl проверяет HTTPS с ~/devops.crt.
Успех возвращает 0 и короткий хеш коммита, ошибка — 1.

```bash
scripts/deploy.sh --dry-run
scripts/deploy.sh
echo $?
```

При --dry-run передача и проверка доступности не выполняются: выводится только план rsync.
Любые изменения самого скрипта и документации тоже надо закоммитить перед штатным деплоем.

Подтверждены пять сценариев:

| Условие | Результат |
|---|---|
| --dry-run | План операций, код 0 |
| Изменение страницы закоммичено | Страница обновлена, код 0; проверен запуск из docs |
| Изменение не закоммичено | Отказ до передачи, код 1 |
| Nginx остановлен | Передача выполнена, HTTPS-проверка не пройдена, код 1; служба затем запущена |
| index.html переименован с коммитом | Отказ до передачи, код 1; имя восстановлено отдельным коммитом |

### Проверка и диагностика

На сервере:

```bash
sudo nginx -t
ps -o user,pid,ppid,cmd -C nginx
namei -l /var/www/devops-site/index.html
find /var/www/devops-site -perm -o+w
sudo stat -c '%a %U:%G %n' /etc/ssl/private/devops.key
sudo tail -n 10 /var/log/nginx/devops-site.access.log
sudo tail -n 10 /var/log/nginx/devops-site.error.log
sudo awk '{print $9}' /var/log/nginx/devops-site.access.log | sort | uniq -c | sort -rn
```

В WSL:

```bash
curl --noproxy devops.local -I http://devops.local/
curl --noproxy devops.local --cacert ~/devops.crt -I https://devops.local/
curl --noproxy devops.local --cacert ~/devops.crt -I https://devops.local/no-such-page
openssl s_client -connect devops.local:443 -servername devops.local </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```

Ожидаемые ответы: HTTP — 301 с Location на HTTPS, главная по HTTPS — 200, неизвестная страница — 404.
Журнал запросов задаётся и для HTTP-блока, поэтому перенаправления тоже попадают в журнал сайта.
В успешной проверке использовался TLS 1.3, поле SAN содержало DNS:devops.local.

При правах index.html 600 получен 403 и open() ... failed (13: Permission denied).
Для каталога проверены 755 → 200, 750 → 403, 744 → 403, 711 → 200.
При недостатке прав на каталоге в error.log записано is forbidden (13: Permission denied).
У каталога 711 есть проход x, но нет чтения списка r; у 744 список виден, но прохода нет.

Доставка без --chmod перенесла права 777: www-data смог подменить index.html.
Штатный deploy.sh восстановил содержимое и права; find после восстановления ничего не вывел,
попытка touch от www-data завершилась Permission denied.

### Расширенный аудит

В scripts/audit.sh добавлен раздел [4] Веб-сервер: состояние Nginx, синтаксис конфигурации,
оставшийся срок сертификата и совместная проверка прав сайта и ключа.
Для ключа проверяются права 600 и владелец root; файлов и каталогов с записью для всех быть не должно.
Всего проходят 10 проверок, итоговый код — 0.

На сервере проверен порог 400 дней при сертификате на 365 дней:

```bash
CERT_MIN_DAYS=400 bash ~/pr5/scripts/audit.sh
echo $?
```

Ожидается одна ошибка и код 1. Изменяется только порог проверки, сертификат не перевыпускается.
Также проверено временное chmod 666 для index.html: одна ошибка, код 1.
Права восстановлены в 644, после чего снова получены 10 успешных проверок и код 0.

Рабочая серверная копия аудита — ~/pr5/scripts/audit.sh. При изменении репозиторной версии обновить её из WSL:

```bash
scp scripts/audit.sh devops:pr5/scripts/audit.sh
```
