#!/bin/bash
# ============================================================
#  HataVPN — Автоустановка ноды v2.0
#  bash <(curl -sL https://raw.githubusercontent.com/mashiahzzx/hatavpn-node-check/main/hatavpn-node-install.sh)
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[→]${NC} $1"; }

clear
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║         HataVPN Node Installer v2.0             ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# ============================================================
# Валидация ввода
# ============================================================
ask() {
  local prompt="$1"
  local var=""
  while [ -z "$var" ]; do
    read -p "$prompt: " var
    [ -z "$var" ] && echo -e "${YELLOW}[!]${NC} Поле не может быть пустым"
  done
  echo "$var"
}

ask_url() {
  local var=""
  while true; do
    read -p "URL панели (https://...): " var
    [[ "$var" =~ ^https?:// ]] && break
    echo -e "${YELLOW}[!]${NC} URL должен начинаться с http:// или https://"
  done
  echo "$var"
}

ask_node() {
  echo -e "\nВыбери тип ноды:"
  echo "  1) nl1 — Netherlands #1"
  echo "  2) nl2 — Netherlands #2"
  echo "  3) nl3 — Netherlands #3"
  echo "  4) nl4 — Netherlands #4"
  echo "  5) ru1 — Russia #1"
  echo "  6) Ввести вручную"
  local choice=""
  while true; do
    read -p "Выбор [1-6]: " choice
    case $choice in
      1) echo "nl1"; return ;;
      2) echo "nl2"; return ;;
      3) echo "nl3"; return ;;
      4) echo "nl4"; return ;;
      5) echo "ru1"; return ;;
      6) ask "Имя ноды"; return ;;
      *) echo -e "${YELLOW}[!]${NC} Введи число от 1 до 6" ;;
    esac
  done
}

ask_ssh_port() {
  local port=""
  while true; do
    read -p "SSH порт [по умолчанию 2222]: " port
    port="${port:-2222}"
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1024 ] && [ "$port" -le 65535 ]; then
      echo "$port"; return
    fi
    echo -e "${YELLOW}[!]${NC} Порт должен быть от 1024 до 65535"
  done
}

# ============================================================
# Сбор параметров
# ============================================================
echo -e "${BLUE}Настройка ноды:${NC}\n"

PANEL_URL=$(ask_url)
SECRET_KEY=$(ask "SECRET_KEY из Remnawave панели")
NODE_NAME=$(ask_node)
PANEL_IP=$(ask "IP адрес панели (для Prometheus, например 77.110.111.122)")
SSH_PORT=$(ask_ssh_port)

NODE_PORT="39381"
SERVICE_PORT="38119"

echo ""
echo -e "${CYAN}Параметры установки:${NC}"
echo "  Нода:       $NODE_NAME"
echo "  Панель:     $PANEL_URL"
echo "  Panel IP:   $PANEL_IP"
echo "  SSH порт:   $SSH_PORT"
echo ""
read -p "Всё верно? [y/N]: " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || err "Установка отменена"
echo ""

# ============================================================
# 1. Обновление системы
# ============================================================
info "Обновление системы..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq curl wget git ufw fail2ban
log "Система обновлена"

# ============================================================
# 2. Hostname
# ============================================================
hostnamectl set-hostname "$NODE_NAME"
log "Hostname: $NODE_NAME"

# ============================================================
# 3. SSH: смена порта
# ============================================================
info "Настройка SSH (порт $SSH_PORT)..."

if grep -q "^Port " /etc/ssh/sshd_config; then
  sed -i "s/^Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
elif grep -q "^#Port " /etc/ssh/sshd_config; then
  sed -i "s/^#Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
else
  echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
fi

# Отключаем пароль только если есть authorized_keys
if [ -f ~/.ssh/authorized_keys ] && [ -s ~/.ssh/authorized_keys ]; then
  sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  log "Вход по паролю отключён (найден authorized_keys)"
else
  warn "authorized_keys пустой — вход по паролю оставлен"
  warn "После добавления ключа выполни:"
  warn "  sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config && systemctl restart sshd"
fi

systemctl restart sshd
log "SSH порт: $SSH_PORT"

# ============================================================
# 4. Docker
# ============================================================
if ! command -v docker &> /dev/null; then
  info "Установка Docker..."
  curl -fsSL https://get.docker.com | sh -qq
  systemctl enable docker
  systemctl start docker
  log "Docker установлен"
else
  log "Docker уже установлен"
fi

cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  }
}
EOF
systemctl restart docker
log "Ротация логов Docker: 50MB x 3"

# ============================================================
# 5. Remnawave Node
# ============================================================
info "Установка Remnawave Node..."
mkdir -p /opt/remnanode
cd /opt/remnanode

cat > docker-compose.yml << EOF
services:
  remnanode:
    container_name: remnanode
    hostname: ${NODE_NAME}
    image: remnawave/node:latest
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - NODE_PORT=${NODE_PORT}
      - SECRET_KEY=${SECRET_KEY}
EOF

docker compose pull -q
docker compose up -d
sleep 5

if docker ps | grep -q remnanode; then
  log "Remnawave Node запущен ✅"
else
  err "Remnawave Node не запустился — проверь SECRET_KEY и попробуй: cd /opt/remnanode && docker compose logs"
fi

# ============================================================
# 6. Node Exporter
# ============================================================
info "Установка Node Exporter..."
docker rm -f node-exporter 2>/dev/null || true
docker run -d \
  --name node-exporter \
  --restart always \
  --network host \
  prom/node-exporter:latest
log "Node Exporter: порт 9100"

# ============================================================
# 7. Fail2ban
# ============================================================
info "Настройка Fail2ban..."
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime  = 24h
findtime = 10m
maxretry = 3
ignoreip = 127.0.0.1/8

[sshd]
enabled  = true
port     = $SSH_PORT
maxretry = 3
EOF

systemctl enable fail2ban
systemctl restart fail2ban
log "Fail2ban: 3 попытки → бан 24ч"

# ============================================================
# 8. UFW
# ============================================================
info "Настройка UFW..."
ufw --force reset > /dev/null
ufw default deny incoming > /dev/null
ufw default allow outgoing > /dev/null
ufw allow "$SSH_PORT/tcp" > /dev/null
ufw allow "$SERVICE_PORT/tcp" > /dev/null
ufw allow "$NODE_PORT/tcp" > /dev/null
ufw allow "9100/tcp" > /dev/null
ufw --force enable > /dev/null
log "UFW: SSH($SSH_PORT), VLESS($SERVICE_PORT), Node($NODE_PORT), Metrics(9100)"

# ============================================================
# 9. Автодобавление в Prometheus
# ============================================================
info "Добавление в Prometheus..."
NODE_IP=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

PROMETHEUS_CONF="/etc/dokploy/compose/panel-remnawave-grafana-dfofjh/files/prometheus.yml"

if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes root@$PANEL_IP "test -f $PROMETHEUS_CONF" 2>/dev/null; then
  ssh -o StrictHostKeyChecking=no root@$PANEL_IP bash << SSHEOF
if ! grep -q 'job_name: "$NODE_NAME"' "$PROMETHEUS_CONF"; then
  printf '\n  - job_name: "$NODE_NAME"\n    static_configs:\n      - targets: ["%s:9100"]\n' "$NODE_IP" >> "$PROMETHEUS_CONF"
  docker restart prometheus 2>/dev/null || true
  echo "✅ $NODE_NAME добавлен в Prometheus"
else
  echo "ℹ️  $NODE_NAME уже есть в Prometheus"
fi
SSHEOF
  log "Prometheus обновлён"
else
  warn "Не удалось подключиться к панели — добавь вручную в prometheus.yml:"
  echo ""
  echo "  - job_name: '$NODE_NAME'"
  echo "    static_configs:"
  echo "      - targets: ['$NODE_IP:9100']"
  echo ""
fi

# ============================================================
# Сохраняем конфиг
# ============================================================
cat > /opt/remnanode/.env << EOF
NODE_NAME=$NODE_NAME
NODE_PORT=$NODE_PORT
SERVICE_PORT=$SERVICE_PORT
SECRET_KEY=$SECRET_KEY
PANEL_URL=$PANEL_URL
PANEL_IP=$PANEL_IP
SSH_PORT=$SSH_PORT
NODE_IP=$NODE_IP
INSTALL_DATE=$(date +%Y-%m-%d)
EOF

# ============================================================
# Итог
# ============================================================
echo ""
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════╗"
printf "║      ✅  Нода %-10s установлена!          ║\n" "$NODE_NAME"
echo "╠══════════════════════════════════════════════════╣"
printf "║  IP:             %-31s║\n" "$NODE_IP"
printf "║  SSH порт:       %-31s║\n" "$SSH_PORT"
printf "║  VLESS порт:     %-31s║\n" "$SERVICE_PORT"
printf "║  Remnawave порт: %-31s║\n" "$NODE_PORT"
printf "║  Node Exporter:  %-31s║\n" "9100"
echo "╠══════════════════════════════════════════════════╣"
echo "║  Добавь ноду в Remnawave панель и назначь        ║"
echo "║  хосты на неё.                                   ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

docker ps --format "table {{.Names}}\t{{.Status}}"
