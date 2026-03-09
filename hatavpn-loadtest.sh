#!/bin/bash
# ╔══════════════════════════════════════════════════╗
#   HataVPN Node Load Tester v1.0
#   Нагрузочный тест — сколько юзеров потянет нода
#   Запуск:
#   bash <(curl -sL https://raw.githubusercontent.com/mashiahzzx/hatavpn-node-check/main/hatavpn-loadtest.sh)
# ╚══════════════════════════════════════════════════╝

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

REPORT_FILE="/tmp/hatavpn-loadtest-$(date +%Y%m%d-%H%M%S).txt"
REPORT_LINES=()

print_section() {
    echo ""
    echo -e "${BOLD}${CYAN}[$1] $2${NC}"
    echo -e "${DIM}──────────────────────────────────────────────────${NC}"
    REPORT_LINES+=("" "[$1] $2" "──────────────────────────────────────────────────")
}
rlog() {
    REPORT_LINES+=("$(echo "$1" | sed 's/\x1b\[[0-9;]*m//g')")
}

# ══════════════════════════════════════════════════
# ШАПКА
# ══════════════════════════════════════════════════
clear
echo ""
echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║       HataVPN Node Load Tester  v1.0            ║${NC}"
echo -e "${BOLD}${BLUE}║   Нагрузочный тест — сколько юзеров потянет     ║${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo -e "  ${DIM}Время: $(date '+%Y-%m-%d %H:%M:%S UTC')${NC}"
echo -e "  ${DIM}Хост:  $(hostname)${NC}"
echo ""
echo -e "  ${YELLOW}Тест займёт ~2-3 минуты. Не прерывай.${NC}"
echo ""

rlog "HataVPN Node Load Tester v1.0"
rlog "Время: $(date '+%Y-%m-%d %H:%M:%S UTC')"
rlog "Хост:  $(hostname)"

START_TIME=$(date +%s)

# ══════════════════════════════════════════════════
# 1. СНИМАЕМ БАЗОВЫЕ МЕТРИКИ
# ══════════════════════════════════════════════════
print_section "1/5" "Базовые ресурсы ноды"

CPU_CORES=$(nproc)
CPU_MHZ=$(grep 'cpu MHz' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs | cut -d. -f1)
RAM_TOTAL_MB=$(free -m | awk '/Mem:/ {print $2}')
RAM_FREE_MB=$(free -m | awk '/Mem:/ {print $7}')
RAM_TOTAL_H=$(free -h | awk '/Mem:/ {print $2}')
RAM_FREE_H=$(free -h | awk '/Mem:/ {print $7}')

echo -e "  ${INFO}  CPU: ${BOLD}${CPU_CORES} vCPU @ ${CPU_MHZ} MHz${NC}"
echo -e "  ${INFO}  RAM: ${BOLD}${RAM_TOTAL_H} total / ${RAM_FREE_H} доступно${NC}"
rlog "CPU: ${CPU_CORES} vCPU @ ${CPU_MHZ} MHz"
rlog "RAM: ${RAM_TOTAL_H} total / ${RAM_FREE_H} доступно"

# Xray потребляет ~5-8MB RAM на 100 активных соединений
# + ~15MB базово для самого процесса
XRAY_BASE_MB=20
RAM_PER_100_USERS=7
RAM_FOR_OS=300  # резерв под ОС и прочее

RAM_AVAILABLE_FOR_XRAY=$((RAM_FREE_MB - RAM_FOR_OS))
[ "$RAM_AVAILABLE_FOR_XRAY" -lt 0 ] && RAM_AVAILABLE_FOR_XRAY=0
RAM_USER_LIMIT=$(( (RAM_AVAILABLE_FOR_XRAY - XRAY_BASE_MB) * 100 / RAM_PER_100_USERS ))
[ "$RAM_USER_LIMIT" -lt 0 ] && RAM_USER_LIMIT=0

echo -e "  ${INFO}  RAM доступно для Xray: ${BOLD}${RAM_AVAILABLE_FOR_XRAY} MB${NC}"
echo -e "  ${INFO}  Лимит по RAM: ~${BOLD}${RAM_USER_LIMIT}${NC} одновременных соединений"
rlog "RAM доступно для Xray: ${RAM_AVAILABLE_FOR_XRAY} MB → лимит ~${RAM_USER_LIMIT} соединений"

# ══════════════════════════════════════════════════
# 2. ТЕСТ CPU — МНОГОПОТОЧНОЕ ШИФРОВАНИЕ
# ══════════════════════════════════════════════════
print_section "2/5" "Тест CPU — многопоточное шифрование (как реальная нагрузка)"

echo -e "  ${INFO}  Симулирую шифрование ${CPU_CORES} потоков одновременно..."
rlog "Многопоточный тест AES-256-GCM, потоков: ${CPU_CORES}"

# Запускаем openssl в N потоков параллельно (по числу vCPU)
AES_TOTAL=0
AES_RESULTS=()

if command -v openssl &>/dev/null; then
    for i in $(seq 1 $CPU_CORES); do
        (
            RES=$(openssl speed -elapsed -seconds 3 aes-256-gcm 2>/dev/null \
                | grep 'aes-256-gcm' | awk '{print $NF}')
            # Новый формат Ubuntu 24.04
            if [ -z "$RES" ] || [ "$RES" = "0" ]; then
                RES=$(openssl speed -elapsed -seconds 3 aes-256-gcm 2>&1 \
                    | grep -oP '[0-9]+\.[0-9]+k bytes' | head -1 \
                    | awk '{print $1 * 1024}')
            fi
            echo "${RES:-0}" > /tmp/hv_aes_$i
        ) &
    done
    wait

    for i in $(seq 1 $CPU_CORES); do
        VAL=$(cat /tmp/hv_aes_$i 2>/dev/null || echo 0)
        rm -f /tmp/hv_aes_$i
        AES_TOTAL=$(echo "$AES_TOTAL $VAL" | awk '{printf "%.0f", $1 + $2}')
    done

    if [ "$AES_TOTAL" -gt 0 ] 2>/dev/null; then
        AES_TOTAL_MB=$(echo "$AES_TOTAL" | awk '{printf "%.0f", $1/1024/1024}')
        AES_TOTAL_GBIT=$(echo "$AES_TOTAL" | awk '{printf "%.1f", $1/1024/1024/1024*8}')
        echo -e "  ${INFO}  Суммарная пропускная способность: ${BOLD}${AES_TOTAL_MB} MB/s (~${AES_TOTAL_GBIT} Gbit/s)${NC}"
        rlog "CPU шифрование (${CPU_CORES} потоков): ${AES_TOTAL_MB} MB/s / ${AES_TOTAL_GBIT} Gbit/s"

        # Каждый активный юзер VPN ~= 1-5 Mbit/s трафика
        # Среднее потребление на юзера: 2 Mbit/s = 0.25 MB/s
        CPU_USER_LIMIT=$(echo "$AES_TOTAL_MB" | awk '{printf "%.0f", $1 / 0.25}')
        echo -e "  ${INFO}  Лимит по CPU: ~${BOLD}${CPU_USER_LIMIT}${NC} одновременных соединений"
        rlog "Лимит по CPU: ~${CPU_USER_LIMIT} соединений"
    else
        echo -e "  ${WARN} openssl тест не дал результата — считаем по частоте CPU"
        rlog "openssl тест пропущен"
        # Грубая оценка по частоте: 1 vCPU @ 4GHz ≈ 500 юзеров
        CPU_USER_LIMIT=$(( CPU_CORES * CPU_MHZ / 8 ))
        echo -e "  ${INFO}  Оценка по частоте: ~${BOLD}${CPU_USER_LIMIT}${NC} одновременных соединений"
        rlog "Оценка по частоте: ~${CPU_USER_LIMIT} соединений"
    fi
else
    echo -e "  ${WARN} openssl не найден"
    CPU_USER_LIMIT=$(( CPU_CORES * CPU_MHZ / 8 ))
    rlog "openssl не найден, оценка по частоте: ~${CPU_USER_LIMIT} соединений"
fi

# ══════════════════════════════════════════════════
# 3. ТЕСТ СЕТИ — ПАРАЛЛЕЛЬНЫЕ СОЕДИНЕНИЯ
# ══════════════════════════════════════════════════
print_section "3/5" "Тест сети — параллельные соединения"

echo -e "  ${INFO}  Тест максимального числа одновременных TCP-соединений..."

# Проверяем лимиты ядра
SOMAXCONN=$(cat /proc/sys/net/core/somaxconn 2>/dev/null || echo "128")
FILE_MAX=$(cat /proc/sys/fs/file-max 2>/dev/null || echo "0")
ULIMIT_N=$(ulimit -n 2>/dev/null || echo "1024")
TCP_TW=$(cat /proc/sys/net/ipv4/tcp_tw_reuse 2>/dev/null || echo "0")
LOCAL_PORTS=$(cat /proc/sys/net/ipv4/ip_local_port_range 2>/dev/null | awk '{print $2-$1}')

echo -e "  ${INFO}  somaxconn (очередь соединений): ${BOLD}${SOMAXCONN}${NC}"
echo -e "  ${INFO}  file-max (макс. открытых файлов): ${BOLD}${FILE_MAX}${NC}"
echo -e "  ${INFO}  ulimit -n (лимит fd процесса): ${BOLD}${ULIMIT_N}${NC}"
echo -e "  ${INFO}  tcp_tw_reuse: ${BOLD}${TCP_TW}${NC}"
echo -e "  ${INFO}  Локальных портов: ${BOLD}${LOCAL_PORTS:-н/д}${NC}"
rlog "somaxconn: $SOMAXCONN | file-max: $FILE_MAX | ulimit: $ULIMIT_N | tcp_tw_reuse: $TCP_TW"

# Оцениваем лимит по сетевым настройкам
NET_USER_LIMIT=10000  # дефолт
if [ "$ULIMIT_N" -lt 4096 ] 2>/dev/null; then
    NET_USER_LIMIT=$((ULIMIT_N / 4))
    echo -e "  ${WARN} ulimit -n слишком мал: $ULIMIT_N — ограничит Xray до ~${NET_USER_LIMIT} соединений"
    echo -e "  ${INFO}  Фикс: echo '* soft nofile 65535' >> /etc/security/limits.conf"
    rlog "⚠️ ulimit мал: $ULIMIT_N → лимит ~${NET_USER_LIMIT} соединений"
else
    echo -e "  ${OK}  Сетевые лимиты ОС достаточны"
    rlog "✅ Сетевые лимиты ОС в норме"
fi

# Реальный стресс-тест: открываем параллельные TCP-соединения к 1.1.1.1:80
echo ""
echo -e "  ${INFO}  Стресс-тест: 200 параллельных TCP-соединений..."
rlog "Стресс-тест: 200 параллельных TCP-соединений"

SUCCESS=0
FAIL_CONN=0

for i in $(seq 1 200); do
    (timeout 3 bash -c 'echo "" > /dev/tcp/1.1.1.1/80' 2>/dev/null && \
        echo "ok" || echo "fail") > /tmp/hv_conn_$i &
done
wait

for i in $(seq 1 200); do
    RES=$(cat /tmp/hv_conn_$i 2>/dev/null)
    rm -f /tmp/hv_conn_$i
    [ "$RES" = "ok" ] && ((SUCCESS++)) || ((FAIL_CONN++))
done

CONN_PCT=$(echo "$SUCCESS" | awk '{printf "%.0f", $1/200*100}')
echo -e "  ${INFO}  Успешных соединений: ${BOLD}${SUCCESS}/200 (${CONN_PCT}%)${NC}"
rlog "Параллельные соединения: ${SUCCESS}/200 успешных (${CONN_PCT}%)"

if [ "$SUCCESS" -ge 190 ]; then
    echo -e "  ${OK}  Нода держит 200+ параллельных соединений — отлично"
    rlog "✅ 200+ параллельных соединений"
    NET_CONN_OK=true
elif [ "$SUCCESS" -ge 150 ]; then
    echo -e "  ${WARN} Часть соединений отвалилась: ${SUCCESS}/200"
    rlog "⚠️ ${SUCCESS}/200 соединений"
    NET_CONN_OK=true
else
    echo -e "  ${FAIL}  Много потерь: ${SUCCESS}/200 — проблема с сетью или лимитами"
    rlog "❌ Проблема: ${SUCCESS}/200 соединений"
    NET_CONN_OK=false
fi

# ══════════════════════════════════════════════════
# 4. ТЕСТ ПАМЯТИ ПОД НАГРУЗКОЙ
# ══════════════════════════════════════════════════
print_section "4/5" "Тест памяти под нагрузкой"

echo -e "  ${INFO}  Симулирую 500 Xray-соединений в памяти..."
rlog "Симуляция 500 соединений в памяти"

# Каждое соединение Xray держит буферы ~8-16KB
# Симулируем: 500 процессов с минимальным буфером
MEM_BEFORE=$(free -m | awk '/Mem:/ {print $3}')

python3 - << 'PYEOF' 2>/dev/null &
import time, threading

buffers = []
def hold_memory():
    # ~12KB на соединение
    buf = bytearray(12 * 1024)
    buffers.append(buf)
    time.sleep(5)

threads = []
for _ in range(500):
    t = threading.Thread(target=hold_memory)
    t.daemon = True
    t.start()
    threads.append(t)

time.sleep(5)
PYEOF

PY_PID=$!
sleep 2  # даём время занять память

MEM_AFTER=$(free -m | awk '/Mem:/ {print $3}')
MEM_DELTA=$((MEM_AFTER - MEM_BEFORE))

wait $PY_PID 2>/dev/null

echo -e "  ${INFO}  Память до симуляции:   ${BOLD}${MEM_BEFORE} MB${NC}"
echo -e "  ${INFO}  Память во время:       ${BOLD}${MEM_AFTER} MB${NC}"
echo -e "  ${INFO}  Дельта (500 соед.):    ${BOLD}${MEM_DELTA} MB${NC}"
rlog "Память: до ${MEM_BEFORE}MB / во время ${MEM_AFTER}MB / дельта ${MEM_DELTA}MB"

# Пересчитываем реальный лимит по памяти
if [ "$MEM_DELTA" -gt 0 ] 2>/dev/null; then
    MB_PER_CONN=$(echo "$MEM_DELTA" | awk '{printf "%.3f", $1/500}')
    RAM_USER_LIMIT_REAL=$(echo "$RAM_AVAILABLE_FOR_XRAY $MEM_DELTA" | \
        awk '{printf "%.0f", $1 / ($2/500)}')
    echo -e "  ${INFO}  Памяти на соединение:  ${BOLD}${MB_PER_CONN} MB${NC}"
    echo -e "  ${INFO}  Уточнённый лимит по RAM: ~${BOLD}${RAM_USER_LIMIT_REAL}${NC} соединений"
    rlog "Памяти на соединение: ${MB_PER_CONN} MB → уточнённый лимит: ~${RAM_USER_LIMIT_REAL}"
    RAM_USER_LIMIT=$RAM_USER_LIMIT_REAL
else
    echo -e "  ${INFO}  Python тест пропущен — используем теоретическую оценку"
    rlog "Python тест пропущен"
fi

# ══════════════════════════════════════════════════
# 5. ИТОГОВЫЙ РАСЧЁТ
# ══════════════════════════════════════════════════
print_section "5/5" "Итоговый расчёт ёмкости ноды"

# Лимит по каналу (если speedtest-cli доступен)
CHANNEL_MBIT=0
if command -v speedtest-cli &>/dev/null; then
    echo -e "  ${INFO}  Проверяю канал..."
    ST=$(speedtest-cli --simple --timeout 20 2>/dev/null)
    DL=$(echo "$ST" | grep -i download | awk '{print $2}' | cut -d. -f1)
    [ -n "$DL" ] && CHANNEL_MBIT=$DL
fi

if [ "$CHANNEL_MBIT" -gt 0 ] 2>/dev/null; then
    # Каждый юзер в среднем 1.5 Mbit/s при активном использовании
    CHANNEL_USER_LIMIT=$(echo "$CHANNEL_MBIT" | awk '{printf "%.0f", $1 / 1.5}')
    echo -e "  ${INFO}  Канал: ${BOLD}${CHANNEL_MBIT} Mbit/s${NC} → лимит ~${BOLD}${CHANNEL_USER_LIMIT}${NC} активных юзеров"
    rlog "Канал: ${CHANNEL_MBIT} Mbit/s → ~${CHANNEL_USER_LIMIT} активных юзеров"
else
    # Берём консервативно 400 Mbit/s если не смогли измерить
    CHANNEL_USER_LIMIT=266
    echo -e "  ${INFO}  Канал: не измерен — используем консервативную оценку 400 Mbit/s"
    rlog "Канал: не измерен, консервативная оценка"
fi

echo ""
echo -e "  ${BOLD}Сводка лимитов:${NC}"
echo -e "  ${DIM}┌──────────────────────────────────────────────┐${NC}"
echo -e "  ${DIM}│${NC}  По CPU (шифрование):   ~${BOLD}${CPU_USER_LIMIT}${NC} соединений"
echo -e "  ${DIM}│${NC}  По RAM:                ~${BOLD}${RAM_USER_LIMIT}${NC} соединений"
echo -e "  ${DIM}│${NC}  По каналу:             ~${BOLD}${CHANNEL_USER_LIMIT}${NC} активных юзеров"
echo -e "  ${DIM}└──────────────────────────────────────────────┘${NC}"

rlog ""
rlog "Лимиты:"
rlog "  По CPU:    ~${CPU_USER_LIMIT} соединений"
rlog "  По RAM:    ~${RAM_USER_LIMIT} соединений"
rlog "  По каналу: ~${CHANNEL_USER_LIMIT} активных юзеров"

# Узкое место — минимум из всех
BOTTLENECK=$CPU_USER_LIMIT
BOTTLENECK_NAME="CPU"
if [ "$RAM_USER_LIMIT" -lt "$BOTTLENECK" ] 2>/dev/null; then
    BOTTLENECK=$RAM_USER_LIMIT
    BOTTLENECK_NAME="RAM"
fi
if [ "$CHANNEL_USER_LIMIT" -lt "$BOTTLENECK" ] 2>/dev/null; then
    BOTTLENECK=$CHANNEL_USER_LIMIT
    BOTTLENECK_NAME="Канал"
fi

# Реальных пользователей больше чем одновременных (онлайн обычно 10-20%)
# Если одновременно 300 → реальных подписчиков 1500-3000
REAL_USERS_LOW=$((BOTTLENECK * 5))
REAL_USERS_HIGH=$((BOTTLENECK * 10))

echo ""
echo -e "  ${BOLD}${YELLOW}Узкое место: $BOTTLENECK_NAME (~${BOTTLENECK} одновременных соединений)${NC}"
rlog "Узкое место: $BOTTLENECK_NAME (~${BOTTLENECK} одновременных)"

# ══════════════════════════════════════════════════
# ФИНАЛЬНЫЙ ВЕРДИКТ
# ══════════════════════════════════════════════════
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║              ЁМКОСТЬ НОДЫ HATAVPN               ║${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo ""

rlog ""
rlog "══════════════════ ЁМКОСТЬ НОДЫ ══════════════════"

if [ "$BOTTLENECK" -gt 2000 ] 2>/dev/null; then
    TIER="${GREEN}${BOLD}🚀 МОЩНАЯ НОДА${NC}"
    TIER_TEXT="Потянет крупный проект"
elif [ "$BOTTLENECK" -gt 800 ] 2>/dev/null; then
    TIER="${GREEN}${BOLD}💪 ХОРОШАЯ НОДА${NC}"
    TIER_TEXT="Комфортная нагрузка"
elif [ "$BOTTLENECK" -gt 300 ] 2>/dev/null; then
    TIER="${YELLOW}${BOLD}👍 СРЕДНЯЯ НОДА${NC}"
    TIER_TEXT="Подходит для старта"
else
    TIER="${RED}${BOLD}⚡ СЛАБАЯ НОДА${NC}"
    TIER_TEXT="Только для тестирования"
fi

echo -e "  $TIER — $TIER_TEXT"
echo ""
echo -e "  ${BOLD}Одновременных соединений:   ~${BOTTLENECK}${NC}"
echo -e "  ${BOLD}Реальных подписчиков:        ~${REAL_USERS_LOW} – ${REAL_USERS_HIGH}${NC}"
echo -e "  ${DIM}(при активности 10-20% онлайн одновременно)${NC}"
echo ""

rlog "$(echo "$TIER" | sed 's/\x1b\[[0-9;]*m//g') — $TIER_TEXT"
rlog "Одновременных соединений: ~${BOTTLENECK}"
rlog "Реальных подписчиков:     ~${REAL_USERS_LOW} – ${REAL_USERS_HIGH}"

# Таблица масштабирования
echo -e "  ${BOLD}Когда добавлять следующую ноду:${NC}"
echo -e "  ${DIM}┌─────────────────────────────────────────────────┐${NC}"
SCALE_75=$((BOTTLENECK * 75 / 100))
SCALE_90=$((BOTTLENECK * 90 / 100))
echo -e "  ${DIM}│${NC}  ${YELLOW}⚠️  При ${SCALE_75} онлайн${NC} — готовь вторую ноду"
echo -e "  ${DIM}│${NC}  ${RED}🔴 При ${SCALE_90} онлайн${NC} — срочно добавляй ноду"
echo -e "  ${DIM}└─────────────────────────────────────────────────┘${NC}"
echo ""

rlog "Добавить ноду при: ${SCALE_75} онлайн (75%) / срочно при ${SCALE_90} (90%)"

echo -e "  Тест занял: ${DIM}${ELAPSED} сек${NC}"
echo ""

# Сохраняем отчёт
{
    echo "=================================================="
    echo " HataVPN Node Load Tester v1.0"
    echo " Дата:  $(date '+%Y-%m-%d %H:%M:%S UTC')"
    echo " Хост:  $(hostname)"
    echo "=================================================="
    echo ""
    for line in "${REPORT_LINES[@]}"; do
        echo "$line"
    done
} > "$REPORT_FILE"

echo -e "  ${CYAN}📄 Отчёт: ${BOLD}$REPORT_FILE${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo ""
