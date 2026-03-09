#!/bin/bash
# ================================================
#         HataVPN Node Quality Checker
#         github.com/hatavpn/node-check
#         Версия: 1.0.0
# ================================================
# Запуск:
#   bash <(curl -sL https://raw.githubusercontent.com/USERNAME/REPO/main/check.sh)

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Иконки результата
OK="${GREEN}✅${NC}"
WARN="${YELLOW}⚠️ ${NC}"
FAIL="${RED}❌${NC}"
INFO="${CYAN}ℹ️ ${NC}"

# Счётчики и причины
ISSUES=0
WARNINGS=0
FAIL_REASONS=()
WARN_REASONS=()

print_header() {
    echo ""
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}        HataVPN Node Quality Checker v1.0         ${NC}"
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════${NC}"
    echo -e "  Время проверки: $(date '+%Y-%m-%d %H:%M:%S UTC')"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BOLD}${CYAN}[ $1 ] $2${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
}

check_pass()  { echo -e "  ${OK}  $1"; }
check_warn()  { echo -e "  ${WARN} $1"; ((WARNINGS++)); WARN_REASONS+=("$1"); }
check_fail()  { echo -e "  ${FAIL}  $1"; ((ISSUES++)); FAIL_REASONS+=("$1"); }
check_info()  { echo -e "  ${INFO}  $1"; }

# ──────────────────────────────────────────────────
# 1. БАЗОВАЯ ИНФОРМАЦИЯ
# ──────────────────────────────────────────────────
print_section "1/7" "Базовая информация о сервере"

CPU_MODEL=$(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
CPU_CORES=$(nproc)
CPU_MHZ=$(grep 'cpu MHz' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs | cut -d. -f1)
RAM_TOTAL=$(free -h | awk '/Mem:/ {print $2}')
RAM_FREE=$(free -h | awk '/Mem:/ {print $7}')
DISK_INFO=$(df -h / | awk 'NR==2 {print $2 " total, " $4 " free"}')
OS_NAME=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')
KERNEL=$(uname -r)
UPTIME=$(uptime -p 2>/dev/null || uptime)
VIRT=$(systemd-detect-virt 2>/dev/null || echo "unknown")

check_info "CPU:     ${BOLD}$CPU_MODEL${NC}"
check_info "Ядра:    ${BOLD}${CPU_CORES} @ ${CPU_MHZ} MHz${NC}"
check_info "RAM:     ${BOLD}$RAM_TOTAL total / $RAM_FREE free${NC}"
check_info "Диск:    ${BOLD}$DISK_INFO${NC}"
check_info "ОС:      ${BOLD}$OS_NAME${NC}"
check_info "Ядро:    ${BOLD}$KERNEL${NC}"
check_info "Uptime:  ${BOLD}$UPTIME${NC}"
check_info "Вирт:    ${BOLD}$VIRT${NC}"

# Проверка Ubuntu 22/24
if echo "$OS_NAME" | grep -qE 'Ubuntu 2[24]'; then
    check_pass "ОС актуальная — $OS_NAME"
else
    check_warn "Рекомендуется Ubuntu 22.04 или 24.04, у вас: $OS_NAME"
fi

# ──────────────────────────────────────────────────
# 2. СЕТЬ И ГЕОЛОКАЦИЯ
# ──────────────────────────────────────────────────
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

    if [ "$COUNTRY_CODE" = "NL" ]; then
        check_pass "Геолокация: Netherlands ✓"
    elif [ "$COUNTRY_CODE" = "DE" ]; then
        check_warn "Геолокация показывает Германию — проверь реальный ДЦ у провайдера"
    else
        check_fail "Геолокация: $COUNTRY — ожидается NL"
    fi
else
    check_fail "IPv4 недоступен"
fi

if [ -n "$IPV6" ]; then
    check_pass "IPv6 доступен: $IPV6"
else
    check_warn "IPv6 недоступен (не критично)"
fi

# ──────────────────────────────────────────────────
# 3. КРИТИЧЕСКИЕ ПАРАМЕТРЫ ДЛЯ XRAY
# ──────────────────────────────────────────────────
print_section "3/7" "Критические параметры для Xray / VLESS+Reality"

# AES-NI
if grep -q 'aes' /proc/cpuinfo; then
    check_pass "AES-NI включён — аппаратное шифрование активно"
else
    check_fail "AES-NI ОТКЛЮЧЁН — шифрование будет медленным, нода не подходит"
fi

# BBR
BBR=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
if [ "$BBR" = "bbr" ]; then
    check_pass "BBR включён — оптимальная работа на нестабильных каналах"
else
    check_warn "BBR выключен (текущий: $BBR). Включить: echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.conf && sysctl -p"
fi

# TUN/TAP
if [ -e /dev/net/tun ]; then
    check_pass "TUN/TAP доступен — AmneziaWG и WireGuard можно поднять"
else
    check_warn "TUN/TAP недоступен — WireGuard/AmneziaWG не запустить"
fi

# Проверка частоты CPU для Xray
if [ -n "$CPU_MHZ" ] && [ "$CPU_MHZ" -gt 3500 ] 2>/dev/null; then
    check_pass "Частота CPU: ${CPU_MHZ} MHz — отлично для Xray"
elif [ -n "$CPU_MHZ" ] && [ "$CPU_MHZ" -gt 2500 ] 2>/dev/null; then
    check_warn "Частота CPU: ${CPU_MHZ} MHz — приемлемо, но не оптимально"
else
    check_fail "Частота CPU: ${CPU_MHZ} MHz — низкая, Xray будет работать медленно"
fi

# ──────────────────────────────────────────────────
# 4. ТЕСТ CPU (AES-256-GCM для Xray)
# ──────────────────────────────────────────────────
print_section "4/7" "Тест CPU — скорость шифрования AES-256-GCM (как Xray)"

if command -v openssl &>/dev/null; then
    check_info "Запускаю 3-секундный тест openssl..."
    AES_RESULT=$(openssl speed -elapsed -seconds 3 aes-256-gcm 2>/dev/null | grep 'aes-256-gcm' | awk '{print $NF}')

    if [ -n "$AES_RESULT" ]; then
        # Конвертируем в Gbit/s для наглядности
        AES_GBIT=$(echo "$AES_RESULT" | awk '{printf "%.1f", $1/1024/1024/1024*8}' 2>/dev/null)
        check_info "Результат: ${BOLD}$AES_RESULT bytes/s (~${AES_GBIT} Gbit/s)${NC}"

        AES_MB=$(echo "$AES_RESULT" | awk '{print int($1/1024/1024)}' 2>/dev/null)
        if [ -n "$AES_MB" ]; then
            if [ "$AES_MB" -gt 5000 ] 2>/dev/null; then
                check_pass "Скорость шифрования: ${AES_MB} MB/s — ОТЛИЧНО (потянет 2000+ юзеров)"
            elif [ "$AES_MB" -gt 2000 ] 2>/dev/null; then
                check_pass "Скорость шифрования: ${AES_MB} MB/s — хорошо (до 1000 юзеров)"
            elif [ "$AES_MB" -gt 500 ] 2>/dev/null; then
                check_warn "Скорость шифрования: ${AES_MB} MB/s — приемлемо (до 200 юзеров)"
            else
                check_fail "Скорость шифрования: ${AES_MB} MB/s — слишком медленно"
            fi
        fi
    else
        check_warn "Не удалось получить результат openssl speed"
    fi
else
    check_warn "openssl не найден — пропускаю тест CPU"
fi

# ──────────────────────────────────────────────────
# 5. СКОРОСТЬ ДИСКА И КАНАЛА
# ──────────────────────────────────────────────────
print_section "5/7" "Скорость диска и канала"

# Тест диска
if command -v dd &>/dev/null; then
    check_info "Тест записи на диск..."
    WRITE_SPEED=$(dd if=/dev/zero of=/tmp/hatavpn_test bs=64k count=4096 conv=fdatasync 2>&1 | grep -oP '[0-9.]+ [MGk]B/s' | tail -1)
    rm -f /tmp/hatavpn_test
    check_info "Запись: ${BOLD}$WRITE_SPEED${NC}"

    check_info "Тест чтения с диска..."
    dd if=/dev/zero of=/tmp/hatavpn_test2 bs=64k count=4096 2>/dev/null
    READ_SPEED=$(dd if=/tmp/hatavpn_test2 of=/dev/null bs=64k 2>&1 | grep -oP '[0-9.]+ [MGk]B/s' | tail -1)
    rm -f /tmp/hatavpn_test2
    check_info "Чтение:  ${BOLD}$READ_SPEED${NC}"

    # Оценка
    READ_MB=$(echo "$READ_SPEED" | awk '{print int($1)}')
    if echo "$READ_SPEED" | grep -q 'GB/s'; then
        check_pass "Диск быстрый — NVMe подтверждён"
    elif [ -n "$READ_MB" ] && [ "$READ_MB" -gt 400 ] 2>/dev/null; then
        check_pass "Диск: $READ_SPEED — хороший SSD/NVMe"
    else
        check_warn "Диск медленный: $READ_SPEED (ожидается 500+ MB/s для NVMe)"
    fi
fi

# Тест скорости канала
check_info "Тест скорости канала (загрузка 100MB)..."
DL_SPEED=$(curl -o /dev/null -s -w "%{speed_download}" --max-time 30 http://speedtest.tele2.net/100MB.zip 2>/dev/null)
if [ -n "$DL_SPEED" ] && [ "$DL_SPEED" != "0" ]; then
    DL_MBIT=$(echo "$DL_SPEED" | awk '{printf "%.0f", $1/1024/1024*8}')
    check_info "Скорость загрузки: ${BOLD}${DL_MBIT} Mbit/s${NC}"
    if [ "$DL_MBIT" -gt 700 ] 2>/dev/null; then
        check_pass "Канал: ${DL_MBIT} Mbit/s — ОТЛИЧНО (полный 1 Gbit/s)"
    elif [ "$DL_MBIT" -gt 400 ] 2>/dev/null; then
        check_pass "Канал: ${DL_MBIT} Mbit/s — хорошо"
    elif [ "$DL_MBIT" -gt 100 ] 2>/dev/null; then
        check_warn "Канал: ${DL_MBIT} Mbit/s — приемлемо, но не 1 Gbps"
    else
        check_fail "Канал: ${DL_MBIT} Mbit/s — слишком медленно для VPN-ноды"
    fi
else
    check_warn "Не удалось замерить скорость канала"
fi

# ──────────────────────────────────────────────────
# 6. ПРОВЕРКА ПОРТОВ
# ──────────────────────────────────────────────────
print_section "6/8" "Проверка доступности портов"

check_info "Проверяю что ключевые порты не заблокированы провайдером..."

# Проверяем исходящие соединения на ключевые порты
for PORT in 80 443 8443 2053 2083 2087; do
    RESULT=$(curl -s --max-time 3 --connect-timeout 3 -o /dev/null -w "%{http_code}" "http://example.com:$PORT" 2>/dev/null)
    # Если получили любой ответ (даже ошибку соединения, но не timeout) — порт открыт
    NC_RESULT=$(bash -c "echo >/dev/tcp/1.1.1.1/$PORT" 2>/dev/null && echo "open" || echo "closed")
    if [ "$NC_RESULT" = "open" ]; then
        check_pass "Порт $PORT — открыт исходящий"
    else
        check_warn "Порт $PORT — возможно заблокирован провайдером"
    fi
done

# Проверка порта 25 (SMTP — должен быть заблокирован у хороших хостингов)
SMTP=$(bash -c "echo >/dev/tcp/gmail-smtp-in.l.google.com/25" 2>/dev/null && echo "open" || echo "blocked")
if [ "$SMTP" = "blocked" ]; then
    check_pass "Порт 25 (SMTP) заблокирован — защита от спама, норма"
else
    check_warn "Порт 25 (SMTP) открыт — IP может попасть в спам-листы"
fi

# ──────────────────────────────────────────────────
# 7. ПИНГ ДО РОССИЙСКИХ ПРОВАЙДЕРОВ
# ──────────────────────────────────────────────────
print_section "7/8" "Пинг до российских провайдеров (ключевой параметр)"

declare -A PING_HOSTS=(
    ["Cloudflare (эталон)"]="1.1.1.1"
    ["Google DNS"]="8.8.8.8"
    ["Яндекс DNS"]="77.88.8.8"
    ["MTC Москва"]="195.34.53.71"
    ["Билайн Москва"]="81.88.20.1"
)

ALL_PINGS_OK=true
for NAME in "Cloudflare (эталон)" "Google DNS" "Яндекс DNS" "MTC Москва" "Билайн Москва"; do
    HOST="${PING_HOSTS[$NAME]}"
    PING_MS=$(ping -c 4 -W 3 "$HOST" 2>/dev/null | tail -1 | awk -F'/' '{printf "%.1f", $5}' 2>/dev/null)
    if [ -n "$PING_MS" ] && [ "$PING_MS" != "." ]; then
        PING_INT=$(echo "$PING_MS" | cut -d. -f1)
        if [ "$PING_INT" -lt 40 ] 2>/dev/null; then
            check_pass "$NAME ($HOST): ${BOLD}${PING_MS}ms${NC} — отлично"
        elif [ "$PING_INT" -lt 80 ] 2>/dev/null; then
            check_pass "$NAME ($HOST): ${BOLD}${PING_MS}ms${NC} — хорошо"
        elif [ "$PING_INT" -lt 120 ] 2>/dev/null; then
            check_warn "$NAME ($HOST): ${BOLD}${PING_MS}ms${NC} — приемлемо"
            ALL_PINGS_OK=false
        else
            check_fail "$NAME ($HOST): ${BOLD}${PING_MS}ms${NC} — высокий пинг"
            ALL_PINGS_OK=false
        fi
    else
        check_warn "$NAME ($HOST): недоступен или ICMP заблокирован"
    fi
done

# ──────────────────────────────────────────────────
# 8. ПРОВЕРКА BLACKLIST / DNSBL
# ──────────────────────────────────────────────────
print_section "8/8" "Проверка IP в чёрных списках (DNSBL)"

if [ -z "$IPV4" ]; then
    IPV4=$(curl -s4 --max-time 5 ifconfig.me 2>/dev/null)
fi

if [ -n "$IPV4" ]; then
    # Реверс IP для DNSBL запросов (1.2.3.4 → 4.3.2.1)
    REVERSED_IP=$(echo "$IPV4" | awk -F. '{print $4"."$3"."$2"."$1}')
    check_info "Проверяю IP ${BOLD}$IPV4${NC} в основных DNSBL базах..."

    BLACKLISTED=0
    CLEAN=0

    # Список ключевых DNSBL баз
    declare -A DNSBL_LISTS=(
        ["Spamhaus SBL"]="sbl.spamhaus.org"
        ["Spamhaus XBL"]="xbl.spamhaus.org"
        ["Spamhaus PBL"]="pbl.spamhaus.org"
        ["Spamhaus ZEN"]="zen.spamhaus.org"
        ["SORBS SPAM"]="spam.sorbs.net"
        ["SORBS HTTP"]="http.sorbs.net"
        ["Barracuda"]="b.barracudacentral.org"
        ["SpamCop"]="bl.spamcop.net"
        ["UCEPROTECT L1"]="dnsbl-1.uceprotect.net"
        ["Abuse.ch"]="feodotracker.abuse.ch"
    )

    for NAME in "Spamhaus ZEN" "Spamhaus SBL" "Spamhaus XBL" "Barracuda" "SpamCop" "SORBS SPAM" "UCEPROTECT L1"; do
        BL="${DNSBL_LISTS[$NAME]}"
        QUERY="${REVERSED_IP}.${BL}"
        RESULT=$(host -t A "$QUERY" 2>/dev/null | grep 'has address')
        if [ -n "$RESULT" ]; then
            check_fail "BLACKLISTED в ${BOLD}$NAME${NC} ($BL)"
            ((BLACKLISTED++))
        else
            check_pass "Чист в $NAME"
            ((CLEAN++))
        fi
    done

    echo ""
    check_info "Итог DNSBL: ${GREEN}${BOLD}$CLEAN чист${NC} / ${RED}${BOLD}$BLACKLISTED в блэклисте${NC}"

    if [ "$BLACKLISTED" -eq 0 ]; then
        check_pass "IP не замечен в спам-базах — хорошая репутация"
    elif [ "$BLACKLISTED" -le 2 ]; then
        check_warn "IP в $BLACKLISTED базах — могут быть проблемы с почтой, для VPN некритично"
    else
        check_fail "IP в $BLACKLISTED базах — плохая репутация, лучше сменить IP у провайдера"
    fi

    # Отдельно проверяем Spamhaus PBL (это не плохо — просто динамический пул)
    PBL_QUERY="${REVERSED_IP}.pbl.spamhaus.org"
    PBL_RESULT=$(host -t A "$PBL_QUERY" 2>/dev/null | grep 'has address')
    if [ -n "$PBL_RESULT" ]; then
        check_info "IP в Spamhaus PBL — это норма для хостинга (Policy Block List, не спам)"
    fi
else
    check_warn "Нет IPv4 — пропускаю проверку DNSBL"
fi

# ──────────────────────────────────────────────────
# ИТОГОВЫЙ ВЕРДИКТ
# ──────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${BLUE}                  ИТОГОВЫЙ ВЕРДИКТ               ${NC}"
echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Критических проблем:  ${RED}${BOLD}$ISSUES${NC}"
echo -e "  Предупреждений:       ${YELLOW}${BOLD}$WARNINGS${NC}"
echo ""

if [ "$ISSUES" -eq 0 ] && [ "$WARNINGS" -le 2 ]; then
    echo -e "  ${GREEN}${BOLD}🚀 НОДА ПОДХОДИТ ДЛЯ HATAVPN${NC}"
    echo -e "  ${GREEN}Можно подключать к Remnawave и запускать пользователей.${NC}"

elif [ "$ISSUES" -eq 0 ]; then
    echo -e "  ${YELLOW}${BOLD}⚠️  НОДА УСЛОВНО ПОДХОДИТ${NC}"
    echo -e "  ${YELLOW}Устрани предупреждения перед запуском:${NC}"
    echo ""
    for i in "${!WARN_REASONS[@]}"; do
        NUM=$((i+1))
        # Убираем escape-коды для чистого вывода в списке
        CLEAN=$(echo "${WARN_REASONS[$i]}" | sed 's/\x1b\[[0-9;]*m//g')
        echo -e "  ${YELLOW}  $NUM. $CLEAN${NC}"
    done

else
    echo -e "  ${RED}${BOLD}❌ НОДА НЕ ПОДХОДИТ ДЛЯ HATAVPN${NC}"
    echo ""

    if [ "${#FAIL_REASONS[@]}" -gt 0 ]; then
        echo -e "  ${RED}${BOLD}Критические проблемы:${NC}"
        for i in "${!FAIL_REASONS[@]}"; do
            NUM=$((i+1))
            CLEAN=$(echo "${FAIL_REASONS[$i]}" | sed 's/\x1b\[[0-9;]*m//g')
            echo -e "  ${RED}  $NUM. $CLEAN${NC}"
        done
    fi

    if [ "${#WARN_REASONS[@]}" -gt 0 ]; then
        echo ""
        echo -e "  ${YELLOW}${BOLD}Дополнительные предупреждения:${NC}"
        for i in "${!WARN_REASONS[@]}"; do
            NUM=$((i+1))
            CLEAN=$(echo "${WARN_REASONS[$i]}" | sed 's/\x1b\[[0-9;]*m//g')
            echo -e "  ${YELLOW}  $NUM. $CLEAN${NC}"
        done
    fi

    echo ""
    echo -e "  ${RED}Реши проблемы выше или возьми другую ноду.${NC}"
fi

echo ""
echo -e "  ${CYAN}Следующий шаг:${NC} подключи ноду к Remnawave Panel"
echo -e "  ${CYAN}Протокол:${NC} VLESS + Reality + XHTTP"
echo ""
echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════${NC}"
echo ""
