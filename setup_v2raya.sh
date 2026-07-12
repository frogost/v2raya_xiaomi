#!/bin/sh

USB_PATH=$(ls -d /mnt/usb-* 2>/dev/null | head -n 1)
V2RAYA_DIR="$USB_PATH/v2raya"
LOG_FILE="/tmp/v2raya_install.log"
FINAL_LOG="$V2RAYA_DIR/v2raya_install_final.log"
STARTUP_DIR="/data/v2raya"
STARTUP_FILE="/data/v2raya/startup_v2raya.sh"
FIREWALL_CONFIG="/etc/config/firewall"

log() {
    local msg="$1"
    local type="$2"
    local timestamp=$(date '+%F %T')
    
    echo "[$timestamp] $msg" >> "$LOG_FILE"
    [ -d "$V2RAYA_DIR" ] && echo "[$timestamp] $msg" >> "$FINAL_LOG"

    case "$type" in
        "info") echo " -> $msg" ;;
        "err")  echo "[!] ОШИБКА: $msg" ;;
        "ok")   echo "[+] УСПЕХ: $msg" ;;
        *)      echo "$msg" ;;
    esac
}

startup_v2raya() {
    # Ожидание инициализации сети и накопителя
    sleep 30

    # Отключение сетевого ускорителя (критично для tproxy маршрутизации)
    /etc/init.d/qca-nss-ecm stop >/dev/null 2>&1
    /etc/init.d/qca-nss-ecm disable >/dev/null 2>&1

    # Отключаем ipv6
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1
    sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1

    # Копируем службу в системную директорию
    cp -p -f "$V2RAYA_DIR/etc/init.d/v2raya" /etc/init.d/v2raya
    
    # Запускаем службу
    /etc/init.d/v2raya enable
    /etc/init.d/v2raya start 
}

update_v2raya() {
	echo "=== Запуск обновления V2raya и ядра Xray ==="
	log "Создание временной папки" "info"
    mkdir -p "$V2RAYA_DIR/tmp" || { log "Диск защищен от записи!" "err" ; exit 1; }
	
    log "Поиск последней версии v2raya в репозитории..." "info"
	V2RAYA_LATEST_NAME=$(curl -s http://bin.entware.net/aarch64-k3.10/ | grep -o 'v2raya_[^"]*\.ipk' | tail -n 1)
	
	if [ -z "$V2RAYA_LATEST_NAME" ]; then
    	log "Не удалось определить имя последней версии v2raya!" "err"
    	exit 1
	fi
	
	log "Найдена версия: $V2RAYA_LATEST_NAME, скачиваем..." "info"
	curl -L -k -s "http://bin.entware.net/aarch64-k3.10/$V2RAYA_LATEST_NAME" -o "$V2RAYA_DIR/tmp/v2raya.ipk"
}

install_v2raya() {
    echo "=== Запуск установки V2raya ==="
    
    if [ -z "$USB_PATH" ]; then
        log "USB накопитель не найден в /mnt/" "err"
        exit 1
    fi
    log "Используем накопитель: $USB_PATH" "info"
    
    mkdir -p "$V2RAYA_DIR" || { log "Диск защищен от записи!" "err" ; exit 1; }
    
    log "Создание временной папки" "info"
    mkdir -p "$V2RAYA_DIR/tmp" || { log "Диск защищен от записи!" "err" ; exit 1; }
    
    log "Скачивание файла v2raya..." "info"
    curl -L -k -s http://bin.entware.net/aarch64-k3.10/v2raya_2.3.3-1_aarch64-3.10.ipk -o "$V2RAYA_DIR/tmp/v2raya.ipk"
    
    if [ ! -f "$V2RAYA_DIR/tmp/v2raya.ipk" ]; then
        log "Не удалось скачать v2raya. Проверьте интернет." "err"
        exit 1
    fi
    
    log "Создаем рабочие папки для v2raya" "info" 
    mkdir -p "$V2RAYA_DIR/usr/bin" || { log "Не удалось создать папку usr/bin" "err" ; exit 1; }
    mkdir -p "$V2RAYA_DIR/usr/share" || { log "Не удалось создать папку usr/share" "err" ; exit 1; }
    mkdir -p "$V2RAYA_DIR/config" || { log "Не удалось создать папку config" "err" ; exit 1; }
    
    log "Распаковка пакета v2raya..." "info"
    cd "$V2RAYA_DIR/tmp" || exit 1
    tar -zxf v2raya.ipk 2>/dev/null || tar -xf v2raya.ipk 2>/dev/null
    if [ -f "data.tar.gz" ]; then
        tar -zxf data.tar.gz
        if [ -f "./opt/bin/v2raya" ]; then
            mv "./opt/bin/v2raya" "$V2RAYA_DIR/usr/bin/v2raya"
        fi
    fi

    if [ ! -f "$V2RAYA_DIR/usr/bin/v2raya" ]; then
        log "Ошибка распаковки бинарника v2raya!" "err"
        exit 1
    fi
    
    log "Скачивание ядра Xray..." "info"
    curl -L -k -s https://raw.githubusercontent.com/frogost/v2raya_xiaomi/main/xray.tgz -o "$V2RAYA_DIR/tmp/xray.tgz"
    
    if [ ! -f "$V2RAYA_DIR/tmp/xray.tgz" ]; then
        log "Не удалось скачать Xray по ссылке. Проверьте интернет." "err"
        exit 1
    fi
    
    log "Распаковка архива Xray..." "info"
    tar -zxf "$V2RAYA_DIR/tmp/xray.tgz" -C "$V2RAYA_DIR/tmp/"
    
    if [ -f "$V2RAYA_DIR/tmp/xray" ]; then
        mv "$V2RAYA_DIR/tmp/xray" "$V2RAYA_DIR/usr/bin/v2ray"
    fi
	
    if [ ! -f "$V2RAYA_DIR/usr/bin/v2ray" ]; then
        log "Ошибка: Файл xray не найден внутри архива или не смог переместиться!" "err"
        exit 1
    fi

	log "Удаление временных файлов" "info"
    rm -rf "$V2RAYA_DIR/tmp"
	
    log "Даем права на выполнение v2raya и ядра" "info" 
    chmod +x "$V2RAYA_DIR/usr/bin/v2raya"
    chmod +x "$V2RAYA_DIR/usr/bin/v2ray"
    
    log "Создаем папки для конфигурации службы" "info"
    mkdir -p "$V2RAYA_DIR/etc/init.d" || { log "Не удалось создать /data/v2raya/etc/init.d" "err" ; exit 1; }
    
    log "Настраиваем службу v2raya" "info"
    cat << 'EOF' > "$V2RAYA_DIR/etc/init.d/v2raya"
#!/bin/sh /etc/rc.common

USE_PROCD=1
START=99

USB_PATH=$(ls -d /mnt/usb-* 2>/dev/null | head -n 1)
V2RAYA_DIR="$USB_PATH/v2raya"

PROG="$V2RAYA_DIR/usr/bin/v2raya"
V2RAY_BIN="$V2RAYA_DIR/usr/bin/v2ray"
ASSETS_DIR="$V2RAYA_DIR/usr/share"
CONFIG_DIR="$V2RAYA_DIR/config"
LOG_FILE="$V2RAYA_DIR/v2raya.log"

start_service() {
    [ ! -x "$PROG" ] && return 1

    procd_open_instance "v2raya"
    procd_set_param command "$PROG"
    
    procd_append_param command --v2ray-bin "$V2RAY_BIN"
    procd_append_param command --v2ray-assetsdir "$ASSETS_DIR"
    procd_append_param command --config "$CONFIG_DIR"
    procd_append_param command --log-file "$LOG_FILE"
    procd_append_param command --log-level "info"
    procd_append_param command --address "0.0.0.0:2017"
    procd_append_param command --ipv6-support "false"

    procd_set_param env V2RAY_CONF_GEOLOADER="memconservative"
    procd_set_param env XRAY_LOCATION_ASSET="$ASSETS_DIR"
    procd_set_param env GOGC=20
    procd_set_param env GOMEMLIMIT=180MiB
    procd_set_param env XDG_DATA_HOME="$ASSETS_DIR"
    
    procd_append_param env V2RAYA_V2RAY_BIN="$V2RAY_BIN"
    procd_append_param env V2RAYA_LOG_FILE="$LOG_FILE"
    procd_append_param env V2RAYA_CONFIG="$CONFIG_DIR"

    procd_set_param limits core="unlimited"
    procd_set_param limits nofile="1000000 1000000"

    procd_set_param stdout 0
    procd_set_param stderr 1 
    procd_set_param respawn
    
    procd_close_instance
}

stop_service() {
    killall v2raya 2>/dev/null
    killall v2ray 2>/dev/null
}

reload_service() {
    stop
    start
}
EOF
    
	log "Даем права службе на выполнение" "info"
  chmod +x "$V2RAYA_DIR/etc/init.d/v2raya"
    
    log "Создание бэкапа firewall" "info"
    cp "$FIREWALL_CONFIG" "$FIREWALL_CONFIG.backup"
    
    log "Настраиваем firewall" "info"
    TEMP_FILE=$(mktemp)
    IN_DEFAULTS_BLOCK=false
    
    while IFS= read -r line; do
        if echo "$line" | grep -q "^config defaults"; then
            IN_DEFAULTS_BLOCK=true
        elif echo "$line" | grep -q "^config " && [ "$IN_DEFAULTS_BLOCK" = true ]; then
            IN_DEFAULTS_BLOCK=false
        fi
        
        if [ "$IN_DEFAULTS_BLOCK" = true ]; then
            case "$line" in
                *option\ syn_flood*) echo "	option syn_flood '0'" >> "$TEMP_FILE" ;;
                *option\ input*) echo "	option input 'ACCEPT'" >> "$TEMP_FILE" ;;
                *option\ output*) echo "	option output 'ACCEPT'" >> "$TEMP_FILE" ;;
                *option\ forward*) echo "	option forward 'ACCEPT'" >> "$TEMP_FILE" ;;
                *option\ drop_invalid*) echo "	option drop_invalid '1'" >> "$TEMP_FILE" ;;
                *option\ fw_enable*) echo "	option fw_enable '1'" >> "$TEMP_FILE" ;;
                *option\ port_trigger*) echo "	option port_trigger '1'" >> "$TEMP_FILE" ;;
                *option\ disable_ipv6*) echo "	option disable_ipv6 '1'" >> "$TEMP_FILE" ;;
                *) echo "$line" >> "$TEMP_FILE" ;;
            esac
        else
            echo "$line" >> "$TEMP_FILE"
        fi
    done < "$FIREWALL_CONFIG"
    
    mv "$TEMP_FILE" "$FIREWALL_CONFIG"
    
    # Регистрация скрипта автозагрузки через uci
    uci -q delete firewall.startup_v2raya
    uci set firewall.startup_v2raya=include
    uci set firewall.startup_v2raya.type='script'
    uci set firewall.startup_v2raya.path="$STARTUP_FILE"
    uci set firewall.startup_v2raya.enabled='1'
    uci commit firewall
    
    log "Конфигурация firewall обновлена" "info"
    
    log "Запуск скрипта автозапуска..." "info"
    sh "$STARTUP_FILE"
    
    log "v2raya полностью установлена! Зайдите на веб http://(IP_РОУТЕРА):2017" "ok"
    echo "================================"
}

uninstall_v2raya() {
    echo "=== Запуск удаления v2raya ==="
    /etc/init.d/v2raya stop 2>/dev/null
    killall v2raya v2ray 2>/dev/null
    sleep 2
    
    uci -q delete firewall.startup_v2raya
    uci commit firewall
    
    rm -f /etc/init.d/v2raya
    rm -rf "$STARTUP_DIR"
    rm -rf "$V2RAYA_DIR"
    
    # Возвращаем работу ускорителя ECM при удалении (опционально)
    /etc/init.d/qca-nss-ecm enable 2>/dev/null
    /etc/init.d/qca-nss-ecm start 2>/dev/null
    
    echo "[+] v2raya полностью удалена."
    echo "================================"
}

# Меню выбора действий
case "$1" in
    "uninstall")
        uninstall_v2raya
        ;;
    *)
        install_v2raya
        ;;
esac
