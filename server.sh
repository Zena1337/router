#!/data/data/com.termux/files/usr/bin/bash

set -e

PORT=8080
SERVER_DIR="$HOME/home-server"

echo "================================"
echo "     ANDROID HOME SERVER"
echo "================================"

pkg update -y
pkg install -y python openssh iproute2 procps

mkdir -p "$SERVER_DIR"

# ======================
# info.sh
# ======================
cat > "$SERVER_DIR/info.sh" <<'SH'
#!/data/data/com.termux/files/usr/bin/bash
CPU_PCT="0.0"

# CPU via top (paling reliable di Termux non-root)
TOP_CPU=$(top -bn1 2>/dev/null | awk -F'[ ,]+' '/[Cc]pu/ && /idle/ {
  for (i=1;i<=NF;i++) if ($i ~ /idle/) { print $(i-1); exit }
}')
if [ -n "$TOP_CPU" ]; then
  CPU_PCT=$(awk "BEGIN {p=100-$TOP_CPU; if(p<0)p=0; if(p>100)p=100; printf \"%.1f\", p}")
fi

# Fallback: loadavg
if [ "$CPU_PCT" = "0.0" ]; then
  LA=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
  CORES=$(nproc 2>/dev/null || echo 1)
  if [ -n "$LA" ] && [ "$CORES" -gt 0 ]; then
    CPU_PCT=$(awk "BEGIN {p=($LA/$CORES)*100; if(p>100)p=100; printf \"%.1f\", p}")
  fi
fi

CPU_MODEL=$(getprop ro.soc.model 2>/dev/null)
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(getprop ro.board.platform 2>/dev/null)
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(getprop ro.product.board 2>/dev/null)
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(awk -F: '/^[Hh]ardware/ {gsub(/^ +/,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null)
[ -z "$CPU_MODEL" ] && CPU_MODEL="Unknown"

CPU_ARCH=$(uname -m)
CPU_CORES=$(nproc 2>/dev/null || echo 1)

CPU_FREQ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo 0)
CPU_FREQ_MAX=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null || echo 0)
[ "$CPU_FREQ" -gt 0 ] 2>/dev/null && CPU_FREQ_MHZ=$((CPU_FREQ/1000)) || CPU_FREQ_MHZ=0
[ "$CPU_FREQ_MAX" -gt 0 ] 2>/dev/null && CPU_FREQ_MAX_MHZ=$((CPU_FREQ_MAX/1000)) || CPU_FREQ_MAX_MHZ=0

RAM_TOTAL=$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
RAM_AVAIL=$(awk '/MemAvailable/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null)
[ -z "$RAM_AVAIL" ] || [ "$RAM_AVAIL" = "0" ] && RAM_AVAIL=$(awk '/MemFree/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
if [ "$RAM_TOTAL" -gt 0 ]; then
  RAM_USED=$((RAM_TOTAL - RAM_AVAIL))
  RAM_PCT=$(awk "BEGIN {printf \"%.1f\", ($RAM_USED/$RAM_TOTAL)*100}")
else
  RAM_USED=0; RAM_PCT="0.0"
fi

DISK_INFO=$(df -k "$HOME" | awk 'NR==2 {print $2, $3, $4}')
DISK_TOTAL=$(echo "$DISK_INFO" | awk '{printf "%.1f", $1/1024/1024}')
DISK_USED=$(echo "$DISK_INFO"  | awk '{printf "%.1f", $2/1024/1024}')
DISK_FREE=$(echo "$DISK_INFO"  | awk '{printf "%.1f", $3/1024/1024}')
DISK_PCT=$(awk "BEGIN {if($DISK_TOTAL>0) printf \"%.1f\", ($DISK_USED/$DISK_TOTAL)*100; else print \"0.0\"}")

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
  "cpu": {"pct": $CPU_PCT, "cores": $CPU_CORES, "freq": $CPU_FREQ_MHZ, "freq_max": $CPU_FREQ_MAX_MHZ, "model": "$CPU_MODEL", "arch": "$CPU_ARCH"},
  "ram": {"total": $RAM_TOTAL, "used": $RAM_USED, "avail": $RAM_AVAIL, "pct": $RAM_PCT},
  "disk": {"total": $DISK_TOTAL, "used": $DISK_USED, "free": $DISK_FREE, "pct": $DISK_PCT},
  "net": {"iface": "$IFACE", "rx": $RX_MBPS, "tx": $TX_MBPS}
}
JSON
SH
chmod +x "$SERVER_DIR/info.sh"

# ======================
# index.html
# ======================
cat > "$SERVER_DIR/index.html" <<'HTML'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Home Server</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
<style>
  :root {
    --bg: #000;
    --panel: #0a0a0a;
    --card: #111;
    --card-2: #0d0d0d;
    --border: #1f1f1f;
    --text: #f5f5f5;
    --muted: #888;
    --green: #22c55e;
    --amber: #f59e0b;
    --red: #ef4444;
    --blue: #3b82f6;
    --purple: #a855f7;
    --accent: #22d3ee;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; -webkit-tap-highlight-color: transparent; }
  html, body { background: var(--bg); color: var(--text); }
  body {
    font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
    min-height: 100vh;
    padding: 16px;
    overflow-x: hidden;
  }

  /* ===== Top bar ===== */
  .topbar {
    display: flex; align-items: center; justify-content: space-between;
    padding: 12px 4px 20px;
    position: sticky; top: 0;
    background: linear-gradient(180deg, #000 70%, transparent);
    z-index: 100;
  }
  .brand {
    display: flex; align-items: center; gap: 10px;
    font-weight: 700; font-size: 15px;
  }
  .brand .logo-mini {
    width: 32px; height: 32px;
    display: inline-flex; align-items: center; justify-content: center;
    border-radius: 9px;
    background: linear-gradient(135deg, #06b6d4, #3b82f6);
    font-size: 14px; color: #fff;
  }
  .menu-btn {
    width: 40px; height: 40px;
    display: inline-flex; align-items: center; justify-content: center;
    background: #1a1a1a; border: 1px solid var(--border);
    border-radius: 10px; color: var(--text); font-size: 16px;
    cursor: pointer; transition: background .15s;
  }
  .menu-btn:hover { background: #222; }
  .menu-btn:active { transform: scale(.96); }

  /* ===== Drawer ===== */
  .drawer-backdrop {
    position: fixed; inset: 0;
    background: rgba(0,0,0,.7);
    opacity: 0; pointer-events: none;
    transition: opacity .25s;
    z-index: 900;
    backdrop-filter: blur(2px);
  }
  .drawer-backdrop.open { opacity: 1; pointer-events: auto; }

  .drawer {
    position: fixed; top: 0; right: 0;
    width: 280px; max-width: 85vw; height: 100vh;
    background: #0a0a0a;
    border-left: 1px solid var(--border);
    transform: translateX(100%);
    transition: transform .28s cubic-bezier(.4,0,.2,1);
    z-index: 1000;
    display: flex; flex-direction: column;
    padding: 20px 16px;
  }
  .drawer.open { transform: translateX(0); }

  .drawer-head {
    display: flex; align-items: center; justify-content: space-between;
    padding-bottom: 16px; margin-bottom: 12px;
    border-bottom: 1px solid var(--border);
  }
  .drawer-head .title { font-weight: 700; font-size: 15px; }
  .close-btn {
    width: 34px; height: 34px;
    background: transparent; border: none;
    color: var(--muted); font-size: 18px; cursor: pointer;
    border-radius: 8px; transition: background .15s;
  }
  .close-btn:hover { background: #1a1a1a; color: #fff; }

  .drawer-nav { display: flex; flex-direction: column; gap: 6px; }
  .nav-item {
    display: flex; align-items: center; gap: 14px;
    padding: 14px 14px;
    background: #111;
    border: 1px solid var(--border);
    border-radius: 12px;
    color: var(--text); text-decoration: none;
    font-size: 14px; font-weight: 500;
    cursor: pointer; transition: background .15s, border-color .15s;
  }
  .nav-item:hover { background: #1a1a1a; border-color: #2a2a2a; }
  .nav-item.active { background: #1a2e1f; border-color: #22c55e33; }
  .nav-item i:first-child {
    width: 20px; text-align: center; color: #ddd;
  }
  .nav-item.active i:first-child { color: var(--green); }
  .nav-item .arrow {
    margin-left: auto; color: #555; font-size: 12px;
  }

  /* ===== Layout ===== */
  .wrap { max-width: 760px; margin: 0 auto; }
  .grid { display: grid; grid-template-columns: 1fr; gap: 14px; }
  @media (min-width: 620px) {
    .grid { grid-template-columns: 1fr 1fr; }
    .card.full { grid-column: 1 / -1; }
  }
  .page { display: none; }
  .page.active { display: block; animation: fade .25s ease; }
  @keyframes fade { from { opacity: 0; transform: translateY(6px); } to { opacity: 1; transform: none; } }

  /* ===== Card ===== */
  .card {
    background: linear-gradient(160deg, var(--card) 0%, var(--card-2) 100%);
    border: 1px solid var(--border);
    border-radius: 16px;
    padding: 18px;
    position: relative; overflow: hidden;
  }
  .card::before {
    content: ''; position: absolute; top: 0; left: 0; right: 0; height: 2px;
    background: linear-gradient(90deg, transparent, var(--accent), transparent);
    opacity: .5;
  }
  .card-head { display: flex; align-items: center; gap: 10px; margin-bottom: 14px; }
  .card-head i.ic {
    width: 34px; height: 34px;
    display: inline-flex; align-items: center; justify-content: center;
    border-radius: 10px; font-size: 15px; color: #fff; flex-shrink: 0;
  }
  .ic-cpu  { background: linear-gradient(135deg,#8b5cf6,#a78bfa); }
  .ic-ram  { background: linear-gradient(135deg,#0ea5e9,#22d3ee); }
  .ic-disk { background: linear-gradient(135deg,#f59e0b,#fbbf24); }
  .ic-net  { background: linear-gradient(135deg,#10b981,#4ade80); }
  .ic-term { background: linear-gradient(135deg,#374151,#111827); }
  .card-head h2 { font-size: 14px; font-weight: 600; letter-spacing: .3px; }
  .card-head .badge {
    margin-left: auto; font-size: 11px; color: var(--muted);
    background: #1a1a1a; padding: 3px 8px; border-radius: 6px; white-space: nowrap;
  }

  .chip {
    display: flex; align-items: center; gap: 10px;
    padding: 10px 12px; background: #0a0a0a;
    border: 1px solid var(--border); border-radius: 10px;
    margin-bottom: 12px; font-size: 13px;
  }
  .chip i { color: var(--purple); }
  .chip .model { font-weight: 600; color: #f1f5f9;
    overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .chip .arch {
    margin-left: auto; font-size: 11px; color: var(--muted);
    background: #1a1a1a; padding: 2px 8px; border-radius: 6px;
  }

  .row { display: flex; justify-content: space-between; align-items: center;
    font-size: 13px; margin: 7px 0; }
  .row .lbl { color: var(--muted); display: inline-flex; align-items: center; gap: 6px; }
  .row .val { font-weight: 600; color: #f1f5f9; font-variant-numeric: tabular-nums; }

  .bar { height: 8px; border-radius: 6px; background: #1a1a1a; overflow: hidden; margin-top: 12px; }
  .fill {
    height: 100%; width: 0%; border-radius: 6px;
    background: linear-gradient(90deg,#22c55e,#4ade80);
    transition: width .45s ease, background .3s;
  }
  .fill.warn { background: linear-gradient(90deg,#f59e0b,#fbbf24); }
  .fill.crit { background: linear-gradient(90deg,#ef4444,#f87171); }

  .big-pct { font-size: 26px; font-weight: 700; font-variant-numeric: tabular-nums; }
  .pct-green { color: var(--green); }
  .pct-amber { color: var(--amber); }
  .pct-red   { color: var(--red); }

  .net-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
  .net-box {
    background: #0a0a0a; border: 1px solid var(--border);
    border-radius: 12px; padding: 14px 10px; text-align: center;
  }
  .net-box i { font-size: 16px; margin-bottom: 6px; display: block; }
  .net-box .num {
    font-size: 20px; font-weight: 700; font-variant-numeric: tabular-nums; line-height: 1.2;
  }
  .net-box .lbl {
    font-size: 11px; color: var(--muted); margin-top: 4px;
    text-transform: uppercase; letter-spacing: .5px;
  }
  .dl i, .dl .num { color: var(--green); }
  .ul i, .ul .num { color: var(--blue); }

  /* ===== Terminal ===== */
  .term {
    background: #000;
    border: 1px solid #1f1f1f;
    border-radius: 12px;
    padding: 14px;
    font-family: 'JetBrains Mono', 'Courier New', monospace;
    font-size: 12.5px;
    line-height: 1.55;
    height: 280px;
    overflow-y: auto;
    color: #d1d5db;
  }
  .term::-webkit-scrollbar { width: 6px; }
  .term::-webkit-scrollbar-track { background: #0a0a0a; }
  .term::-webkit-scrollbar-thumb { background: #222; border-radius: 3px; }
  .term .line { white-space: pre-wrap; word-break: break-word; }
  .term .prompt { color: var(--green); }
  .term .err { color: #f87171; }
  .term .info { color: var(--muted); }

  .term-input {
    display: flex; gap: 8px; margin-top: 10px;
    background: #000; border: 1px solid var(--border);
    border-radius: 10px; padding: 8px 10px; align-items: center;
  }
  .term-input .prompt-char { color: var(--green); font-family: monospace; font-weight: 700; }
  .term-input input {
    flex: 1; background: transparent; border: none; outline: none;
    color: #fff; font-family: 'JetBrains Mono', 'Courier New', monospace;
    font-size: 13px; padding: 4px 0;
  }
  .term-input button {
    background: #1a1a1a; border: 1px solid #2a2a2a; color: #ddd;
    border-radius: 6px; width: 32px; height: 32px;
    cursor: pointer; transition: background .15s;
    display: inline-flex; align-items: center; justify-content: center;
  }
  .term-input button:hover { background: #22c55e33; border-color: #22c55e55; color: #4ade80; }

  /* ===== File list ===== */
  .file-item {
    display: flex; align-items: center; gap: 12px;
    padding: 12px 14px; background: #0a0a0a;
    border: 1px solid var(--border); border-radius: 10px;
    margin-bottom: 8px; font-size: 13px;
    cursor: pointer; transition: background .15s;
  }
  .file-item:hover { background: #151515; }
  .file-item i { color: var(--amber); font-size: 16px; width: 20px; text-align: center; }
  .file-item .name { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .file-item .size { color: var(--muted); font-size: 12px; font-variant-numeric: tabular-nums; }

  footer {
    text-align: center; font-size: 12px; color: var(--muted);
    margin-top: 22px; padding-top: 16px; border-top: 1px solid var(--border);
  }
  footer i { color: var(--accent); }

  .empty { text-align: center; padding: 30px 10px; color: var(--muted); font-size: 13px; }
</style>
</head>
<body>

  <!-- Topbar -->
  <div class="topbar">
    <div class="brand">
      <div class="logo-mini"><i class="fa-solid fa-server"></i></div>
      Home Server
    </div>
    <button class="menu-btn" onclick="openDrawer()" aria-label="Menu">
      <i class="fa-solid fa-bars"></i>
    </button>
  </div>

  <!-- Backdrop -->
  <div class="drawer-backdrop" id="backdrop" onclick="closeDrawer()"></div>

  <!-- Drawer -->
  <aside class="drawer" id="drawer">
    <div class="drawer-head">
      <span class="title">Menu</span>
      <button class="close-btn" onclick="closeDrawer()"><i class="fa-solid fa-xmark"></i></button>
    </div>
    <nav class="drawer-nav">
      <a class="nav-item active" data-page="home" onclick="navigate('home')">
        <i class="fa-solid fa-house"></i> Home
        <i class="fa-solid fa-chevron-right arrow"></i>
      </a>
      <a class="nav-item" data-page="files" onclick="navigate('files')">
        <i class="fa-solid fa-folder"></i> File
        <i class="fa-solid fa-chevron-right arrow"></i>
      </a>
    </nav>
  </aside>

  <div class="wrap">

    <!-- ============ PAGE: HOME ============ -->
    <section class="page active" id="page-home">
      <div class="grid">
        <!-- CPU -->
        <div class="card full">
          <div class="card-head">
            <i class="ic ic-cpu fa-solid fa-microchip"></i>
            <h2>CPU</h2>
            <span class="badge" id="cpu-cores">- core</span>
          </div>
          <div class="chip">
            <i class="fa-solid fa-microchip"></i>
            <span class="model" id="cpu-model">Memuat…</span>
            <span class="arch" id="cpu-arch">-</span>
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
            <i class="ic ic-ram fa-solid fa-memory"></i>
            <h2>RAM</h2>
          </div>
          <div class="row"><span class="lbl"><i class="fa-solid fa-chart-pie"></i> Pemakaian</span><span class="val" id="ram-pct">-</span></div>
          <div class="row"><span class="lbl"><i class="fa-solid fa-database"></i> Terpakai</span><span class="val" id="ram-used">-</span></div>
          <div class="row"><span class="lbl"><i class="fa-solid fa-check"></i> Tersedia</span><span class="val" id="ram-avail">-</span></div>
          <div class="row"><span class="lbl"><i class="fa-solid fa-server"></i> Total</span><span class="val" id="ram-total">-</span></div>
          <div class="bar"><div class="fill" id="ram-bar"></div></div>
        </div>

        <!-- Disk -->
        <div class="card">
          <div class="card-head">
            <i class="ic ic-disk fa-solid fa-hard-drive"></i>
            <h2>Disk</h2>
          </div>
          <div class="row"><span class="lbl"><i class="fa-solid fa-chart-pie"></i> Pemakaian</span><span class="val" id="disk-pct">-</span></div>
          <div class="row"><span class="lbl"><i class="fa-solid fa-database"></i> Terpakai</span><span class="val" id="disk-used">-</span></div>
          <div class="row"><span class="lbl"><i class="fa-solid fa-check"></i> Kosong</span><span class="val" id="disk-free">-</span></div>
          <div class="row"><span class="lbl"><i class="fa-solid fa-server"></i> Total</span><span class="val" id="disk-total">-</span></div>
          <div class="bar"><div class="fill" id="disk-bar"></div></div>
        </div>

        <!-- Network -->
        <div class="card full">
          <div class="card-head">
            <i class="ic ic-net fa-solid fa-wifi"></i>
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

        <!-- Terminal -->
        <div class="card full">
          <div class="card-head">
            <i class="ic ic-term fa-solid fa-terminal"></i>
            <h2>Terminal</h2>
            <span class="badge">whitelist</span>
          </div>
          <div class="term" id="term">
            <div class="line info">Termux Web Terminal siap. Ketik perintah, contoh: <b>ls</b>, <b>df -h</b>, <b>uname -a</b></div>
          </div>
          <form class="term-input" onsubmit="runCmd(event)">
            <span class="prompt-char">$</span>
            <input type="text" id="cmd" placeholder="ketik perintah..." autocomplete="off" autocapitalize="off" spellcheck="false">
            <button type="submit"><i class="fa-solid fa-paper-plane"></i></button>
          </form>
        </div>
      </div>
    </section>

    <!-- ============ PAGE: FILES ============ -->
    <section class="page" id="page-files">
      <div class="card full">
        <div class="card-head">
          <i class="ic ic-disk fa-solid fa-folder-open"></i>
          <h2>Daftar File</h2>
          <span class="badge" id="file-path">~/home-server</span>
        </div>
        <div id="file-list">
          <div class="empty">Memuat…</div>
        </div>
      </div>
    </section>

    <footer>
      <i class="fa-solid fa-rotate"></i> Auto-refresh 2 detik &nbsp;·&nbsp;
      <i class="fa-solid fa-heart"></i> Termux
    </footer>
  </div>

<script>
// ============ Drawer ============
function openDrawer() {
  document.getElementById('drawer').classList.add('open');
  document.getElementById('backdrop').classList.add('open');
}
function closeDrawer() {
  document.getElementById('drawer').classList.remove('open');
  document.getElementById('backdrop').classList.remove('open');
}
function navigate(page) {
  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
  document.getElementById('page-' + page).classList.add('active');
  document.querySelectorAll('.nav-item').forEach(n => {
    n.classList.toggle('active', n.dataset.page === page);
  });
  closeDrawer();
  if (page === 'files') loadFiles();
}

// ============ Stats ============
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

    document.getElementById('cpu-pct').textContent = d.cpu.pct + '%';
    colorPct('cpu-pct', d.cpu.pct);
    document.getElementById('cpu-cores').textContent = d.cpu.cores + ' core';
    document.getElementById('cpu-model').textContent = d.cpu.model;
    document.getElementById('cpu-arch').textContent = d.cpu.arch;
    let freqTxt = d.cpu.freq + ' MHz';
    if (d.cpu.freq_max > 0) freqTxt += ' / ' + d.cpu.freq_max + ' MHz';
    document.getElementById('cpu-freq').textContent = freqTxt;
    setBar('cpu-bar', d.cpu.pct);

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

    document.getElementById('iface').textContent = d.net.iface;
    document.getElementById('rx').textContent = d.net.rx.toFixed(2);
    document.getElementById('tx').textContent = d.net.tx.toFixed(2);
  } catch(e) { console.error(e); }
}
refresh();
setInterval(refresh, 2000);

// ============ Terminal ============
const term = document.getElementById('term');
function termWrite(html, cls) {
  const div = document.createElement('div');
  div.className = 'line ' + (cls || '');
  div.innerHTML = html;
  term.appendChild(div);
  term.scrollTop = term.scrollHeight;
}

async function runCmd(e) {
  e.preventDefault();
  const input = document.getElementById('cmd');
  const cmd = input.value.trim();
  if (!cmd) return;

  termWrite('<span class="prompt">$</span> ' + escapeHtml(cmd));
  input.value = '';

  try {
    const r = await fetch('/run?cmd=' + encodeURIComponent(cmd));
    const text = await r.text();
    if (r.ok) {
      termWrite(text ? escapeHtml(text) : '<i class="info">(tidak ada output)</i>');
    } else {
      termWrite(escapeHtml(text), 'err');
    }
  } catch(e) {
    termWrite('Error: ' + escapeHtml(e.message), 'err');
  }
}
function escapeHtml(s) {
  return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

// ============ Files ============
async function loadFiles() {
  const box = document.getElementById('file-list');
  box.innerHTML = '<div class="empty">Memuat…</div>';
  try {
    const r = await fetch('/ls');
    const list = await r.json();
    if (!list.length) {
      box.innerHTML = '<div class="empty">Folder kosong</div>';
      return;
    }
    box.innerHTML = list.map(f => `
      <div class="file-item">
        <i class="fa-solid ${f.isDir ? 'fa-folder' : 'fa-file'}"></i>
        <span class="name">${escapeHtml(f.name)}</span>
        <span class="size">${f.size}</span>
      </div>
    `).join('');
  } catch(e) {
    box.innerHTML = '<div class="empty">Gagal memuat</div>';
  }
}
</script>
</body>
</html>
HTML

# ======================
# server.py
# ======================
cat > "$SERVER_DIR/server.py" <<'PY'
#!/usr/bin/env python3
import http.server
import socketserver
import subprocess
import os
import json
import urllib.parse

PORT = 8080
DIRECTORY = os.path.dirname(os.path.abspath(__file__))

# Whitelist perintah yang boleh dijalankan (keamanan)
ALLOWED_CMDS = {
    "ls", "pwd", "whoami", "uname", "date", "uptime", "df", "du",
    "free", "top", "ps", "ip", "ifconfig", "netstat", "ss",
    "cat", "head", "tail", "wc", "grep", "echo", "which", "nproc",
    "getprop", "termux-info", "id", "hostname", "env"
}

def is_allowed(cmd):
    """Hanya izinkan perintah dari whitelist (kata pertama)."""
    first = cmd.strip().split()[0] if cmd.strip() else ""
    return first in ALLOWED_CMDS

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def _json(self, code, obj):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(json.dumps(obj).encode())

    def _text(self, code, text):
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(text.encode())

    def do_GET(self):
        path = urllib.parse.urlparse(self.path)
        route = path.path
        qs = urllib.parse.parse_qs(path.query)

        # /info.json
        if route == "/info.json":
            try:
                out = subprocess.check_output(
                    [os.path.join(DIRECTORY, "info.sh")],
                    timeout=10, stderr=subprocess.DEVNULL
                )
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(out)
            except Exception:
                self._json(200, {
                    "cpu": {"pct":0,"cores":0,"freq":0,"freq_max":0,"model":"Error","arch":"-"},
                    "ram": {"total":0,"used":0,"avail":0,"pct":0},
                    "disk":{"total":0,"used":0,"free":0,"pct":0},
                    "net": {"iface":"-","rx":0,"tx":0}
                })
            return

        # /run?cmd=...
        if route == "/run":
            cmd = (qs.get("cmd") or [""])[0].strip()
            if not cmd:
                self._text(400, "Perintah kosong")
                return
            if not is_allowed(cmd):
                self._text(403, f"Perintah '{cmd.split()[0]}' tidak diizinkan (whitelist)")
                return
            try:
                out = subprocess.check_output(
                    cmd, shell=True, timeout=10,
                    stderr=subprocess.STDOUT, cwd=os.path.expanduser("~")
                ).decode("utf-8", errors="replace")
                # Batasi output biar tidak overload
                if len(out) > 20000:
                    out = out[:20000] + "\n...(output dipotong)"
                self._text(200, out)
            except subprocess.CalledProcessError as e:
                self._text(500, (e.output or b"").decode("utf-8", errors="replace"))
            except subprocess.TimeoutExpired:
                self._text(504, "Timeout (>10 detik)")
            except Exception as e:
                self._text(500, str(e))
            return

        # /ls — daftar isi folder home
        if route == "/ls":
            try:
                base = os.path.expanduser("~")
                items = []
                for name in sorted(os.listdir(base)):
                    full = os.path.join(base, name)
                    try:
                        st = os.stat(full)
                        is_dir = os.path.isdir(full)
                        if is_dir:
                            size = "folder"
                        else:
                            b = st.st_size
                            if b < 1024: size = f"{b} B"
                            elif b < 1024*1024: size = f"{b/1024:.1f} KB"
                            else: size = f"{b/1024/1024:.1f} MB"
                        items.append({"name": name, "isDir": is_dir, "size": size})
                    except Exception:
                        items.append({"name": name, "isDir": False, "size": "?"})
                self._json(200, items)
            except Exception as e:
                self._json(500, {"error": str(e)})
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
# Info IP
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
