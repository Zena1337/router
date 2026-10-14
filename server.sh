#!/data/data/com.termux/files/usr/bin/bash

set -e

PORT=8080
SERVER_DIR="$HOME/home-server"

echo "================================"
echo "     ANDROID HOME SERVER"
echo "================================"

# Update dan instal kebutuhan
pkg update -y
pkg install -y python openssh iproute2 procps

# Membuat folder server
mkdir -p "$SERVER_DIR"

# ======================
# Fungsi: baca info sistem
# ======================
cat > "$SERVER_DIR/info.sh" <<'SH'
#!/data/data/com.termux/files/usr/bin/bash
# Output: JSON berisi CPU, RAM, Disk, Network

# ---- CPU (sample /proc/stat 2x) ----
read_cpu() {
  awk '/^cpu / {print $2, $3, $4, $5, $6, $7, $8}' /proc/stat
}

CPU1=$(read_cpu)
sleep 0.5
CPU2=$(read_cpu)

CPU_PCT=$(echo "$CPU1 $CPU2" | awk '
{
  # idle = kolom 4 (idle) + kolom 5 (iowait)
  idle1 = $4 + $5
  idle2 = $9 + $10

  total1 = $1+$2+$3+$4+$5+$6+$7
  total2 = $8+$9+$10+$11+$12+$13+$14

  dt = total2 - total1
  di = idle2 - idle1

  if (dt <= 0) { print "0.0"; exit }
  printf "%.1f", (1 - di/dt) * 100
}')

# Jumlah core
CPU_CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)

# Frekuensi CPU (kalau tersedia)
CPU_FREQ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo 0)
CPU_FREQ_MHZ=$(awk "BEGIN {printf \"%.0f\", $CPU_FREQ/1000}")

# ---- RAM ----
RAM_TOTAL=$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo)
RAM_AVAIL=$(awk '/MemAvailable/ {printf "%.0f", $2/1024}' /proc/meminfo)
RAM_USED=$((RAM_TOTAL - RAM_AVAIL))
RAM_PCT=$(awk "BEGIN {printf \"%.1f\", ($RAM_USED/$RAM_TOTAL)*100}")

# ---- DISK ----
DISK_INFO=$(df -k "$HOME" | awk 'NR==2 {print $2, $3, $4}')
DISK_TOTAL=$(echo "$DISK_INFO" | awk '{printf "%.1f", $1/1024/1024}')
DISK_USED=$(echo "$DISK_INFO"  | awk '{printf "%.1f", $2/1024/1024}')
DISK_FREE=$(echo "$DISK_INFO"  | awk '{printf "%.1f", $3/1024/1024}')
DISK_PCT=$(awk "BEGIN {printf \"%.1f\", ($DISK_USED/$DISK_TOTAL)*100}")

# ---- NETWORK ----
IFACE=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
[ -z "$IFACE" ] && IFACE="wlan0"

RX1=$(cat /sys/class/net/$IFACE/statistics/rx_bytes 2>/dev/null || echo 0)
TX1=$(cat /sys/class/net/$IFACE/statistics/tx_bytes 2>/dev/null || echo 0)
sleep 0.5
RX2=$(cat /sys/class/net/$IFACE/statistics/rx_bytes 2>/dev/null || echo 0)
TX2=$(cat /sys/class/net/$IFACE/statistics/tx_bytes 2>/dev/null || echo 0)

RX_MBPS=$(awk "BEGIN {printf \"%.2f\", (($RX2-$RX1)*8)/500000}")
TX_MBPS=$(awk "BEGIN {printf \"%.2f\", (($TX2-$TX1)*8)/500000}")

cat <<JSON
{
  "cpu":  {"pct": $CPU_PCT, "cores": $CPU_CORES, "freq": $CPU_FREQ_MHZ},
  "ram":  {"total": $RAM_TOTAL, "used": $RAM_USED, "avail": $RAM_AVAIL, "pct": $RAM_PCT},
  "disk": {"total": $DISK_TOTAL, "used": $DISK_USED, "free": $DISK_FREE, "pct": $DISK_PCT},
  "net":  {"iface": "$IFACE", "rx": $RX_MBPS, "tx": $TX_MBPS}
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
  <title>Home Server · Dashboard</title>
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
  <style>
    :root {
      --bg: #0b1120;
      --card: #111c33;
      --card-2: #0f172a;
      --border: #1e293b;
      --text: #e2e8f0;
      --muted: #94a3b8;
      --accent: #22d3ee;
      --green: #4ade80;
      --amber: #fbbf24;
      --red: #f87171;
      --blue: #60a5fa;
      --purple: #a78bfa;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
      background: radial-gradient(circle at top, #1e293b 0%, var(--bg) 60%);
      color: var(--text);
      min-height: 100vh;
      padding: 24px 16px;
    }
    .wrap { max-width: 720px; margin: 0 auto; }

    /* Header */
    header {
      text-align: center;
      margin-bottom: 28px;
    }
    .logo {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 64px; height: 64px;
      border-radius: 18px;
      background: linear-gradient(135deg, #06b6d4, #3b82f6);
      box-shadow: 0 8px 24px rgba(6,182,212,.35);
      font-size: 28px;
      color: white;
      margin-bottom: 12px;
    }
    h1 {
      font-size: 22px;
      font-weight: 700;
      letter-spacing: -.3px;
      background: linear-gradient(90deg, #22d3ee, #4ade80);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      background-clip: text;
    }
    .sub {
      font-size: 13px;
      color: var(--muted);
      margin-top: 6px;
      display: inline-flex;
      align-items: center;
      gap: 6px;
    }
    .dot {
      width: 8px; height: 8px;
      border-radius: 50%;
      background: var(--green);
      box-shadow: 0 0 10px var(--green);
      animation: pulse 1.6s infinite;
    }
    @keyframes pulse {
      0%,100% { opacity: 1; transform: scale(1); }
      50%     { opacity: .5; transform: scale(.85); }
    }

    /* Grid */
    .grid {
      display: grid;
      grid-template-columns: 1fr;
      gap: 14px;
    }
    @media (min-width: 600px) {
      .grid { grid-template-columns: 1fr 1fr; }
      .card.full { grid-column: 1 / -1; }
    }

    /* Card */
    .card {
      background: linear-gradient(160deg, var(--card) 0%, var(--card-2) 100%);
      border: 1px solid var(--border);
      border-radius: 16px;
      padding: 18px;
      position: relative;
      overflow: hidden;
    }
    .card::before {
      content: '';
      position: absolute;
      top: 0; left: 0; right: 0;
      height: 2px;
      background: linear-gradient(90deg, transparent, var(--accent), transparent);
      opacity: .5;
    }
    .card-head {
      display: flex;
      align-items: center;
      gap: 10px;
      margin-bottom: 14px;
    }
    .card-head i {
      width: 34px; height: 34px;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      border-radius: 10px;
      font-size: 15px;
      color: white;
    }
    .ic-cpu  { background: linear-gradient(135deg,#8b5cf6,#a78bfa); }
    .ic-ram  { background: linear-gradient(135deg,#0ea5e9,#22d3ee); }
    .ic-disk { background: linear-gradient(135deg,#f59e0b,#fbbf24); }
    .ic-net  { background: linear-gradient(135deg,#10b981,#4ade80); }

    .card-head h2 {
      font-size: 14px;
      font-weight: 600;
      letter-spacing: .3px;
    }
    .card-head .badge {
      margin-left: auto;
      font-size: 11px;
      color: var(--muted);
      background: rgba(148,163,184,.1);
      padding: 3px 8px;
      border-radius: 6px;
    }

    .row {
      display: flex;
      justify-content: space-between;
      align-items: center;
      font-size: 13px;
      margin: 7px 0;
    }
    .row .lbl {
      color: var(--muted);
      display: inline-flex;
      align-items: center;
      gap: 6px;
    }
    .row .val { font-weight: 600; color: #f1f5f9; font-variant-numeric: tabular-nums; }

    .bar {
      height: 8px;
      border-radius: 6px;
      background: rgba(148,163,184,.12);
      overflow: hidden;
      margin-top: 12px;
    }
    .fill {
      height: 100%;
      width: 0%;
      border-radius: 6px;
      background: linear-gradient(90deg,#22c55e,#4ade80);
      transition: width .45s ease, background .3s;
    }
    .fill.warn { background: linear-gradient(90deg,#f59e0b,#fbbf24); }
    .fill.crit { background: linear-gradient(90deg,#ef4444,#f87171); }

    /* Ringkasan persen besar */
    .big-pct {
      font-size: 26px;
      font-weight: 700;
      font-variant-numeric: tabular-nums;
    }
    .pct-green { color: var(--green); }
    .pct-amber { color: var(--amber); }
    .pct-red   { color: var(--red); }

    /* Network grid */
    .net-grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 10px;
    }
    .net-box {
      background: rgba(15,23,42,.7);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 14px 10px;
      text-align: center;
    }
    .net-box i { font-size: 16px; margin-bottom: 6px; display: block; }
    .net-box .num {
      font-size: 20px;
      font-weight: 700;
      font-variant-numeric: tabular-nums;
      line-height: 1.2;
    }
    .net-box .lbl {
      font-size: 11px;
      color: var(--muted);
      margin-top: 4px;
      text-transform: uppercase;
      letter-spacing: .5px;
    }
    .dl i, .dl .num { color: var(--green); }
    .ul i, .ul .num { color: var(--blue); }

    footer {
      text-align: center;
      font-size: 12px;
      color: var(--muted);
      margin-top: 22px;
      padding-top: 16px;
      border-top: 1px solid var(--border);
    }
    footer i { color: var(--accent); }

    /* loading state */
    .loading { opacity: .5; transition: opacity .3s; }
  </style>
</head>
<body>
  <div class="wrap">
    <header>
      <div class="logo"><i class="fa-solid fa-server"></i></div>
      <h1>Home Server Dashboard</h1>
      <div class="sub"><span class="dot"></span>Live monitoring · Android</div>
    </header>

    <div class="grid" id="grid">
      <!-- CPU -->
      <div class="card full">
        <div class="card-head">
          <i class="ic-cpu fa-solid fa-microchip"></i>
          <h2>CPU</h2>
          <span class="badge" id="cpu-cores">- core</span>
        </div>
        <div class="row">
          <span class="lbl"><i class="fa-solid fa-gauge-high"></i> Pemakaian</span>
          <span class="big-pct" id="cpu-pct">-</span>
        </div>
        <div class="row">
          <span class="lbl"><i class="fa-solid fa-bolt"></i> Frekuensi</span>
          <span class="val" id="cpu-freq">-</span>
        </div>
        <div class="bar"><div class="fill" id="cpu-bar"></div></div>
      </div>

      <!-- RAM -->
      <div class="card">
        <div class="card-head">
          <i class="ic-ram fa-solid fa-memory"></i>
          <h2>RAM</h2>
        </div>
        <div class="row">
          <span class="lbl"><i class="fa-solid fa-chart-pie"></i> Pemakaian</span>
          <span class="val" id="ram-pct">-</span>
        </div>
        <div class="row">
          <span class="lbl"><i class="fa-solid fa-database"></i> Terpakai</span>
          <span class="val" id="ram-used">-</span>
        </div>
        <div class="row">
          <span class="lbl"><i class="fa-solid fa-check"></i> Tersedia</span>
          <span class="val" id="ram-avail">-</span>
        </div>
        <div class="row">
          <span class="lbl"><i class="fa-solid fa-server"></i> Total</span>
          <span class="val" id="ram-total">-</span>
        </div>
        <div class="bar"><div class="fill" id="ram-bar"></div></div>
      </div>

      <!-- DISK -->
      <div class="card">
        <div class="card-head">
          <i class="ic-disk fa-solid fa-hard-drive"></i>
          <h2>Disk</h2>
        </div>
        <div class="row">
          <span class="lbl"><i class="fa-solid fa-chart-pie"></i> Pemakaian</span>
          <span class="val" id="disk-pct">-</span>
        </div>
        <div class="row">
          <span class="lbl"><i class="fa-solid fa-database"></i> Terpakai</span>
          <span class="val" id="disk-used">-</span>
        </div>
        <div class="row">
          <span class="lbl"><i class="fa-solid fa-check"></i> Kosong</span>
          <span class="val" id="disk-free">-</span>
        </div>
        <div class="row">
          <span class="lbl"><i class="fa-solid fa-server"></i> Total</span>
          <span class="val" id="disk-total">-</span>
        </div>
        <div class="bar"><div class="fill" id="disk-bar"></div></div>
      </div>

      <!-- NETWORK -->
      <div class="card full">
        <div class="card-head">
          <i class="ic-net fa-solid fa-wifi"></i>
          <h2>Jaringan</h2>
          <span class="badge" id="iface">-</span>
        </div>
        <div class="net-grid">
          <div class="net-box dl">
            <i class="fa-solid fa-arrow-down"></i>
            <div class="num" id="rx">-</div>
            <div class="lbl">Download · Mbps</div>
          </div>
          <div class="net-box ul">
            <i class="fa-solid fa-arrow-up"></i>
            <div class="num" id="tx">-</div>
            <div class="lbl">Upload · Mbps</div>
          </div>
        </div>
      </div>
    </div>

    <footer>
      <i class="fa-solid fa-rotate"></i>
      Auto-refresh setiap 2 detik &nbsp;·&nbsp;
      <i class="fa-solid fa-heart"></i> Termux
    </footer>
  </div>

<script>
function setBar(id, pct) {
  const el = document.getElementById(id);
  el.style.width = Math.min(pct, 100) + '%';
  el.className = 'fill' + (pct > 85 ? ' crit' : pct > 65 ? ' warn' : '');
}

function colorPct(id, pct) {
  const el = document.getElementById(id);
  el.className = 'big-pct ' + (pct > 85 ? 'pct-red' : pct > 65 ? 'pct-amber' : 'pct-green');
}

async function refresh() {
  try {
    const r = await fetch('/info.json?t=' + Date.now());
    const d = await r.json();

    // CPU
    document.getElementById('cpu-pct').textContent  = d.cpu.pct + '%';
    document.getElementById('cpu-cores').textContent = d.cpu.cores + ' core';
    document.getElementById('cpu-freq').textContent  = d.cpu.freq + ' MHz';
    colorPct('cpu-pct', d.cpu.pct);
    setBar('cpu-bar', d.cpu.pct);

    // RAM
    document.getElementById('ram-total').textContent = d.ram.total + ' MB';
    document.getElementById('ram-used').textContent  = d.ram.used  + ' MB';
    document.getElementById('ram-avail').textContent = d.ram.avail + ' MB';
    document.getElementById('ram-pct').textContent   = d.ram.pct   + ' %';
    setBar('ram-bar', d.ram.pct);

    // Disk
    document.getElementById('disk-total').textContent = d.disk.total + ' GB';
    document.getElementById('disk-used').textContent  = d.disk.used  + ' GB';
    document.getElementById('disk-free').textContent  = d.disk.free  + ' GB';
    document.getElementById('disk-pct').textContent   = d.disk.pct   + ' %';
    setBar('disk-bar', d.disk.pct);

    // Net
    document.getElementById('iface').textContent = d.net.iface;
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
import http.server, socketserver, subprocess, os

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
                    timeout=6
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
        pass

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
