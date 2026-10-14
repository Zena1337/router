#!/data/data/com.termux/files/usr/bin/bash

set -e

PORT=8080
SERVER_DIR="$HOME/home-server"
CGI_DIR="$SERVER_DIR/cgi-bin"

echo "================================"
echo "     ANDROID HOME SERVER"
echo "================================"

# Update dan instal kebutuhan
pkg update -y
pkg install -y python openssh iproute2 procps

# Membuat folder server & cgi-bin
mkdir -p "$SERVER_DIR"
mkdir -p "$CGI_DIR"

# ======================
# Fungsi: baca info sistem
# ======================
cat > "$SERVER_DIR/info.sh" <<'SH'
#!/data/data/com.termux/files/usr/bin/bash
# Output: JSON berisi RAM, Disk, Network

# ---- RAM ----
RAM_TOTAL=$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo)
RAM_AVAIL=$(awk '/MemAvailable/ {printf "%.0f", $2/1024}' /proc/meminfo)
RAM_USED=$((RAM_TOTAL - RAM_AVAIL))
RAM_PCT=$(awk "BEGIN {printf \"%.1f\", ($RAM_USED/$RAM_TOTAL)*100}")

# ---- DISK (root / data) ----
DISK_INFO=$(df -k "$HOME" | awk 'NR==2 {print $2, $3, $4}')
DISK_TOTAL=$(echo "$DISK_INFO" | awk '{printf "%.1f", $1/1024/1024}')
DISK_USED=$(echo "$DISK_INFO"  | awk '{printf "%.1f", $2/1024/1024}')
DISK_FREE=$(echo "$DISK_INFO"  | awk '{printf "%.1f", $3/1024/1024}')
DISK_PCT=$(awk "BEGIN {printf \"%.1f\", ($DISK_USED/$DISK_TOTAL)*100}")

# ---- NETWORK SPEED (sample 1 detik) ----
IFACE=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
[ -z "$IFACE" ] && IFACE="wlan0"

RX1=$(cat /sys/class/net/$IFACE/statistics/rx_bytes 2>/dev/null || echo 0)
TX1=$(cat /sys/class/net/$IFACE/statistics/tx_bytes 2>/dev/null || echo 0)
sleep 1
RX2=$(cat /sys/class/net/$IFACE/statistics/rx_bytes 2>/dev/null || echo 0)
TX2=$(cat /sys/class/net/$IFACE/statistics/tx_bytes 2>/dev/null || echo 0)

RX_MBPS=$(awk "BEGIN {printf \"%.2f\", (($RX2-$RX1)*8)/1000000}")
TX_MBPS=$(awk "BEGIN {printf \"%.2f\", (($TX2-$TX1)*8)/1000000}")

cat <<JSON
{
  "ram":   {"total": $RAM_TOTAL, "used": $RAM_USED, "avail": $RAM_AVAIL, "pct": $RAM_PCT},
  "disk":  {"total": $DISK_TOTAL, "used": $DISK_USED, "free": $DISK_FREE, "pct": $DISK_PCT},
  "net":   {"iface": "$IFACE", "rx": $RX_MBPS, "tx": $TX_MBPS}
}
JSON
SH
chmod +x "$SERVER_DIR/info.sh"

# ======================
# Halaman web
# ======================
cat > "$SERVER_DIR/index.html" <<'HTML'
<!DOCTYPE html>
<html lang="id">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Home Server</title>
  <style>
    * { box-sizing: border-box; }
    body {
      font-family: system-ui, sans-serif;
      background: #101827;
      color: #e2e8f0;
      margin: 0;
      padding: 24px 16px;
    }
    .wrap { max-width: 640px; margin: auto; }
    h1 { color: #4ade80; text-align: center; margin-bottom: 4px; }
    .sub { text-align: center; color: #94a3b8; margin-bottom: 24px; font-size: 14px; }
    .card {
      background: #1e293b;
      border-radius: 14px;
      padding: 18px 20px;
      margin-bottom: 14px;
      box-shadow: 0 4px 14px rgba(0,0,0,.3);
    }
    .card h2 {
      margin: 0 0 12px;
      font-size: 15px;
      color: #93c5fd;
      text-transform: uppercase;
      letter-spacing: .5px;
    }
    .row { display: flex; justify-content: space-between; margin: 6px 0; font-size: 14px; }
    .val { color: #f1f5f9; font-weight: 600; }
    .bar {
      height: 8px;
      border-radius: 4px;
      background: #334155;
      overflow: hidden;
      margin-top: 10px;
    }
    .fill {
      height: 100%;
      width: 0%;
      background: linear-gradient(90deg,#22c55e,#4ade80);
      transition: width .4s ease;
    }
    .fill.warn { background: linear-gradient(90deg,#f59e0b,#fbbf24); }
    .fill.crit { background: linear-gradient(90deg,#ef4444,#f87171); }
    .net-grid { display: flex; gap: 12px; }
    .net-box {
      flex: 1;
      background: #0f172a;
      border-radius: 10px;
      padding: 12px;
      text-align: center;
    }
    .net-box .num { font-size: 22px; font-weight: 700; color: #4ade80; }
    .net-box .lbl { font-size: 12px; color: #94a3b8; margin-top: 2px; }
    .footer { text-align: center; font-size: 12px; color: #64748b; margin-top: 20px; }
    .dot {
      display: inline-block; width: 8px; height: 8px;
      border-radius: 50%; background: #22c55e; margin-right: 6px;
      animation: pulse 1.5s infinite;
    }
    @keyframes pulse { 0%,100%{opacity:1} 50%{opacity:.4} }
  </style>
</head>
<body>
  <div class="wrap">
    <h1>Home Server Aktif!</h1>
    <div class="sub"><span class="dot"></span>Server berjalan dari HP Android</div>

    <div class="card">
      <h2>🧠 RAM</h2>
      <div class="row"><span>Total</span><span class="val" id="ram-total">-</span></div>
      <div class="row"><span>Terpakai</span><span class="val" id="ram-used">-</span></div>
      <div class="row"><span>Tersedia</span><span class="val" id="ram-avail">-</span></div>
      <div class="row"><span>Pemakaian</span><span class="val" id="ram-pct">-</span></div>
      <div class="bar"><div class="fill" id="ram-bar"></div></div>
    </div>

    <div class="card">
      <h2>💾 Disk</h2>
      <div class="row"><span>Total</span><span class="val" id="disk-total">-</span></div>
      <div class="row"><span>Terpakai</span><span class="val" id="disk-used">-</span></div>
      <div class="row"><span>Kosong</span><span class="val" id="disk-free">-</span></div>
      <div class="row"><span>Pemakaian</span><span class="val" id="disk-pct">-</span></div>
      <div class="bar"><div class="fill" id="disk-bar"></div></div>
    </div>

    <div class="card">
      <h2>🌐 Jaringan <span id="iface" style="color:#64748b;font-size:12px;text-transform:none"></span></h2>
      <div class="net-grid">
        <div class="net-box">
          <div class="num" id="rx">-</div>
          <div class="lbl">⬇ Download (Mbps)</div>
        </div>
        <div class="net-box">
          <div class="num" id="tx">-</div>
          <div class="lbl">⬆ Upload (Mbps)</div>
        </div>
      </div>
    </div>

    <div class="footer">Auto-refresh setiap 2 detik</div>
  </div>

<script>
function setBar(id, pct) {
  const el = document.getElementById(id);
  el.style.width = Math.min(pct, 100) + '%';
  el.className = 'fill' + (pct > 85 ? ' crit' : pct > 65 ? ' warn' : '');
}

async function refresh() {
  try {
    const r = await fetch('/info.json?t=' + Date.now());
    const d = await r.json();

    document.getElementById('ram-total').textContent = d.ram.total + ' MB';
    document.getElementById('ram-used').textContent  = d.ram.used  + ' MB';
    document.getElementById('ram-avail').textContent = d.ram.avail + ' MB';
    document.getElementById('ram-pct').textContent   = d.ram.pct   + ' %';
    setBar('ram-bar', d.ram.pct);

    document.getElementById('disk-total').textContent = d.disk.total + ' GB';
    document.getElementById('disk-used').textContent  = d.disk.used  + ' GB';
    document.getElementById('disk-free').textContent  = d.disk.free  + ' GB';
    document.getElementById('disk-pct').textContent   = d.disk.pct   + ' %';
    setBar('disk-bar', d.disk.pct);

    document.getElementById('iface').textContent = '(' + d.net.iface + ')';
    document.getElementById('rx').textContent = d.net.rx.toFixed(2);
    document.getElementById('tx').textContent = d.net.tx.toFixed(2);
  } catch(e) { console.error(e); }
}

refresh();
setInterval(refresh, 2000);
</script>
</body>
</html>
HTML

# ======================
# Server Python dengan endpoint /info.json
# ======================
cat > "$SERVER_DIR/server.py" <<'PY'
#!/usr/bin/env python3
import http.server, socketserver, subprocess, os, json

PORT = 8080
DIRECTORY = os.path.dirname(os.path.abspath(__file__))

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def do_GET(self):
        if self.path.startswith("/info.json"):
            try:
                out = subprocess.check_output(
                    [os.path.join(DIRECTORY, "info.sh")],
                    timeout=5
                )
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(out)
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(str(e).encode())
            return
        super().do_GET()

    def log_message(self, fmt, *args):
        pass  # senyapkan log

socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
    print(f"Server berjalan di port {PORT}")
    httpd.serve_forever()
PY
chmod +x "$SERVER_DIR/server.py"

# ======================
# Deteksi IP lokal
# ======================
IP=$(ip -4 route get 1.1.1.1 2>/dev/null |
  awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')

if [ -z "$IP" ]; then
  IP=$(ip -4 addr show wlan0 2>/dev/null |
    awk '/inet / {sub(/\/.*/, "", $2); print $2; exit}')
fi

echo
echo "Folder server : $SERVER_DIR"
echo "Port          : $PORT"
echo "IP lokal      : ${IP:-Tidak terdeteksi}"
echo
echo "Buka browser perangkat lain:"
echo "http://${IP:-IP-HP-SERVER}:$PORT"
echo
echo "Tekan CTRL+C untuk menghentikan server."
echo

cd "$SERVER_DIR"
exec python server.py
