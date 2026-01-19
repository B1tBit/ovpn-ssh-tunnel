# Обход блокировки OpenVPN
Перед использованием убедитесь, что у вас имеется арендованный VPS хост находящийся вне стран СНГ. В противном случаи вы не сможете воспользоваться этим руководством. Подходящий хост можете найти у популярных хостеров на примере ![Timeweb](https://timeweb.cloud/), ![Aeza](https://aeza.ru/) или ![VDSina](https://vdsina.ru/). Тариф стоит брать самый минимальный, поскольку кроме SSH нам ничего не нужно.

# Подготовка хоста
Требует минимальных усилий, для работы рекомендую использовать Ubuntu Server.
1. Обновите текущие пакеты: `sudo apt update && sudo apt upgrade`
2. Установка OpenSSH: `sudo apt install openssh-server `
3. Запуск сервера: `sudo systemctl enable --now ssh `
4. Оценка статуса: `sudo systemctl status ssh`
# Настройка входа
Здесь есть два пути: 
- Вход по паролю (*всегда указан в дашборде VPS*);
- Вход по ключу (*ниже я покажу как сделать аутентификацию по ключу*).
Для этой задачи в консоли требуется написать one-line:
```
ssh-keygen -a 1000 -b 4096 -o -t rsa && cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys && echo -e "SSH key for \e[1;32m$(hostname).key\e[0m:\n$(cat ~/.ssh/id_rsa)" && systemctl restart ssh
```
Созданный ключ будет лежать по пути **~/.ssh/authorized_keys**, его мы копируем и переносим на целевой хост, откуда будем работать (*также ключ подсветится после выполнения команды*). Остальное не трогаем и оставляем как есть.
# Обходим DPI ручным способом
Итак, на этом этапе в одной папке должно лежать два ключевых файла - это ключ от SSH (*если он есть*) и конфиг `.ovpn`, его мы берем с официального сайта **Hack The Box** или **TryHackMe**. Нас интересует конфиг, который работает на TCP (*443 порт*).
Теперь мы должны сделать прослушку SSH порта до нашего VPS сервера, для этого используем команды в соответствии с нашим положением:
- Авторизация по ключу: `sudo ssh -v -N -L local_port:ctf.server.name:443 -i locate_ssh.key user@ip_address`
- Авторизация по логину/паролю: `sudo ssh -v -N -L local_port:ctf.server.name:443 user@ip_address`

Здесь важно понимание локальных имен, где:
- **local_port**: локальный порт на вашем хосте, который будет поднят (*по дефолту можно использовать 1443*);
- **ctf.server.name**: домен CTF сервера который вы будете использовать (*содержится в конфиге, строка remote*);
- **user**: имя пользователя авторизованного по SSH;
- **ip_address**: IP адрес вашего удаленного VPS сервера.
Если при авторизации по ключу вы получаете ошибку OpenSSH в libcrypto, воспользуйтесь файлом **fixed_key.sh**, скачайте его в папку с ключом и выполните ряд команд:
```
sudo chmod +x fixed_key.sh
sudo ./fixed_key.sh
```
После повторно запустите команду и не закрывайте окно консоли, оно должно быть активно во всем процессе игры. Следующим этапом требуется отредактировать `.ovpn` конфиг, в нем требуется найти следующие строки:
```
remote ctf.server.name 443
proto tcp
```
Заменить на:
```
remote 127.0.0.1 local_port
proto tcp-client
```
После сохраняем и запускаем наш конфиг командой:
```
sudo openvpn config_name.ovpn
```
Где `config_name.ovpn` название вашего конфига. Окно терминала так же оставляем открытым и не трогаем, пока не закончим играть. Для проверки работоспособности рекомендую стартануть любую машинку и попытаться ее пропинговать, если пинг идет значит мы успешно справились с задачей. Как альтернатива проверки можно использовать команду `ifconfig interface` где **interface** название вашего виртуального сетевого интерфейса. Обычно в Linux он имеет идентификатор **tn0**. В выходящей строке вы должны увидеть значение RX не равное 0, если значение больше нуля, значит все работает, иначе вы сделали что-то не так и стоит вернуться к предыдущим действиям.

# Автоматизация обхода
Если геморроя слишком много, я оставил автоматизированный скрипт настройки `htb-ssh-ovpn-tunnel.sh`, для работы выполните ряд команд:
```
sudo chmod +x htb-ssh-ovpn-tunnel.sh
./htb-ssh-ovpn-tunnel.sh
```
Ниже оставил справку по работе со скриптом.
```
Usage:
  htb-ssh-ovpn-tunnel.sh --ovpn <file.ovpn> --lport <local_port> --ip <external_host_ip> --user <ssh_user> [--key <keyfile.key>] [--htb <htb_hostname>]

Arguments:
  --ovpn   Path to .ovpn config (required)
  --lport  Local port for SSH -L (required)
  --ip     External host IP (required)
  --user   SSH user on external host (required)
  --key    SSH private key filename or path (optional). If it's just a filename, it must sit next to this script.
  --htb    HTB server hostname (optional). If omitted, extracted from first 'remote <host> <port>' line in ovpn.

Behavior:
  - Creates patched ovpn: <name>.ovpn
  - Replaces first 'remote ...' with 'remote 127.0.0.1 <lport>'
  - Replaces/sets proto to 'proto tcp-client'
  - Starts SSH tunnel:
      sudo ssh -v -N -L <lport>:<htb_host>:443 [-i <key>] <user>@<ip>
```
Удачной охоты за флагами, пусть победит сильнейший!
