#!/bin/sh

USB_PATH=$(ls -d /mnt/usb-* 2>/dev/null | head -n 1)
V2RAYA_DIR="$USB_PATH/v2raya"
LOG_FILE="/tmp/v2raya_install.log"
FINAL_LOG="$V2RAYA_DIR/v2raya_install_final.log"
STARTUP_DIR="/data/v2raya"
STARTUP_FILE="$STARTUP_DIR/startup_v2raya.sh"
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

fetch_versions() {
    log "Получение информации о последних версиях..." "info"
    XRAY_TAG=$(curl -k -s -I "https://github.com/frogost/v2raya_xiaomi/releases/latest" | grep -Fi 'Location:' | grep -o 'tag/[^[:space:]\r]*' | cut -d'/' -f2)
    V2RAYA_LATEST_NAME=$(curl -s http://bin.entware.net/aarch64-k3.10/ | grep -o 'v2raya_[^"]*\.ipk' | tail -n 1)

    if [ -z "$XRAY_TAG" ] || [ -z "$V2RAYA_LATEST_NAME" ]; then
        log "Не удалось получить версии пакетов. Проверьте подключение к интернету." "err"
        exit 1
    fi
}

do_startup() {
    # Запускаем в фоне, чтобы не блокировать процессы OpenWrt
    {
        sleep 30
        
        # Отключение сетевого ускорителя (критично для tproxy)
        /etc/init.d/qca-nss-ecm stop >/dev/null 2>&1
        /etc/init.d/qca-nss-ecm disable >/dev/null 2>&1
        
        # Отключаем ipv6
        sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1
        sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1
        
        # Находим флешку, копируем службу и запускаем
        CURRENT_USB=$(ls -d /mnt/usb-* 2>/dev/null | head -n 1)
        if [ -n "$CURRENT_USB" ] && [ -f "$CURRENT_USB/v2raya/etc/init.d/v2raya" ]; then
            cp -p -f "$CURRENT_USB/v2raya/etc/init.d/v2raya" /etc/init.d/v2raya
            /etc/init.d/v2raya enable
            /etc/init.d/v2raya start 
        fi
    } &
}

update_v2raya() {
    echo "=== Запуск обновления V2raya и ядра Xray ==="

    log "Завершение открытых процессов v2raya" "info"
    /etc/init.d/v2raya stop 2>/dev/null
    killall v2raya v2ray 2>/dev/null
    sleep 2
    
    log "Создание временной папки" "info"
    mkdir -p "$V2RAYA_DIR/tmp" || { log "Диск защищен от записи!" "err" ; exit 1; }
    
    fetch_versions
    
    log "Найдена версия v2raya: $V2RAYA_LATEST_NAME, скачиваем..." "info"
    curl -L -k -s "http://bin.entware.net/aarch64-k3.10/$V2RAYA_LATEST_NAME" -o "$V2RAYA_DIR/tmp/v2raya.ipk"
    
    if [ ! -f "$V2RAYA_DIR/tmp/v2raya.ipk" ]; then
        log "Не удалось скачать v2raya. Проверьте интернет." "err"
        exit 1
    fi
    
    log "Распаковка пакета v2raya..." "info"
    cd "$V2RAYA_DIR/tmp" || exit 1
    tar -zxf v2raya.ipk 2>/dev/null || tar -xf v2raya.ipk 2>/dev/null
    if [ -f "data.tar.gz" ]; then
        tar -zxf data.tar.gz
        if [ -f "./opt/bin/v2raya" ]; then
            mv "./opt/bin/v2raya" "$V2RAYA_DIR/usr/bin/v2raya"
        fi
    fi
    log "v2raya обновлена" "ok"
    
    log "Найдена версия: Xray $XRAY_TAG, скачиваем..." "info"
    curl -L -k -s "https://github.com/frogost/v2raya_xiaomi/releases/download/$XRAY_TAG/Xray-linux-arm64-v8a.tgz" -o "$V2RAYA_DIR/tmp/xray.tgz"
    
    log "Распаковка архива Xray..." "info"
    tar -zxf "$V2RAYA_DIR/tmp/xray.tgz" -C "$V2RAYA_DIR/tmp/"
    
    if [ -f "$V2RAYA_DIR/tmp/xray" ]; then
        mv "$V2RAYA_DIR/tmp/xray" "$V2RAYA_DIR/usr/bin/v2ray"
    fi
    
    if [ ! -f "$V2RAYA_DIR/usr/bin/v2ray" ]; then
        log "Ошибка: Файл xray не найден внутри архива!" "err"
        exit 1
    fi

    log "Удаление временных файлов" "info"
    rm -rf "$V2RAYA_DIR/tmp"

    log "Даем права на выполнение v2raya и ядра" "info" 
    chmod +x "$V2RAYA_DIR/usr/bin/v2raya"
    chmod +x "$V2RAYA_DIR/usr/bin/v2ray"
    
    log "Обновление V2raya и ядра Xray успешно" "ok"
    
    log "Запуск службы..." "info"
    /etc/init.d/v2raya start
    echo "================================"
}

install_v2raya() {
    echo "=== Запуск установки V2raya ==="
    
    if [ -z "$USB_PATH" ]; then
        log "USB накопитель не найден в /mnt/" "err"
        exit 1
    fi
    log "Используем накопитель: $USB_PATH" "info"
    
    mkdir -p "$V2RAYA_DIR" || { log "Диск защищен от записи!" "err" ; exit 1; }
    
    log "Создание рабочих папок" "info"
    mkdir -p "$V2RAYA_DIR/tmp"
    mkdir -p "$V2RAYA_DIR/usr/bin"
    mkdir -p "$V2RAYA_DIR/usr/share"
    mkdir -p "$V2RAYA_DIR/config"
    mkdir -p "$STARTUP_DIR"

    fetch_versions
    
    log "Скачивание v2raya ($V2RAYA_LATEST_NAME)..." "info"
    curl -L -k -s "http://bin.entware.net/aarch64-k3.10/$V2RAYA_LATEST_NAME" -o "$V2RAYA_DIR/tmp/v2raya.ipk"
    
    if [ ! -f "$V2RAYA_DIR/tmp/v2raya.ipk" ]; then
        log "Не удалось скачать v2raya. Проверьте интернет." "err"
        exit 1
    fi
    
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
    
    log "Скачивание ядра Xray ($XRAY_TAG)..." "info"
    curl -L -k -s "https://github.com/frogost/v2raya_xiaomi/releases/download/$XRAY_TAG/Xray-linux-arm64-v8a.tgz" -o "$V2RAYA_DIR/tmp/xray.tgz"
    
    log "Распаковка архива Xray..." "info"
    tar -zxf "$V2RAYA_DIR/tmp/xray.tgz" -C "$V2RAYA_DIR/tmp/"
    
    if [ -f "$V2RAYA_DIR/tmp/xray" ]; then
        mv "$V2RAYA_DIR/tmp/xray" "$V2RAYA_DIR/usr/bin/v2ray"
    fi
    
    if [ ! -f "$V2RAYA_DIR/usr/bin/v2ray" ]; then
        log "Ошибка: Файл xray не найден внутри архива!" "err"
        exit 1
    fi

    log "Удаление временных файлов" "info"
    rm -rf "$V2RAYA_DIR/tmp"
    
    chmod +x "$V2RAYA_DIR/usr/bin/v2raya"
    chmod +x "$V2RAYA_DIR/usr/bin/v2ray"
    
    log "Создаем конфиг службы v2raya" "info"
    mkdir -p "$STARTUP_DIR/etc/init.d"
    
    cat << 'EOF' > "$STARTUP_DIR/etc/init.d/v2raya"
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
    chmod +x "$STARTUP_DIR/etc/init.d/v2raya"
    
    log "Создание бэкапа firewall" "info"
    cp "$FIREWALL_CONFIG" "$FIREWALL_CONFIG.backup"
    
    log "Настраиваем firewall через UCI" "info"
    uci -q set firewall.@defaults[0].syn_flood='0'
    uci -q set firewall.@defaults[0].input='ACCEPT'
    uci -q set firewall.@defaults[0].output='ACCEPT'
    uci -q set firewall.@defaults[0].forward='ACCEPT'
    uci -q set firewall.@defaults[0].drop_invalid='1'
    uci -q set firewall.@defaults[0].fw_enable='1'
    uci -q set firewall.@defaults[0].port_trigger='1'
    uci -q set firewall.@defaults[0].disable_ipv6='1'
    
    uci -q delete firewall.startup_v2raya
    uci set firewall.startup_v2raya=include
    uci set firewall.startup_v2raya.type='script'
    uci set firewall.startup_v2raya.path="$STARTUP_FILE"
    uci set firewall.startup_v2raya.enabled='1'
    uci commit firewall
    
    log "Копирование скрипта-установщика для автозапуска" "info"
    cp "$0" "$STARTUP_FILE"
    chmod +x "$STARTUP_FILE"

    log "Первичный запуск службы..." "info"
    sh "$STARTUP_FILE" startup
    
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
    
    # Возвращаем работу ускорителя ECM при удалении
    /etc/init.d/qca-nss-ecm enable 2>/dev/null
    /etc/init.d/qca-nss-ecm start 2>/dev/null
    
    log "v2raya полностью удалена" "ok"
    echo "================================"
}

# Меню выбора действий
case "$1" in
    "install")
        install_v2raya
        ;;
    "uninstall")
        uninstall_v2raya
        ;;
    "update")
        update_v2raya
        ;;
    "startup"|"")
        do_startup
        ;;
    *)
        echo "Использование: $0 {install|uninstall|update|startup}"
        exit 1
        ;;
esac
