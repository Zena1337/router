#!/data/data/com.termux/files/usr/bin/bash

set -e
PORT=8080
SERVER_DIR="$HOME/home-server"

echo "===== ANDROID HOME SERVER ====="
pkg update -y
pkg install -y python openssh iproute2 procps
mkdir -p "$SERVER_DIR"

# ============================================================
# info.sh — FIX TOTAL
# ============================================================
cat > "$SERVER_DIR/info.sh" <<'SH'
#!/data/data/com.termux/files/usr/bin/bash

# ---- CPU via top (paling andal di Termux) ----
CPU_PCT="0.0"
TOP_OUT=$(top -bn1 2>/dev/null | head -10)
if [ -n "$TOP_OUT" ]; then
  # Coba berbagai format top: cari token yang mengandung "id" (idle)
  IDLE=$(echo "$TOP_OUT" | tr ',' '\n' | grep -iE '[0-9.]+[[:space:]]*id' | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
  if [ -n "$IDLE" ]; then
    CPU_PCT=$(awk "BEGIN {p=100-$IDLE; if(p<0)p=0; if(p>100)p=100; printf \"%.1f\", p}")
  fi
fi

# Fallback loadavg kalau top gagal
if [ "$CPU_PCT" = "0.0" ] || [ -z "$CPU_PCT" ]; then
  LA=$(cat /proc/loadavg 2>/dev/null | awk '{print $1}')
  CORES=$(nproc 2>/dev/null || echo 1)
  if [ -n "$LA" ] && [ "$CORES" -gt 0 ] 2>/dev/null; then
    CPU_PCT=$(awk "BEGIN {p=($LA/$CORES)*100; if(p>100)p=100; printf \"%.1f\", p}")
  fi
fi

# ---- Processor ----
CPU_MODEL=$(getprop ro.soc.model 2>/dev/null)
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(getprop ro.board.platform 2>/dev/null)
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(getprop ro.product.board 2>/dev/null)
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(getprop ro.hardware 2>/dev/null)
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(grep -m1 -i 'hardware' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ *//')
[ -z "$CPU_MODEL" ] && CPU_MODEL="Unknown"

CPU_ARCH=$(uname -m)
CPU_CORES=$(nproc 2>/dev/null || echo 1)

CPU_FREQ_MHZ=0
CPU_FREQ_MAX_MHZ=0
for f in /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq \
         /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_cur_freq; do
  if [ -r "$f" ]; then
    V=$(cat "$f" 2>/dev/null)
    if [ -n "$V" ] && [ "$V" -gt 0 ] 2>/dev/null; then
      CPU_FREQ_MHZ=$((V/1000)); break
    fi
  fi
done
for f in /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq \
         /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq; do
  if [ -r "$f" ]; then
    V=$(cat "$f" 2>/dev/null)
    if [ -n "$V" ] && [ "$V" -gt 0 ] 2>/dev/null; then
      CPU_FREQ_MAX_MHZ=$((V/1000)); break
    fi
  fi
done

# ---- RAM ----
RAM_TOTAL=0; RAM_AVAIL=0; RAM_FREE=0
if [ -r /proc/meminfo ]; then
  RAM_TOTAL=$(awk '/^MemTotal:/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null)
  RAM_AVAIL=$(awk '/^MemAvailable:/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null)
  RAM_FREE=$(awk '/^MemFree:/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null)
fi

# Fallback: pakai free
if [ -z "$RAM_TOTAL" ] || [ "$RAM_TOTAL" = "0" ]; then
  FREE_OUT=$(free -m 2>/dev/null | awk '/^Mem:/ {print $2, $7, $4}')
  if [ -n "$FREE_OUT" ]; then
    RAM_TOTAL=$(echo "$FREE_OUT" | awk '{print $1}')
    RAM_AVAIL=$(echo "$FREE_OUT" | awk '{print $2}')
    RAM_FREE=$(echo "$FREE_OUT" | awk '{print $3}')
  fi
fi

RAM_TOTAL=${RAM_TOTAL:-0}
RAM_AVAIL=${RAM_AVAIL:-0}
RAM_FREE=${RAM_FREE:-0}
[ "$RAM_AVAIL" = "0" ] && RAM_AVAIL=$RAM_FREE

if [ "$RAM_TOTAL" -gt 0 ] 2>/dev/null; then
  RAM_USED=$((RAM_TOTAL - RAM_AVAIL))
  RAM_PCT=$(awk "BEGIN {printf \"%.1f\", ($RAM_USED/$RAM_TOTAL)*100}")
else
  RAM_USED=0
  RAM_PCT="0.0"
fi

# ---- Disk ----
DISK_TOTAL=0; DISK_USED=0; DISK_FREE=0; DISK_PCT="0.0"
DF_LINE=$(df -k "$HOME" 2>/dev/null | tail -n +2 | head -1)
if [ -n "$DF_LINE" ]; then
  DT=$(echo "$DF_LINE" | awk '{print $2}')
  DU=$(echo "$DF_LINE" | awk '{print $3}')
  DF_=$(echo "$DF_LINE" | awk '{print $4}')
  if [ -n "$DT" ] && [ "$DT" -gt 0 ] 2>/dev/null; then
    DISK_TOTAL=$(awk "BEGIN {printf \"%.1f\", $DT/1024/1024}")
    DISK_USED=$(awk  "BEGIN {printf \"%.1f\", $DU/1024/1024}")
    DISK_FREE=$(awk  "BEGIN {printf \"%.1f\", $DF_/1024/1024}")
    DISK_PCT=$(awk   "BEGIN {printf \"%.1f\", ($DU/$DT)*100}")
  fi
fi

# ---- Network ----
IFACE=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
[ -z "$IFACE" ] && IFACE="wlan0"

RX1=0; TX1=0; RX2=0; TX2=0
[ -r "/sys/class/net/$IFACE/statistics/rx_bytes" ] && RX1=$(cat "/sys/class/net/$IFACE/statistics/rx_bytes" 2>/dev/null)
[ -r "/sys/class/net/$IFACE/statistics/tx_bytes" ] && TX1=$(cat "/sys/class/net/$IFACE/statistics/tx_bytes" 2>/dev/null)
sleep 0.5
[ -r "/sys/class/net/$IFACE/statistics/rx_bytes" ] && RX2=$(cat "/sys/class/net/$IFACE/statistics/rx_bytes" 2>/dev/null)
[ -r "/sys/class/net/$IFACE/statistics/tx_bytes" ] && TX2=$(cat "/sys/class/net/$IFACE/statistics/tx_bytes" 2>/dev/null)

RX1=${RX1:-0}; TX1=${TX1:-0}; RX2=${RX2:-0}; TX2=${TX2:-0}
RX_MBPS=$(awk "BEGIN {printf \"%.2f\", (($RX2-$RX1)*8)/500000}")
TX_MBPS=$(awk "BEGIN {printf \"%.2f\", (($TX2-$TX1)*8)/500000}")

cat <<JSON
{
  "cpu": {"pct": $CPU_PCT, "cores": $CPU_CORES, "freq": $CPU_FREQ_MHZ, "freq_max": $CPU_FREQ_MAX_MHZ, "model": "$CPU_MODEL", "arch": "$CPU_ARCH"},
  "ram": {"total": $RAM_TOTAL, "used": $RAM_USED, "avail": $RAM_AVAIL, "pct": $RAM_PCT},
  "disk": {"total": $DISK_TOTAL, "used": $DISK_USED, "free": $DISK_FREE, "pct": $DISK_PCT},
  "net": {"iface": "$IFACE", "rx": $RX_MBPS, "tx": $TX_MBPS}
}
JSON
SH
chmod +x "$SERVER_DIR/info.sh"

echo
echo "=== TEST info.sh ==="
bash "$SERVER_DIR/info.sh"
echo
echo "===================="
