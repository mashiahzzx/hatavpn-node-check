#!/bin/bash
# ╔══════════════════════════════════════════════════╗
#   HataVPN Node Quality Checker v2.0
#   Универсальная проверка VPN-ноды (любая локация)
#   Запуск:
#   bash <(curl -sL https://raw.githubusercontent.com/mashiahzzx/hatavpn-node-check/main/hatavpn-check.sh)
# ╚══════════════════════════════════════════════════╝

# ── Цвета ──────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

OK="${GREEN}✅${NC}"
WARN="${YELLOW}⚠️ ${NC}"
FAIL="${RED}❌${NC}"
INFO="${CYAN}ℹ️ ${NC}"

# ── Счётчики и причины ─────────────────────────────
ISSUES=0
WARNINGS=0
FAIL_REASONS=()
WARN_REASONS=()
REPORT_LINES=()

check_pass() {
    echo -e "  ${OK}  $1"
    CLEAN=$(echo "$1" | sed 's/\x1b\[[0-9;]*m//g')
    REPORT_LINES+=("✅ $CLEAN")
}
check_warn() {
    echo -e "  ${WARN} $1"
    ((WARNINGS++))
    WARN_REASONS+=("$1")
    CLEAN=$(echo "$1" | sed 's/\x1b\[[0-9;]*m//g')
    REPORT_LINES+=("⚠️  $CLEAN")
}
check_fail() {
    echo -e "  ${FAIL}  $1"
    ((ISSUES++))
    FAIL_REASONS+=("$1")
    CLEAN=$(echo "$1" | sed 's/\x1b\[[0-9;]*m//g')
    REPORT_LINES+=("❌ $CLEAN")
}
check_info() {
    echo -e "  ${INFO}  $1"
    CLEAN=$(echo "$1" | sed 's/\x1b\[[0-9;]*m//g')
    REPORT_LINES+=("ℹ️  $CLEAN")
}

print_section() {
    echo ""
    echo -e "${BOLD}${CYAN}[$1] $2${NC}"
    echo -e "${DIM}──────────────────────────────────────────────────${NC}"
    REPORT_LINES+=("")
    REPORT_LINES+=("[$1] $2")
    REPORT_LINES+=("──────────────────────────────────────────────────")
}

REPORT_FILE="/tmp/hatavpn-node-report-$(date +%Y%m%d-%H%M%S).txt"
START_TIME=$(date +%s)

# ══════════════════════════════════════════════════
# ШАПКА
# ══════════════════════════════════════════════════
clear
echo ""
echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║       HataVPN Node Quality Checker  v2.0        ║${NC}"
echo -e "${BOLD}${BLUE}║      Универсальная проверка VPN-ноды             ║${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo -e "  ${DIM}Время: $(date '+%Y-%m-%d %H:%M:%S UTC')${NC}"
echo -e "  ${DIM}Хост:  $(hostname)${NC}"
echo ""

REPORT_LINES+=("HataVPN Node Quality Checker v2.0")
REPORT_LINES+=("Время: $(date '+%Y-%m-%d %H:%M:%S UTC')")
REPORT_LINES+=("Хост:  $(hostname)")

# ══════════════════════════════════════════════════
# 1. БАЗОВАЯ ИНФОРМАЦИЯ
# ══════════════════════════════════════════════════
print_section "1/7" "Базовая информация о сервере"

CPU_MODEL=$(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
CPU_CORES=$(nproc)
CPU_MHZ=$(grep 'cpu MHz' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs | cut -d. -f1)
RAM_TOTAL=$(free -h | awk '/Mem:/ {print $2}')
RAM_FREE=$(free -h | awk '/Mem:/ {print $7}')
RAM_TOTAL_MB=$(free -m | awk '/Mem:/ {print $2}')
DISK_FREE=$(df -h / | awk 'NR==2 {print $4}')
DISK_USED_PCT=$(df / | awk 'NR==2 {print $5}')
OS_NAME=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')
KERNEL=$(uname -r)
UPTIME_STR=$(uptime -p 2>/dev/null || uptime)
VIRT=$(systemd-detect-virt 2>/dev/null || echo "unknown")
LOAD=$(uptime | awk -F'load average:' '{print $2}' | xargs)
LOAD_1=$(uptime | awk -F'load average:' '{print $2}' | cut -d, -f1 | xargs)

check_info "CPU:      ${BOLD}$CPU_MODEL${NC}"
check_info "Ядра:     ${BOLD}${CPU_CORES} vCPU @ ${CPU_MHZ} MHz${NC}"
check_info "RAM:      ${BOLD}$RAM_TOTAL total / $RAM_FREE free${NC}"
check_info "Диск:     ${BOLD}$DISK_FREE free ($DISK_USED_PCT занято)${NC}"
check_info "ОС:       ${BOLD}$OS_NAME${NC}"
check_info "Ядро:     ${BOLD}$KERNEL${NC}"
check_info "Вирт:     ${BOLD}$VIRT${NC}"
check_info "Uptime:   ${BOLD}$UPTIME_STR${NC}"
check_info "LA:       ${BOLD}$LOAD${NC}"

# Проверка ОС
if echo "$OS_NAME" | grep -qE 'Ubuntu 2[24]'; then
    check_pass "ОС актуальная: $OS_NAME"
elif echo "$OS_NAME" | grep -qiE 'debian 1[12]|ubuntu'; then
    check_warn "Рекомендуется Ubuntu 22.04/24.04, у вас: $OS_NAME"
else
    check_warn "Нестандартная ОС: $OS_NAME — рекомендуется Ubuntu 22.04/24.04"
fi

# Проверка RAM
if [ "$RAM_TOTAL_MB" -ge 3800 ] 2>/dev/null; then
    check_pass "RAM достаточно: $RAM_TOTAL"
elif [ "$RAM_TOTAL_MB" -ge 1800 ] 2>/dev/null; then
    check_warn "RAM минимальная: $RAM_TOTAL — при большой нагрузке может не хватить"
else
    check_fail "RAM критически мало: $RAM_TOTAL — Xray + система не поместятся комфортно"
fi

# Проверка нагрузки
LOAD_INT=$(echo "$LOAD_1" | cut -d. -f1)
if [ "$LOAD_INT" -ge "$CPU_CORES" ] 2>/dev/null; then
    check_warn "Высокая нагрузка (LA: $LOAD_1) — сервер уже чем-то занят"
else
    check_pass "Нагрузка в норме (LA: $LOAD_1)"
fi

# Проверка диска
DISK_USED_NUM=$(echo "$DISK_USED_PCT" | tr -d '%')
if [ "$DISK_USED_NUM" -lt 70 ] 2>/dev/null; then
    check_pass "Диска достаточно: $DISK_FREE свободно"
elif [ "$DISK_USED_NUM" -lt 90 ] 2>/dev/null; then
    check_warn "Диск заполнен на $DISK_USED_PCT — следи за логами"
else
    check_fail "Диск почти полный ($DISK_USED_PCT) — освободи место перед установкой"
fi

# ══════════════════════════════════════════════════
# 2. СЕТЬ И ГЕОЛОКАЦИЯ
# ══════════════════════════════════════════════════
print_section "2/7" "Сеть и геолокация"

IPV4=$(curl -s4 --max-time 5 ifconfig.me 2>/dev/null)
IPV6=$(curl -s6 --max-time 5 ifconfig.me 2>/dev/null)

if [ -n "$IPV4" ]; then
    check_info "IPv4: ${BOLD}$IPV4${NC}"
    GEO=$(curl -s --max-time 5 "http://ip-api.com/json/$IPV4" 2>/dev/null)
    COUNTRY=$(echo $GEO | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("country","?"))' 2>/dev/null)
    COUNTRY_CODE=$(echo $GEO | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("countryCode","?"))' 2>/dev/null)
    CITY=$(echo $GEO | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("city","?"))' 2>/dev/null)
    ISP=$(echo $GEO | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("isp","?"))' 2>/dev/null)
    ASN=$(echo $GEO | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("as","?"))' 2>/dev/null)

    check_info "Страна:  ${BOLD}$COUNTRY ($COUNTRY_CODE)${NC}"
    check_info "Город:   ${BOLD}$CITY${NC}"
    check_info "ISP:     ${BOLD}$ISP${NC}"
    check_info "ASN:     ${BOLD}$ASN${NC}"

    if [ -n "$COUNTRY_CODE" ] && [ "$COUNTRY_CODE" != "?" ]; then
        check_pass "Геолокация определена: $CITY, $COUNTRY"
    else
        check_warn "Не удалось определить геолокацию IP"
    fi

    # Российский IP — бессмысленно для VPN
    if [ "$COUNTRY_CODE" = "RU" ]; then
        check_fail "IP российский — VPN-нода в РФ бессмысленна для обхода блокировок"
    fi
else
    check_fail "IPv4 недоступен — критическая проблема"
fi

if [ -n "$IPV6" ]; then
    check_pass "IPv6 доступен: $IPV6"
else
    check_info "IPv6 недоступен (не критично для VLESS+Reality)"
fi

# ══════════════════════════════════════════════════
# 3. КРИТИЧЕСКИЕ ПАРАМЕТРЫ ДЛЯ XRAY
# ══════════════════════════════════════════════════
print_section "3/7" "Критические параметры для Xray / VLESS+Reality"

# AES-NI
if grep -q 'aes' /proc/cpuinfo; then
    check_pass "AES-NI включён — аппаратное шифрование активно"
else
    check_fail "AES-NI ОТКЛЮЧЁН — Xray будет работать медленно, нода не подходит"
fi

# BBR
BBR=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
if [ "$BBR" = "bbr" ]; then
    check_pass "BBR включён — оптимальная работа на нестабильных каналах"
else
    check_warn "BBR выключен (текущий: $BBR) — включить: echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.conf && sysctl -p"
fi

# TUN/TAP
if [ -e /dev/net/tun ]; then
    check_pass "TUN/TAP доступен"
else
    check_warn "TUN/TAP недоступен — WireGuard/AmneziaWG не поднять"
fi

# Частота CPU
if [ -n "$CPU_MHZ" ] && [ "$CPU_MHZ" -gt 3800 ] 2>/dev/null; then
    check_pass "Частота CPU: ${CPU_MHZ} MHz — отлично для Xray"
elif [ -n "$CPU_MHZ" ] && [ "$CPU_MHZ" -gt 2500 ] 2>/dev/null; then
    check_warn "Частота CPU: ${CPU_MHZ} MHz — приемлемо, но не идеально для Xray"
else
    check_fail "Частота CPU: ${CPU_MHZ} MHz — низкая, Xray будет тормозить"
fi

# ══════════════════════════════════════════════════
# 4. ТЕСТ CPU — AES-256-GCM
# ══════════════════════════════════════════════════
print_section "4/7" "Тест CPU — скорость шифрования AES-256-GCM (как Xray)"

if command -v openssl &>/dev/null; then
    check_info "Запускаю 3-секундный тест..."

    # Ubuntu 24.04 изменил формат вывода openssl speed
    # Пробуем несколько вариантов парсинга
    AES_RAW=$(openssl speed -elapsed -seconds 3 aes-256-gcm 2>&1)

    # Вариант 1: старый формат — последнее число в строке aes-256-gcm
    AES_RESULT=$(echo "$AES_RAW" | grep -i 'aes-256-gcm' | grep -v '^#' | awk '{print $NF}' | grep -oP '[0-9]+\.[0-9]+' | tail -1)

    # Вариант 2: новый формат Ubuntu 24.04 — ищем строку с числом байт
    if [ -z "$AES_RESULT" ] || [ "$AES_RESULT" = "0" ]; then
        AES_RESULT=$(echo "$AES_RAW" | grep -i 'aes-256-gcm' | grep -oP '\d+\.\d+k' | tail -1 | tr -d 'k')
        [ -n "$AES_RESULT" ] && AES_RESULT=$(echo "$AES_RESULT" | awk '{print $1 * 1024}')
    fi

    # Вариант 3: ищем throughput напрямую
    if [ -z "$AES_RESULT" ] || [ "$AES_RESULT" = "0" ]; then
        AES_RESULT=$(echo "$AES_RAW" | grep -oP '[0-9]+\.[0-9]+[kmKM]?\s+bytes' | head -1 | awk '{print $1}')
    fi

    if [ -n "$AES_RESULT" ] && [ "$AES_RESULT" != "0" ]; then
        AES_MB=$(echo "$AES_RESULT" | awk '{print int($1/1024/1024)}')
        AES_GBIT=$(echo "$AES_RESULT" | awk '{printf "%.1f", $1/1024/1024/1024*8}')
        check_info "Результат: ${BOLD}${AES_MB} MB/s (~${AES_GBIT} Gbit/s)${NC}"

        if   [ "$AES_MB" -gt 8000 ] 2>/dev/null; then
            check_pass "Шифрование ${AES_MB} MB/s — топ, потянет 3000+ юзеров"
        elif [ "$AES_MB" -gt 5000 ] 2>/dev/null; then
            check_pass "Шифрование ${AES_MB} MB/s — отлично, до 2000 юзеров"
        elif [ "$AES_MB" -gt 2000 ] 2>/dev/null; then
            check_pass "Шифрование ${AES_MB} MB/s — хорошо, до 1000 юзеров"
        elif [ "$AES_MB" -gt 500 ]  2>/dev/null; then
            check_warn "Шифрование ${AES_MB} MB/s — приемлемо, до 200 юзеров"
        else
            check_fail "Шифрование ${AES_MB} MB/s — слишком медленно"
        fi
    else
        # Fallback: считаем через dd + openssl напрямую
        check_info "Альтернативный тест через dd+openssl..."
        DD_RESULT=$(dd if=/dev/zero bs=1M count=512 2>/dev/null | openssl enc -aes-256-cbc -pass pass:test -pbkdf2 2>/dev/null | wc -c)
        if [ -n "$DD_RESULT" ] && [ "$DD_RESULT" -gt 0 ] 2>/dev/null; then
            check_info "Шифрование работает (детальный бенчмарк недоступен)"
        else
            check_info "Тест шифрования пропущен — openssl установится с Xray автоматически"
        fi
    fi
else
    check_info "openssl не установлен — установится с Xray автоматически"
fi

# ══════════════════════════════════════════════════
# 5. СКОРОСТЬ ДИСКА, КАНАЛА И MTU
# ══════════════════════════════════════════════════
print_section "5/7" "Скорость диска, канала и MTU"

# Диск
if command -v dd &>/dev/null; then
    check_info "Тест записи на диск..."
    WRITE_SPEED=$(dd if=/dev/zero of=/tmp/hv_wr bs=64k count=4096 conv=fdatasync 2>&1 | grep -oP '[0-9.]+ [MGk]?B/s' | tail -1)
    rm -f /tmp/hv_wr

    check_info "Тест чтения с диска..."
    dd if=/dev/zero of=/tmp/hv_rd bs=64k count=4096 2>/dev/null
    READ_SPEED=$(dd if=/tmp/hv_rd of=/dev/null bs=64k 2>&1 | grep -oP '[0-9.]+ [MGk]?B/s' | tail -1)
    rm -f /tmp/hv_rd

    check_info "Запись: ${BOLD}${WRITE_SPEED:-н/д}${NC}  /  Чтение: ${BOLD}${READ_SPEED:-н/д}${NC}"

    if echo "$READ_SPEED" | grep -q 'GB/s'; then
        check_pass "Диск: $READ_SPEED — NVMe подтверждён"
    elif echo "$READ_SPEED" | grep -qP '^[5-9][0-9]{2}'; then
        check_pass "Диск: $READ_SPEED — хороший NVMe/SSD"
    elif [ -n "$READ_SPEED" ]; then
        check_warn "Диск медленный: $READ_SPEED (ожидается 500+ MB/s для NVMe)"
    fi
fi

# Канал — тест через несколько источников
check_info "Тест скорости канала (несколько серверов)..."

# Источники: европейский нейтральный + Яндекс CDN (РФ) + Cloudflare
declare -A SPEED_SOURCES=(
    ["Cloudflare EU"]="https://speed.cloudflare.com/__down?bytes=104857600"
    ["Yandex CDN (RU)"]="https://storage.yandexcloud.net/yandex-internet-speed-test/100mb.bin"
    ["Tele2 EU"]="http://speedtest.tele2.net/100MB.zip"
)

BEST_SPEED=0
BEST_NAME=""

for ENTRY in \
    "Cloudflare EU:https://speed.cloudflare.com/__down?bytes=104857600" \
    "Yandex CDN (RU):https://storage.yandexcloud.net/yandex-internet-speed-test/100mb.bin" \
    "Tele2 EU:http://speedtest.tele2.net/100MB.zip"
do
    SRC_NAME=$(echo "$ENTRY" | cut -d: -f1)
    SRC_URL=$(echo "$ENTRY" | cut -d: -f2-)

    check_info "  → $SRC_NAME..."
    RAW=$(curl -o /dev/null -s -w "%{speed_download}" \
        -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" \
        -L --max-time 20 "$SRC_URL" 2>/dev/null)
    if [ -n "$RAW" ] && [ "$RAW" != "0" ]; then
        MBIT=$(echo "$RAW" | awk '{printf "%.0f", $1/1024/1024*8}')
        if [ "$MBIT" -gt 0 ] 2>/dev/null; then
            check_info "    $SRC_NAME: ${BOLD}${MBIT} Mbit/s${NC}"
            REPORT_LINES+=("  $SRC_NAME: ${MBIT} Mbit/s")
            if [ "$MBIT" -gt "$BEST_SPEED" ] 2>/dev/null; then
                BEST_SPEED=$MBIT
                BEST_NAME=$SRC_NAME
            fi
        else
            check_info "    $SRC_NAME: сервер недоступен"
        fi
    else
        check_info "    $SRC_NAME: недоступен"
    fi
done

echo ""
if [ "$BEST_SPEED" -gt 0 ] 2>/dev/null; then
    check_info "Лучший результат: ${BOLD}${BEST_SPEED} Mbit/s${NC} (${BEST_NAME})"
    if   [ "$BEST_SPEED" -gt 700 ] 2>/dev/null; then
        check_pass "Канал: ${BEST_SPEED} Mbit/s — полноценный 1 Gbps ✓"
    elif [ "$BEST_SPEED" -gt 400 ] 2>/dev/null; then
        check_pass "Канал: ${BEST_SPEED} Mbit/s — хорошо"
    elif [ "$BEST_SPEED" -gt 100 ] 2>/dev/null; then
        check_warn "Канал: ${BEST_SPEED} Mbit/s — приемлемо, но не 1 Gbps"
    else
        check_warn "Канал: ${BEST_SPEED} Mbit/s — низкая скорость по всем серверам (может быть перегрузка, проверь позже)"
    fi
else
    check_warn "Не удалось замерить скорость канала ни с одного источника"
fi

# MTU
MTU=$(ip link show 2>/dev/null | grep -v 'lo:' | grep -oP 'mtu \K[0-9]+' | head -1)
if [ -n "$MTU" ]; then
    check_info "MTU сетевого интерфейса: ${BOLD}$MTU${NC}"
    if   [ "$MTU" -ge 1500 ] 2>/dev/null; then
        check_pass "MTU: $MTU — стандартный, фрагментации не будет"
    elif [ "$MTU" -ge 1400 ] 2>/dev/null; then
        check_warn "MTU: $MTU — немного занижен, VLESS может терять в скорости"
    else
        check_fail "MTU: $MTU — слишком низкий, серьёзная потеря скорости у пользователей"
    fi
fi

# ══════════════════════════════════════════════════
# 6. ПИНГ И ТРАССИРОВКА
# ══════════════════════════════════════════════════
print_section "6/7" "Пинг и трассировка маршрута"

for TARGET in "1.1.1.1:Cloudflare" "8.8.8.8:Google" "77.88.8.8:Яндекс" "195.34.53.71:MTS-RU"; do
    HOST=$(echo $TARGET | cut -d: -f1)
    NAME=$(echo $TARGET | cut -d: -f2)
    PING_MS=$(ping -c 4 -W 3 "$HOST" 2>/dev/null | tail -1 | awk -F'/' '{printf "%.1f", $5}')
    if [ -n "$PING_MS" ] && [[ "$PING_MS" =~ ^[0-9] ]]; then
        PING_INT=$(echo "$PING_MS" | cut -d. -f1)
        if   [ "$PING_INT" -lt 40  ] 2>/dev/null; then check_pass "$NAME ($HOST): ${BOLD}${PING_MS}ms${NC} — отлично"
        elif [ "$PING_INT" -lt 80  ] 2>/dev/null; then check_pass "$NAME ($HOST): ${BOLD}${PING_MS}ms${NC} — хорошо"
        elif [ "$PING_INT" -lt 150 ] 2>/dev/null; then check_warn "$NAME ($HOST): ${BOLD}${PING_MS}ms${NC} — приемлемо"
        else check_fail "$NAME ($HOST): ${BOLD}${PING_MS}ms${NC} — высокий пинг, пользователи заметят"
        fi
    else
        check_info "$NAME ($HOST): ICMP недоступен"
    fi
done

# Трассировка
echo ""
check_info "Трассировка до 8.8.8.8 (первые 8 хопов):"
if command -v traceroute &>/dev/null; then
    TRACE=$(traceroute -n -m 8 -w 2 8.8.8.8 2>/dev/null | tail -n +2)
elif command -v tracepath &>/dev/null; then
    TRACE=$(tracepath -n 8.8.8.8 2>/dev/null | head -10 | tail -n +2)
else
    TRACE="traceroute не найден — установи: apt-get install -y traceroute"
fi
while IFS= read -r line; do
    echo -e "     ${DIM}$line${NC}"
    REPORT_LINES+=("     $line")
done <<< "$TRACE"

# ══════════════════════════════════════════════════
# 7. BLACKLIST / DNSBL
# ══════════════════════════════════════════════════
print_section "7/7" "Проверка IP в чёрных списках (DNSBL)"

if [ -n "$IPV4" ]; then
    REVERSED_IP=$(echo "$IPV4" | awk -F. '{print $4"."$3"."$2"."$1}')
    check_info "Проверяю ${BOLD}$IPV4${NC} в DNSBL..."

    BLACKLISTED=0
    CLEAN_BL=0

    for ENTRY in \
        "Spamhaus ZEN:zen.spamhaus.org" \
        "Spamhaus SBL:sbl.spamhaus.org" \
        "Spamhaus XBL:xbl.spamhaus.org" \
        "Barracuda:b.barracudacentral.org" \
        "SpamCop:bl.spamcop.net" \
        "SORBS SPAM:spam.sorbs.net" \
        "UCEPROTECT L1:dnsbl-1.uceprotect.net"
    do
        NAME=$(echo $ENTRY | cut -d: -f1)
        BL=$(echo $ENTRY | cut -d: -f2)
        RESULT=$(host -t A "${REVERSED_IP}.${BL}" 2>/dev/null | grep 'has address')
        if [ -n "$RESULT" ]; then
            check_fail "В блэклисте: $NAME"
            ((BLACKLISTED++))
        else
            check_pass "Чист: $NAME"
            ((CLEAN_BL++))
        fi
    done

    echo ""
    check_info "Итог DNSBL: ${GREEN}${BOLD}$CLEAN_BL чист${NC} / ${RED}${BOLD}$BLACKLISTED в блэклисте${NC}"

    if   [ "$BLACKLISTED" -eq 0 ]; then
        check_pass "IP чистый — хорошая репутация"
    elif [ "$BLACKLISTED" -le 2 ]; then
        check_warn "IP в $BLACKLISTED базах — для VPN некритично, но лучше сменить IP"
    else
        check_fail "IP в $BLACKLISTED базах — плохая репутация, запроси новый IP у провайдера"
    fi

    PBL=$(host -t A "${REVERSED_IP}.pbl.spamhaus.org" 2>/dev/null | grep 'has address')
    [ -n "$PBL" ] && check_info "IP в Spamhaus PBL — норма для хостинга (не спам-список)"
else
    check_warn "IPv4 недоступен — пропускаю DNSBL"
fi

# ══════════════════════════════════════════════════
# ИТОГОВЫЙ ВЕРДИКТ
# ══════════════════════════════════════════════════
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║                 ИТОГОВЫЙ ВЕРДИКТ                ║${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Проверка заняла:       ${DIM}${ELAPSED} сек${NC}"
echo -e "  Критических проблем:   ${RED}${BOLD}$ISSUES${NC}"
echo -e "  Предупреждений:        ${YELLOW}${BOLD}$WARNINGS${NC}"
echo ""

REPORT_LINES+=("")
REPORT_LINES+=("══════════════════ ИТОГОВЫЙ ВЕРДИКТ ══════════════════")
REPORT_LINES+=("Время проверки: ${ELAPSED} сек | Проблем: $ISSUES | Предупреждений: $WARNINGS")

if [ "$ISSUES" -eq 0 ] && [ "$WARNINGS" -le 2 ]; then
    echo -e "  ${GREEN}${BOLD}🚀 НОДА ПОДХОДИТ ДЛЯ HATAVPN${NC}"
    echo -e "  ${GREEN}Подключай к Remnawave → VLESS + Reality + XHTTP${NC}"
    REPORT_LINES+=("ВЕРДИКТ: ✅ НОДА ПОДХОДИТ")

elif [ "$ISSUES" -eq 0 ]; then
    echo -e "  ${YELLOW}${BOLD}⚠️  НОДА УСЛОВНО ПОДХОДИТ${NC}"
    echo -e "  ${YELLOW}Устрани перед запуском:${NC}"
    echo ""
    for i in "${!WARN_REASONS[@]}"; do
        CLEAN=$(echo "${WARN_REASONS[$i]}" | sed 's/\x1b\[[0-9;]*m//g')
        echo -e "  ${YELLOW}  $((i+1)). $CLEAN${NC}"
        REPORT_LINES+=("  $((i+1)). $CLEAN")
    done
    REPORT_LINES+=("ВЕРДИКТ: ⚠️  УСЛОВНО ПОДХОДИТ")

else
    echo -e "  ${RED}${BOLD}❌ НОДА НЕ ПОДХОДИТ ДЛЯ HATAVPN${NC}"
    echo ""

    if [ "${#FAIL_REASONS[@]}" -gt 0 ]; then
        echo -e "  ${RED}${BOLD}Причины:${NC}"
        for i in "${!FAIL_REASONS[@]}"; do
            CLEAN=$(echo "${FAIL_REASONS[$i]}" | sed 's/\x1b\[[0-9;]*m//g')
            echo -e "  ${RED}  $((i+1)). $CLEAN${NC}"
            REPORT_LINES+=("  Причина $((i+1)): $CLEAN")
        done
    fi

    if [ "${#WARN_REASONS[@]}" -gt 0 ]; then
        echo ""
        echo -e "  ${YELLOW}Дополнительно:${NC}"
        for i in "${!WARN_REASONS[@]}"; do
            CLEAN=$(echo "${WARN_REASONS[$i]}" | sed 's/\x1b\[[0-9;]*m//g')
            echo -e "  ${YELLOW}  $((i+1)). $CLEAN${NC}"
        done
    fi

    echo ""
    echo -e "  ${RED}Смени ноду или устрани проблемы выше.${NC}"
    REPORT_LINES+=("ВЕРДИКТ: ❌ НЕ ПОДХОДИТ")
fi

# ══════════════════════════════════════════════════
# СОХРАНЕНИЕ ОТЧЁТА
# ══════════════════════════════════════════════════
{
    echo "=================================================="
    echo " HataVPN Node Quality Checker v2.0"
    echo " Дата:    $(date '+%Y-%m-%d %H:%M:%S UTC')"
    echo " IP:      ${IPV4:-н/д} | $CITY, $COUNTRY"
    echo " Хост:    $(hostname)"
    echo "=================================================="
    echo ""
    for line in "${REPORT_LINES[@]}"; do
        echo "$line"
    done
} > "$REPORT_FILE"

echo ""
echo -e "  ${CYAN}📄 Отчёт сохранён: ${BOLD}$REPORT_FILE${NC}"
echo -e "  ${DIM}Просмотр: cat $REPORT_FILE${NC}"
echo ""
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo ""
