#!/bin/bash
# ╔══════════════════════════════════════════════════╗
#   HataVPN Node Load Tester v2.0
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
rlog() { REPORT_LINES+=("$(echo "$1" | sed 's/\x1b\[[0-9;]*m//g')"); }

# ══════════════════════════════════════════════════
# ШАПКА
# ══════════════════════════════════════════════════
clear
echo ""
echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║       HataVPN Node Load Tester  v2.0            ║${NC}"
echo -e "${BOLD}${BLUE}║   Нагрузочный тест — сколько юзеров потянет     ║${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo -e "  ${DIM}Время: $(date '+%Y-%m-%d %H:%M:%S UTC')${NC}"
echo -e "  ${DIM}Хост:  $(hostname)${NC}"
echo ""
echo -e "  ${YELLOW}Тест займёт ~3-4 минуты. Не прерывай.${NC}"
echo ""

rlog "HataVPN Node Load Tester v2.0"
rlog "Время: $(date '+%Y-%m-%d %H:%M:%S UTC')"
rlog "Хост:  $(hostname)"

START_TIME=$(date +%s)

# ══════════════════════════════════════════════════
# 0. УСТАНОВКА ЗАВИСИМОСТЕЙ
# ══════════════════════════════════════════════════
print_section "0/7" "Подготовка — установка инструментов"

for PKG in iperf3 bc sysstat; do
    if ! command -v $PKG &>/dev/null; then
        echo -e "  ${INFO}  Устанавливаю $PKG..."
        apt-get install -y -q $PKG 2>/dev/null && \
            echo -e "  ${OK}  $PKG установлен" || \
            echo -e "  ${WARN} $PKG не удалось установить — пропущу связанные тесты"
    else
        echo -e "  ${OK}  $PKG уже есть"
    fi
done

# ══════════════════════════════════════════════════
# 1. БАЗОВЫЕ РЕСУРСЫ
# ══════════════════════════════════════════════════
print_section "1/7" "Базовые ресурсы ноды"

CPU_CORES=$(nproc)
CPU_MHZ=$(grep 'cpu MHz' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs | cut -d. -f1)
RAM_TOTAL_MB=$(free -m | awk '/Mem:/ {print $2}')
RAM_FREE_MB=$(free -m  | awk '/Mem:/ {print $7}')
RAM_TOTAL_H=$(free -h  | awk '/Mem:/ {print $2}')
RAM_FREE_H=$(free -h   | awk '/Mem:/ {print $7}')

echo -e "  ${INFO}  CPU: ${BOLD}${CPU_CORES} vCPU @ ${CPU_MHZ} MHz${NC}"
echo -e "  ${INFO}  RAM: ${BOLD}${RAM_TOTAL_H} total / ${RAM_FREE_H} доступно${NC}"
rlog "CPU: ${CPU_CORES} vCPU @ ${CPU_MHZ} MHz | RAM: ${RAM_TOTAL_H} / свободно ${RAM_FREE_H}"

RAM_FOR_OS=300
RAM_AVAILABLE_FOR_XRAY=$((RAM_FREE_MB - RAM_FOR_OS))
[ "$RAM_AVAILABLE_FOR_XRAY" -lt 0 ] && RAM_AVAILABLE_FOR_XRAY=0

# ── File descriptors ─────────────────────────────
# Xray открывает 2 fd на соединение (входящий + исходящий)
ULIMIT_N=$(ulimit -n 2>/dev/null || echo "1024")
FD_USER_LIMIT=$((ULIMIT_N / 2))
SOMAXCONN=$(cat /proc/sys/net/core/somaxconn 2>/dev/null || echo "128")
TCP_TW=$(cat /proc/sys/net/ipv4/tcp_tw_reuse 2>/dev/null || echo "0")
FILE_MAX=$(cat /proc/sys/fs/file-max 2>/dev/null || echo "0")

echo -e "  ${INFO}  ulimit -n (fd процесса): ${BOLD}${ULIMIT_N}${NC}"
echo -e "  ${INFO}  somaxconn:               ${BOLD}${SOMAXCONN}${NC}"
echo -e "  ${INFO}  tcp_tw_reuse:            ${BOLD}${TCP_TW}${NC}"
rlog "ulimit -n: $ULIMIT_N | somaxconn: $SOMAXCONN | tcp_tw_reuse: $TCP_TW"

if [ "$ULIMIT_N" -lt 4096 ] 2>/dev/null; then
    echo -e "  ${FAIL}  ulimit -n = $ULIMIT_N — Xray сможет держать только ~${FD_USER_LIMIT} соединений!"
    echo -e "  ${INFO}  Фикс: echo '* soft nofile 65535' >> /etc/security/limits.conf && echo '* hard nofile 65535' >> /etc/security/limits.conf"
    rlog "❌ ulimit критически мал: $ULIMIT_N → реальный лимит ~${FD_USER_LIMIT} соединений"
elif [ "$ULIMIT_N" -lt 16384 ] 2>/dev/null; then
    echo -e "  ${WARN} ulimit -n = $ULIMIT_N — лимит ~${FD_USER_LIMIT} соединений, рекомендуется 65535"
    rlog "⚠️ ulimit невысокий: $ULIMIT_N"
else
    echo -e "  ${OK}  ulimit -n = $ULIMIT_N — fd лимит не будет узким местом"
    rlog "✅ ulimit в норме: $ULIMIT_N"
fi

# ══════════════════════════════════════════════════
# 2. CPU STEAL — СКОЛЬКО ЗАБИРАЮТ СОСЕДИ
# ══════════════════════════════════════════════════
print_section "2/7" "CPU steal — кража процессора соседями по гипервизору"

echo -e "  ${INFO}  Измеряю CPU steal за 5 секунд..."
rlog "Тест CPU steal (5 сек)"

STEAL_AVG=0
if command -v iostat &>/dev/null; then
    # iostat из sysstat — самый точный способ
    STEAL_LINE=$(iostat -c 1 5 2>/dev/null | grep -v '^$' | tail -2 | head -1)
    # формат: %user %nice %system %iowait %steal %idle
    STEAL_AVG=$(echo "$STEAL_LINE" | awk '{print $5}' | tr ',' '.')
    CPU_IDLE=$(echo "$STEAL_LINE" | awk '{print $6}' | tr ',' '.')
elif [ -f /proc/stat ]; then
    # Fallback через /proc/stat
    read_steal() { awk '/^cpu / {print $9}' /proc/stat; }
    read_total() { awk '/^cpu / {s=0; for(i=2;i<=NF;i++) s+=$i; print s}' /proc/stat; }
    S1=$(read_steal); T1=$(read_total)
    sleep 5
    S2=$(read_steal); T2=$(read_total)
    STEAL_AVG=$(echo "$S1 $S2 $T1 $T2" | awk '{printf "%.1f", ($2-$1)/($4-$3)*100}')
    CPU_IDLE=$(awk '/^cpu / {print $5}' /proc/stat)
fi

if [ -n "$STEAL_AVG" ] && [ "$STEAL_AVG" != "0" ] && [ "$STEAL_AVG" != "0.0" ]; then
    STEAL_INT=$(echo "$STEAL_AVG" | cut -d. -f1)
    echo -e "  ${INFO}  CPU steal: ${BOLD}${STEAL_AVG}%${NC}"
    rlog "CPU steal: ${STEAL_AVG}%"

    if   [ "$STEAL_INT" -lt 2 ]  2>/dev/null; then
        echo -e "  ${OK}  Steal ${STEAL_AVG}% — соседи не мешают, нода не переподписана"
        rlog "✅ Steal нормальный"
    elif [ "$STEAL_INT" -lt 5 ]  2>/dev/null; then
        echo -e "  ${WARN} Steal ${STEAL_AVG}% — небольшая кража CPU, при высокой нагрузке заметно"
        rlog "⚠️ Steal умеренный"
    elif [ "$STEAL_INT" -lt 10 ] 2>/dev/null; then
        echo -e "  ${FAIL}  Steal ${STEAL_AVG}% — заметная кража CPU, производительность занижена"
        rlog "❌ Steal высокий"
    else
        echo -e "  ${FAIL}  Steal ${STEAL_AVG}% — КРИТИЧНО, гипервизор перегружен, смени провайдера"
        rlog "❌ КРИТИЧНО: Steal ${STEAL_AVG}%"
    fi
else
    echo -e "  ${INFO}  Steal = 0% или не измерить — скорее всего KVM с честным CPU"
    rlog "Steal: 0% (KVM)"
fi

# ══════════════════════════════════════════════════
# 3. CPU — МНОГОПОТОЧНОЕ ШИФРОВАНИЕ
# ══════════════════════════════════════════════════
print_section "3/7" "CPU — многопоточное шифрование AES-256-GCM"

echo -e "  ${INFO}  Запускаю ${CPU_CORES} потоков параллельно (как реальный Xray)..."
rlog "Многопоточный AES-256-GCM, потоков: ${CPU_CORES}"

AES_TOTAL=0
CPU_USER_LIMIT=0

if command -v openssl &>/dev/null; then
    for i in $(seq 1 $CPU_CORES); do
        (
            RES=$(openssl speed -elapsed -seconds 3 aes-256-gcm 2>/dev/null \
                | grep 'aes-256-gcm' | awk '{print $NF}')
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
        AES_TOTAL=$(echo "$AES_TOTAL $VAL" | awk '{printf "%.0f", $1+$2}')
    done

    if [ "$AES_TOTAL" -gt 0 ] 2>/dev/null; then
        AES_MB=$(echo "$AES_TOTAL" | awk '{printf "%.0f", $1/1024/1024}')
        AES_GBIT=$(echo "$AES_TOTAL" | awk '{printf "%.1f", $1/1024/1024/1024*8}')
        echo -e "  ${INFO}  Суммарно (${CPU_CORES} потоков): ${BOLD}${AES_MB} MB/s (~${AES_GBIT} Gbit/s)${NC}"
        rlog "AES-256-GCM (${CPU_CORES} потоков): ${AES_MB} MB/s / ${AES_GBIT} Gbit/s"
        CPU_USER_LIMIT=$(echo "$AES_MB" | awk '{printf "%.0f", $1/0.25}')
        echo -e "  ${INFO}  Лимит по CPU: ~${BOLD}${CPU_USER_LIMIT}${NC} одновременных соединений"
        rlog "Лимит по CPU: ~${CPU_USER_LIMIT}"
    fi
else
    CPU_USER_LIMIT=$(( CPU_CORES * CPU_MHZ / 8 ))
    echo -e "  ${INFO}  openssl не найден — оценка по частоте: ~${CPU_USER_LIMIT} соединений"
    rlog "openssl не найден, оценка: ~${CPU_USER_LIMIT}"
fi

# ══════════════════════════════════════════════════
# 4. IPERF3 — РЕАЛЬНАЯ ПРОПУСКНАЯ СПОСОБНОСТЬ
# ══════════════════════════════════════════════════
print_section "4/7" "iperf3 — реальная пропускная способность канала"

CHANNEL_MBIT=0
IPERF_USER_LIMIT=0

if command -v iperf3 &>/dev/null; then
    # Публичные iperf3 серверы
    IPERF_SERVERS=(
        "iperf.online.net:5200"
        "bouygues.testdebit.info:9200"
        "ping.online.net:5200"
    )

    for SERVER_ENTRY in "${IPERF_SERVERS[@]}"; do
        SRV=$(echo $SERVER_ENTRY | cut -d: -f1)
        PORT=$(echo $SERVER_ENTRY | cut -d: -f2)
        echo -e "  ${INFO}  → iperf3 → $SRV:$PORT (10 сек)..."

        RESULT=$(iperf3 -c "$SRV" -p "$PORT" -t 10 -P 4 --connect-timeout 5000 2>/dev/null \
            | grep -E 'sender|receiver' | tail -1)

        if [ -n "$RESULT" ]; then
            SPEED=$(echo "$RESULT" | awk '{print $(NF-1)}')
            UNIT=$(echo "$RESULT" | awk '{print $NF}')
            echo -e "  ${OK}  $SRV: ${BOLD}${SPEED} ${UNIT}${NC}"
            rlog "iperf3 $SRV: ${SPEED} ${UNIT}"

            # Конвертируем в Mbit/s
            if echo "$UNIT" | grep -qi 'Gbits'; then
                CHANNEL_MBIT=$(echo "$SPEED" | awk '{printf "%.0f", $1*1000}')
            else
                CHANNEL_MBIT=$(echo "$SPEED" | awk '{printf "%.0f", $1}')
            fi
            break
        else
            echo -e "  ${INFO}  $SRV недоступен — пробую следующий..."
        fi
    done

    if [ "$CHANNEL_MBIT" -eq 0 ]; then
        echo -e "  ${WARN} iperf3 серверы недоступны — fallback на speedtest-cli"
        rlog "iperf3 серверы недоступны"
    fi
fi

# Fallback: speedtest-cli
if [ "$CHANNEL_MBIT" -eq 0 ]; then
    if ! command -v speedtest-cli &>/dev/null; then
        echo -e "  ${INFO}  Устанавливаю speedtest-cli..."
        apt-get install -y -q speedtest-cli 2>/dev/null
    fi
    if command -v speedtest-cli &>/dev/null; then
        echo -e "  ${INFO}  → speedtest-cli..."
        ST=$(speedtest-cli --simple --timeout 30 2>/dev/null)
        DL=$(echo "$ST" | grep -i download | awk '{print $2}' | cut -d. -f1)
        UL=$(echo "$ST" | grep -i upload   | awk '{print $2}' | cut -d. -f1)
        PING_ST=$(echo "$ST" | grep -i ping | awk '{print $2}')
        if [ -n "$DL" ] && [ "$DL" -gt 0 ] 2>/dev/null; then
            CHANNEL_MBIT=$DL
            echo -e "  ${OK}  speedtest: Download ${BOLD}${DL} Mbit/s${NC} / Upload ${BOLD}${UL} Mbit/s${NC} / Ping ${PING_ST}ms"
            rlog "speedtest-cli: DL=${DL} UL=${UL} Mbit/s Ping=${PING_ST}ms"
        fi
    fi
fi

if [ "$CHANNEL_MBIT" -gt 0 ] 2>/dev/null; then
    IPERF_USER_LIMIT=$(echo "$CHANNEL_MBIT" | awk '{printf "%.0f", $1/1.5}')
    echo -e "  ${INFO}  Лимит по каналу: ~${BOLD}${IPERF_USER_LIMIT}${NC} активных юзеров (при 1.5 Mbit/с на юзера)"
    rlog "Лимит по каналу: ~${IPERF_USER_LIMIT} (при 1.5 Mbit/с на юзера)"

    if   [ "$CHANNEL_MBIT" -gt 700 ] 2>/dev/null; then
        echo -e "  ${OK}  Канал ${CHANNEL_MBIT} Mbit/s — полноценный 1 Gbps"
    elif [ "$CHANNEL_MBIT" -gt 400 ] 2>/dev/null; then
        echo -e "  ${OK}  Канал ${CHANNEL_MBIT} Mbit/s — хорошо"
    elif [ "$CHANNEL_MBIT" -gt 100 ] 2>/dev/null; then
        echo -e "  ${WARN} Канал ${CHANNEL_MBIT} Mbit/s — приемлемо, не 1 Gbps"
    else
        echo -e "  ${FAIL}  Канал ${CHANNEL_MBIT} Mbit/s — слишком медленно"
    fi
else
    IPERF_USER_LIMIT=266
    echo -e "  ${WARN} Канал не измерен — используем консервативную оценку 400 Mbit/s"
    rlog "Канал не измерен, консервативная оценка"
fi

# ══════════════════════════════════════════════════
# 5. LATENCY ПОД НАГРУЗКОЙ
# ══════════════════════════════════════════════════
print_section "5/7" "Latency под нагрузкой — как юзеры ощутят пинг"

echo -e "  ${INFO}  Базовый пинг до Яндекса (РФ)..."
PING_BASE=$(ping -c 5 -W 3 77.88.8.8 2>/dev/null | tail -1 | awk -F'/' '{printf "%.1f", $5}')
echo -e "  ${INFO}  Базовый пинг: ${BOLD}${PING_BASE}ms${NC}"
rlog "Базовый пинг до Яндекс: ${PING_BASE}ms"

echo -e "  ${INFO}  Создаю нагрузку на CPU + сеть..."

# Нагружаем CPU всеми ядрами
for i in $(seq 1 $CPU_CORES); do
    dd if=/dev/urandom bs=1M count=999 2>/dev/null | openssl enc -aes-256-cbc -pass pass:test -pbkdf2 -nosalt > /dev/null &
done
STRESS_PIDS=$(jobs -p)

# Параллельно нагружаем сеть — 50 curl запросов
for i in $(seq 1 50); do
    curl -s -o /dev/null --max-time 10 https://speed.cloudflare.com/__down?bytes=1048576 \
        -A "Mozilla/5.0" 2>/dev/null &
done

sleep 3  # даём нагрузке разогнаться

echo -e "  ${INFO}  Пинг под нагрузкой..."
PING_LOADED=$(ping -c 10 -W 3 77.88.8.8 2>/dev/null | tail -1 | awk -F'/' '{printf "%.1f", $5}')
PING_LOADED_MAX=$(ping -c 10 -W 3 77.88.8.8 2>/dev/null | tail -1 | awk -F'/' '{printf "%.1f", $6}')

# Останавливаем нагрузку
kill $STRESS_PIDS 2>/dev/null
wait 2>/dev/null

echo -e "  ${INFO}  Пинг под нагрузкой: avg ${BOLD}${PING_LOADED}ms${NC} / max ${BOLD}${PING_LOADED_MAX}ms${NC}"
rlog "Пинг под нагрузкой: avg ${PING_LOADED}ms / max ${PING_LOADED_MAX}ms (базовый: ${PING_BASE}ms)"

# Деградация пинга
if [ -n "$PING_BASE" ] && [ -n "$PING_LOADED" ]; then
    PING_DELTA=$(echo "$PING_BASE $PING_LOADED" | awk '{printf "%.0f", $2-$1}')
    PING_LOADED_INT=$(echo "$PING_LOADED" | cut -d. -f1)

    echo -e "  ${INFO}  Деградация: +${BOLD}${PING_DELTA}ms${NC} под нагрузкой"
    rlog "Деградация пинга: +${PING_DELTA}ms"

    if   [ "$PING_DELTA" -lt 10 ]  2>/dev/null; then
        echo -e "  ${OK}  Пинг стабильный под нагрузкой — юзеры не заметят разницы"
        rlog "✅ Пинг стабильный"
    elif [ "$PING_DELTA" -lt 30 ]  2>/dev/null; then
        echo -e "  ${WARN} Пинг вырос на ${PING_DELTA}ms — слегка заметно при высокой нагрузке"
        rlog "⚠️ Умеренная деградация"
    elif [ "$PING_DELTA" -lt 80 ]  2>/dev/null; then
        echo -e "  ${FAIL}  Пинг вырос на ${PING_DELTA}ms — пользователи почувствуют лаги"
        rlog "❌ Заметная деградация пинга"
    else
        echo -e "  ${FAIL}  Пинг вырос на ${PING_DELTA}ms — КРИТИЧНО, нода не справляется с нагрузкой"
        rlog "❌ КРИТИЧНО: деградация ${PING_DELTA}ms"
    fi
fi

# ══════════════════════════════════════════════════
# 6. СЕТЕВЫЕ ПРЕРЫВАНИЯ (INTERRUPTS)
# ══════════════════════════════════════════════════
print_section "6/7" "Сетевые прерывания — узкое место на слабых нодах"

echo -e "  ${INFO}  Измеряю прерывания сетевого интерфейса за 3 сек..."
rlog "Тест сетевых прерываний"

NET_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
if [ -z "$NET_IFACE" ]; then
    NET_IFACE=$(ip link | grep -v 'lo:' | grep 'UP' | head -1 | awk -F: '{print $2}' | xargs)
fi

echo -e "  ${INFO}  Интерфейс: ${BOLD}${NET_IFACE}${NC}"
rlog "Интерфейс: $NET_IFACE"

# Читаем interrupts дважды с интервалом
IRQ_LINE1=$(grep "$NET_IFACE\|eth0\|ens" /proc/interrupts 2>/dev/null | head -1)
INT1=$(echo "$IRQ_LINE1" | awk '{s=0; for(i=2;i<=NF-2;i++) s+=$i; print s}')

# Создаём трафик
curl -s -o /dev/null --max-time 5 https://speed.cloudflare.com/__down?bytes=10485760 \
    -A "Mozilla/5.0" 2>/dev/null &
sleep 3

IRQ_LINE2=$(grep "$NET_IFACE\|eth0\|ens" /proc/interrupts 2>/dev/null | head -1)
INT2=$(echo "$IRQ_LINE2" | awk '{s=0; for(i=2;i<=NF-2;i++) s+=$i; print s}')
wait 2>/dev/null

if [ -n "$INT1" ] && [ -n "$INT2" ] && [ "$INT1" -gt 0 ] 2>/dev/null; then
    INT_RATE=$(echo "$INT1 $INT2" | awk '{printf "%.0f", ($2-$1)/3}')
    echo -e "  ${INFO}  Прерываний/сек: ${BOLD}${INT_RATE}${NC}"
    rlog "Прерываний/сек: $INT_RATE"

    # При 1000+ юзерах ожидается 50k-200k прерываний/сек
    if   [ "$INT_RATE" -lt 10000 ] 2>/dev/null; then
        echo -e "  ${OK}  ${INT_RATE} irq/s — низкая нагрузка, запас большой"
        rlog "✅ Прерывания в норме"
    elif [ "$INT_RATE" -lt 100000 ] 2>/dev/null; then
        echo -e "  ${OK}  ${INT_RATE} irq/s — нормально для активной ноды"
        rlog "✅ Прерывания нормальные"
    elif [ "$INT_RATE" -lt 500000 ] 2>/dev/null; then
        echo -e "  ${WARN} ${INT_RATE} irq/s — высокая нагрузка на CPU от сети"
        rlog "⚠️ Высокие прерывания"
    else
        echo -e "  ${FAIL}  ${INT_RATE} irq/s — перегрузка, включи RSS/RPS для распределения по ядрам"
        rlog "❌ Критические прерывания"
    fi

    # Проверяем распределение по ядрам (SMP affinity)
    AFFINITY=$(cat /proc/irq/*/smp_affinity_list 2>/dev/null | sort -u | head -3)
    if echo "$AFFINITY" | grep -q ','; then
        echo -e "  ${OK}  IRQ распределены по нескольким ядрам (SMP affinity настроен)"
        rlog "✅ SMP affinity настроен"
    else
        echo -e "  ${WARN} IRQ обрабатываются одним ядром — при 500+ юзерах может стать узким местом"
        rlog "⚠️ SMP affinity не настроен"
    fi
else
    echo -e "  ${INFO}  Не удалось измерить прерывания напрямую"
    rlog "Прерывания не измерены"
fi

# ══════════════════════════════════════════════════
# 7. ИТОГОВЫЙ РАСЧЁТ
# ══════════════════════════════════════════════════
print_section "7/7" "Итоговый расчёт ёмкости ноды"

# Собираем все лимиты
[ "$CPU_USER_LIMIT"   -le 0 ] 2>/dev/null && CPU_USER_LIMIT=$((CPU_CORES * CPU_MHZ / 8))
[ "$IPERF_USER_LIMIT" -le 0 ] 2>/dev/null && IPERF_USER_LIMIT=266
[ "$FD_USER_LIMIT"    -le 0 ] 2>/dev/null && FD_USER_LIMIT=512

# RAM лимит
RAM_USER_LIMIT=$(echo "$RAM_AVAILABLE_FOR_XRAY" | awk '{printf "%.0f", $1/0.012}')  # ~12KB/соед

echo -e "  ${BOLD}Сводка лимитов:${NC}"
echo -e "  ${DIM}┌──────────────────────────────────────────────┐${NC}"
echo -e "  ${DIM}│${NC}  По CPU (шифрование):     ~${BOLD}${CPU_USER_LIMIT}${NC} соединений"
echo -e "  ${DIM}│${NC}  По RAM:                  ~${BOLD}${RAM_USER_LIMIT}${NC} соединений"
echo -e "  ${DIM}│${NC}  По каналу:               ~${BOLD}${IPERF_USER_LIMIT}${NC} активных юзеров"
echo -e "  ${DIM}│${NC}  По file descriptors:     ~${BOLD}${FD_USER_LIMIT}${NC} соединений (ulimit)"
echo -e "  ${DIM}└──────────────────────────────────────────────┘${NC}"

rlog "Лимиты: CPU ~${CPU_USER_LIMIT} | RAM ~${RAM_USER_LIMIT} | Канал ~${IPERF_USER_LIMIT} | FD ~${FD_USER_LIMIT}"

# Узкое место
BOTTLENECK=$CPU_USER_LIMIT; BOTTLENECK_NAME="CPU"

check_bottleneck() {
    local VAL=$1 NAME=$2
    [ -n "$VAL" ] && [ "$VAL" -gt 0 ] && [ "$VAL" -lt "$BOTTLENECK" ] 2>/dev/null && {
        BOTTLENECK=$VAL
        BOTTLENECK_NAME=$NAME
    }
}
check_bottleneck "$RAM_USER_LIMIT"   "RAM"
check_bottleneck "$IPERF_USER_LIMIT" "Канал"
check_bottleneck "$FD_USER_LIMIT"    "File Descriptors (ulimit)"

# Реальных подписчиков ~5-10x от одновременных онлайн
REAL_USERS_LOW=$((BOTTLENECK * 5))
REAL_USERS_HIGH=$((BOTTLENECK * 10))

# Порог для добавления ноды
SCALE_75=$((BOTTLENECK * 75 / 100))
SCALE_90=$((BOTTLENECK * 90 / 100))

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

if   [ "$BOTTLENECK" -gt 2000 ] 2>/dev/null; then
    TIER="${GREEN}${BOLD}🚀 МОЩНАЯ НОДА${NC}"; TIER_TEXT="Потянет крупный проект"
elif [ "$BOTTLENECK" -gt 800  ] 2>/dev/null; then
    TIER="${GREEN}${BOLD}💪 ХОРОШАЯ НОДА${NC}"; TIER_TEXT="Комфортная нагрузка"
elif [ "$BOTTLENECK" -gt 300  ] 2>/dev/null; then
    TIER="${YELLOW}${BOLD}👍 СРЕДНЯЯ НОДА${NC}"; TIER_TEXT="Подходит для старта"
else
    TIER="${RED}${BOLD}⚡ СЛАБАЯ НОДА${NC}"; TIER_TEXT="Только для тестирования"
fi

echo -e "  $TIER — $TIER_TEXT"
echo ""
echo -e "  ${BOLD}Узкое место:                 $BOTTLENECK_NAME${NC}"
echo -e "  ${BOLD}Одновременных соединений:   ~${BOTTLENECK}${NC}"
echo -e "  ${BOLD}Реальных подписчиков:        ~${REAL_USERS_LOW} – ${REAL_USERS_HIGH}${NC}"
echo -e "  ${DIM}(при активности 10-20% онлайн одновременно)${NC}"
echo ""
echo -e "  ${BOLD}Когда добавлять следующую ноду:${NC}"
echo -e "  ${DIM}┌─────────────────────────────────────────────────┐${NC}"
echo -e "  ${DIM}│${NC}  ${YELLOW}⚠️  При ${SCALE_75} онлайн${NC} — готовь вторую ноду"
echo -e "  ${DIM}│${NC}  ${RED}🔴 При ${SCALE_90} онлайн${NC} — срочно добавляй ноду"
echo -e "  ${DIM}└─────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "  Тест занял: ${DIM}${ELAPSED} сек${NC}"
echo ""

rlog ""
rlog "══════════════════ ЁМКОСТЬ НОДЫ ══════════════════"
rlog "Узкое место: $BOTTLENECK_NAME"
rlog "Одновременных соединений: ~${BOTTLENECK}"
rlog "Реальных подписчиков:     ~${REAL_USERS_LOW} – ${REAL_USERS_HIGH}"
rlog "Добавить ноду при: ${SCALE_75} онлайн / срочно при ${SCALE_90}"

{
    echo "=================================================="
    echo " HataVPN Node Load Tester v2.0"
    echo " Дата:  $(date '+%Y-%m-%d %H:%M:%S UTC')"
    echo " Хост:  $(hostname)"
    echo "=================================================="
    echo ""
    for line in "${REPORT_LINES[@]}"; do echo "$line"; done
} > "$REPORT_FILE"

echo -e "  ${CYAN}📄 Отчёт: ${BOLD}$REPORT_FILE${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo ""
