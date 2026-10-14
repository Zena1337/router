#!/data/data/com.termux/files/usr/bin/bash
# =========================================================
#   ANDROID HOME SERVER - All in One (DARK MINIMAL THEME)
#   Dashboard + File Manager + Web Terminal (multi-sesi)
# =========================================================

set -e

PORT=8080
TTYD_BASE_PORT=7681
TTYD_MAX_SESSIONS=6
SERVER_DIR="$HOME/home-server"
AUTH_TOKEN="${HOME_SERVER_TOKEN:-rahasia123}"

echo "================================"
echo "     ANDROID HOME SERVER"
echo "================================"

pkg update -y
pkg install -y python openssh iproute2 procps ttyd

mkdir -p "$SERVER_DIR"

# =========================================================
# info.sh
# =========================================================
cat > "$SERVER_DIR/info.sh" <<'SH'
#!/data/data/com.termux/files/usr/bin/bash
CPU_PCT="0.0"

if [ -r /proc/stat ]; then
  read_cpu_stat() {
    awk '/^cpu / {
      total = $2+$3+$4+$5+$6+$7+$8+$9
      idle  = $5 + $6
      print total, idle
      exit
    }' /proc/stat 2>/dev/null
  }
  CPU1=$(read_cpu_stat)
  sleep 0.5
  CPU2=$(read_cpu_stat)
  if [ -n "$CPU1" ] && [ -n "$CPU2" ]; then
    T1=$(echo "$CPU1" | awk '{print $1}')
    I1=$(echo "$CPU1" | awk '{print $2}')
    T2=$(echo "$CPU2" | awk '{print $1}')
    I2=$(echo "$CPU2" | awk '{print $2}')
    CPU_PCT=$(awk "BEGIN {
      dt=$T2-$T1; di=$I2-$I1
      if (dt>0) printf \"%.1f\", (1-di/dt)*100; else print \"0.0\"
    }")
  fi
fi

if [ "$CPU_PCT" = "0.0" ]; then
  TOP_OUT=$(top -bn1 2>/dev/null | head -20)
  IDLE=$(echo "$TOP_OUT" | awk '
    /[Cc]pu/ {
      for (i=1;i<=NF;i++) {
        if ($i ~ /^[0-9.]+%?$/ && $(i+1) ~ /id/) { gsub(/%/,"",$i); print $i; exit }
        if ($i ~ /id,?$/) { gsub(/[^0-9.]/,"",$(i-1)); print $(i-1); exit }
      }
    }')
  if [ -n "$IDLE" ]; then
    CPU_PCT=$(awk "BEGIN {p=100-$IDLE; if(p<0)p=0; printf \"%.1f\", p}")
  fi
fi

if [ "$CPU_PCT" = "0.0" ]; then
  LA=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
  CORES=$(nproc 2>/dev/null || echo 1)
  if [ -n "$LA" ] && [ "$CORES" -gt 0 ]; then
    CPU_PCT=$(awk "BEGIN {p=($LA/$CORES)*100; if(p>100)p=100; printf \"%.1f\", p}")
  fi
fi

CPU_MODEL=$(awk -F: '/^[Hh]ardware/ {gsub(/^ +/,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null)
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(awk -F: '/^[Mm]odel name/ {gsub(/^ +/,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null)
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(getprop ro.soc.model 2>/dev/null)
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(getprop ro.board.platform 2>/dev/null)
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(getprop ro.product.board 2>/dev/null)
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
  RAM_USED=0
  RAM_PCT="0.0"
fi

DISK_INFO=$(df -k "$HOME" | awk 'NR==2 {print $2, $3, $4}')
DISK_TOTAL=$(echo "$DISK_INFO" | awk '{printf "%.1f", $1/1024/1024}')
DISK_USED=$(echo "$DISK_INFO"  | awk '{printf "%.1f", $2/1024/1024}')
DISK_FREE=$(echo "$DISK_INFO"  | awk '{printf "%.1f", $3/1024/1024}')
if awk "BEGIN{exit !($DISK_TOTAL>0)}"; then
  DISK_PCT=$(awk "BEGIN {printf \"%.1f\", ($DISK_USED/$DISK_TOTAL)*100}")
else
  DISK_PCT="0.0"
fi

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
  "cpu": {
    "pct": $CPU_PCT,
    "cores": $CPU_CORES,
    "freq": $CPU_FREQ_MHZ,
    "freq_max": $CPU_FREQ_MAX_MHZ,
    "model": "$CPU_MODEL",
    "arch": "$CPU_ARCH"
  },
  "ram":  {"total": $RAM_TOTAL, "used": $RAM_USED, "avail": $RAM_AVAIL, "pct": $RAM_PCT},
  "disk": {"total": $DISK_TOTAL, "used": $DISK_USED, "free": $DISK_FREE, "pct": $DISK_PCT},
  "net":  {"iface": "$IFACE", "rx": $RX_MBPS, "tx": $TX_MBPS}
}
JSON
SH
chmod +x "$SERVER_DIR/info.sh"

# =========================================================
# index.html — Dashboard
# =========================================================
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
      --bg: #000000;
      --surface: #0a0a0a;
      --surface-2: #121212;
      --surface-3: #1a1a1a;
      --border: #1c1c1c;
      --border-2: #262626;
      --text: #f0f0f0;
      --text-dim: #a0a0a0;
      --text-mute: #6a6a6a;
      --accent: #e0e0e0;
      --warn: #d4a056;
      --crit: #c86161;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    html, body { background: #000; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #000;
      color: var(--text);
      min-height: 100vh;
      -webkit-font-smoothing: antialiased;
    }

    .topbar {
      position: sticky; top: 0; z-index: 50;
      display: flex; align-items: center; justify-content: space-between;
      padding: 18px 20px;
      background: #000;
      border-bottom: 1px solid var(--border);
    }
    .brand {
      display: flex; align-items: center; gap: 12px;
      font-size: 17px; font-weight: 700;
      letter-spacing: 1.5px;
      color: var(--text);
    }
    .brand i { font-size: 22px; color: var(--text); }
    .menu-btn {
      width: 44px; height: 44px;
      border-radius: 12px;
      background: #121212;
      border: 1px solid var(--border-2);
      color: var(--text);
      cursor: pointer;
      display: flex; align-items: center; justify-content: center;
      font-size: 16px;
      transition: background .15s, border-color .15s;
    }
    .menu-btn:hover { background: #1a1a1a; border-color: #333; }

    .menu-wrap { position: relative; }
    .dropdown {
      position: absolute; top: calc(100% + 10px); right: 0;
      min-width: 260px;
      background: #0d0d0d;
      border: 1px solid var(--border-2);
      border-radius: 16px;
      padding: 8px;
      box-shadow: 0 20px 60px rgba(0,0,0,.9);
      opacity: 0;
      transform: translateY(-6px) scale(.98);
      pointer-events: none;
      transition: opacity .16s, transform .16s;
      transform-origin: top right;
    }
    .dropdown.open {
      opacity: 1;
      transform: translateY(0) scale(1);
      pointer-events: auto;
    }
    .dropdown a {
      display: flex; align-items: center; gap: 14px;
      padding: 14px 16px;
      border-radius: 10px;
      color: var(--text);
      text-decoration: none;
      font-size: 15px;
      font-weight: 500;
      transition: background .15s;
    }
    .dropdown a:hover { background: #1a1a1a; }
    .dropdown a.active { background: #1f1f1f; }
    .dropdown a i.mi {
      font-size: 18px; color: var(--text-dim); width: 22px;
      text-align: center;
    }
    .dropdown a .label { flex: 1; }
    .dropdown a .arrow { color: var(--text-mute); font-size: 14px; }

    .wrap {
      max-width: 900px; margin: 0 auto;
      padding: 24px 20px 60px;
    }
    .page-title {
      display: flex; align-items: center; justify-content: space-between;
      margin-bottom: 22px;
    }
    .page-title h2 {
      font-size: 22px; font-weight: 700;
      letter-spacing: -.3px;
      color: var(--text);
    }
    .status-pill {
      display: inline-flex; align-items: center; gap: 8px;
      font-size: 12px;
      color: var(--text-dim);
      padding: 6px 12px;
      border-radius: 999px;
      background: #121212;
      border: 1px solid var(--border-2);
    }
    .dot {
      width: 6px; height: 6px; border-radius: 50%;
      background: #4ade80;
    }

    .grid { display: grid; grid-template-columns: 1fr; gap: 14px; }
    @media (min-width: 700px) {
      .grid { grid-template-columns: 1fr 1fr; }
      .card.full { grid-column: 1 / -1; }
    }

    .card {
      background: #0d0d0d;
      border: 1px solid var(--border);
      border-radius: 16px;
      padding: 20px;
    }
    .card-head {
      display: flex; align-items: center; gap: 12px; margin-bottom: 18px;
    }
    .card-head .ci {
      width: 38px; height: 38px;
      display: inline-flex; align-items: center; justify-content: center;
      border-radius: 10px;
      background: #1a1a1a;
      color: var(--text-dim);
      font-size: 15px;
      flex-shrink: 0;
    }
    .card-head h3 {
      font-size: 15px; font-weight: 600;
      color: var(--text);
    }
    .card-head .badge {
      margin-left: auto;
      font-size: 11px;
      color: var(--text-dim);
      background: #1a1a1a;
      padding: 4px 10px;
      border-radius: 6px;
      white-space: nowrap;
    }

    .chip {
      display: flex; align-items: center; gap: 12px;
      padding: 12px 14px;
      background: #080808;
      border: 1px solid var(--border);
      border-radius: 10px;
      margin-bottom: 16px;
      font-size: 13px;
    }
    .chip i { color: var(--text-mute); font-size: 13px; }
    .chip .model {
      font-weight: 500; color: var(--text);
      overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
    }
    .chip .arch {
      margin-left: auto;
      font-size: 11px;
      color: var(--text-mute);
      background: #1a1a1a;
      padding: 3px 8px;
      border-radius: 5px;
    }

    .row {
      display: flex; justify-content: space-between; align-items: center;
      font-size: 14px; margin: 11px 0;
    }
    .row .lbl {
      color: var(--text-dim);
      display: inline-flex; align-items: center; gap: 10px;
    }
    .row .lbl i { color: var(--text-mute); font-size: 12px; width: 14px; }
    .row .val {
      font-weight: 600; color: var(--text);
      font-variant-numeric: tabular-nums;
    }

    .bar {
      height: 5px; border-radius: 3px;
      background: #1a1a1a;
      overflow: hidden;
      margin-top: 16px;
    }
    .fill {
      height: 100%; width: 0%; border-radius: 3px;
      background: #d0d0d0;
      transition: width .45s ease, background .3s;
    }
    .fill.warn { background: var(--warn); }
    .fill.crit { background: var(--crit); }

    .big-pct {
      font-size: 28px; font-weight: 700;
      font-variant-numeric: tabular-nums;
      letter-spacing: -.8px;
      color: var(--text);
    }
    .pct-green { color: #d0d0d0; }
    .pct-amber { color: var(--warn); }
    .pct-red   { color: var(--crit); }

    .net-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
    .net-box {
      background: #080808;
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 20px 14px;
      text-align: center;
    }
    .net-box i {
      font-size: 16px; margin-bottom: 10px; display: block;
      color: var(--text-mute);
    }
    .net-box .num {
      font-size: 24px; font-weight: 700;
      font-variant-numeric: tabular-nums;
      line-height: 1.2;
      color: var(--text);
      letter-spacing: -.5px;
    }
    .net-box .lbl {
      font-size: 11px; color: var(--text-mute);
      margin-top: 8px;
    }

    footer {
      text-align: center; font-size: 12px; color: var(--text-mute);
      margin-top: 32px; padding-top: 20px;
      border-top: 1px solid var(--border);
    }
  </style>
</head>
<body>

  <div class="topbar">
    <div class="brand"><i class="fa-solid fa-cloud"></i> HOME SERVER</div>
    <div class="menu-wrap">
      <button class="menu-btn" id="menuBtn" aria-label="Menu"><i class="fa-solid fa-xmark" id="menuIcon"></i></button>
      <div class="dropdown" id="dropdown">
        <a href="/" class="active"><i class="mi fa-solid fa-house"></i><span class="label">Home</span><i class="arrow fa-solid fa-chevron-right"></i></a>
        <a href="/files.html"><i class="mi fa-solid fa-server"></i><span class="label">File</span><i class="arrow fa-solid fa-chevron-right"></i></a>
        <a href="/terminal.html"><i class="mi fa-solid fa-receipt"></i><span class="label">Terminal</span><i class="arrow fa-solid fa-chevron-right"></i></a>
      </div>
    </div>
  </div>

  <div class="wrap">
    <div class="page-title">
      <h2>Dashboard</h2>
      <div class="status-pill"><span class="dot"></span> Live</div>
    </div>

    <div class="grid">
      <div class="card full">
        <div class="card-head">
          <i class="ci fa-solid fa-microchip"></i>
          <h3>CPU</h3>
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

      <div class="card">
        <div class="card-head">
          <i class="ci fa-solid fa-memory"></i>
          <h3>RAM</h3>
        </div>
        <div class="row"><span class="lbl"><i class="fa-solid fa-chart-pie"></i> Pemakaian</span><span class="val" id="ram-pct">-</span></div>
        <div class="row"><span class="lbl"><i class="fa-solid fa-database"></i> Terpakai</span><span class="val" id="ram-used">-</span></div>
        <div class="row"><span class="lbl"><i class="fa-solid fa-check"></i> Tersedia</span><span class="val" id="ram-avail">-</span></div>
        <div class="row"><span class="lbl"><i class="fa-solid fa-server"></i> Total</span><span class="val" id="ram-total">-</span></div>
        <div class="bar"><div class="fill" id="ram-bar"></div></div>
      </div>

      <div class="card">
        <div class="card-head">
          <i class="ci fa-solid fa-hard-drive"></i>
          <h3>Disk</h3>
        </div>
        <div class="row"><span class="lbl"><i class="fa-solid fa-chart-pie"></i> Pemakaian</span><span class="val" id="disk-pct">-</span></div>
        <div class="row"><span class="lbl"><i class="fa-solid fa-database"></i> Terpakai</span><span class="val" id="disk-used">-</span></div>
        <div class="row"><span class="lbl"><i class="fa-solid fa-check"></i> Kosong</span><span class="val" id="disk-free">-</span></div>
        <div class="row"><span class="lbl"><i class="fa-solid fa-server"></i> Total</span><span class="val" id="disk-total">-</span></div>
        <div class="bar"><div class="fill" id="disk-bar"></div></div>
      </div>

      <div class="card full">
        <div class="card-head">
          <i class="ci fa-solid fa-wifi"></i>
          <h3>Jaringan</h3>
          <span class="badge" id="iface">-</span>
        </div>
        <div class="net-grid">
          <div class="net-box">
            <i class="fa-solid fa-arrow-down"></i>
            <div class="num" id="rx">-</div>
            <div class="lbl">DOWNLOAD · MBPS</div>
          </div>
          <div class="net-box">
            <i class="fa-solid fa-arrow-up"></i>
            <div class="num" id="tx">-</div>
            <div class="lbl">UPLOAD · MBPS</div>
          </div>
        </div>
      </div>
    </div>

    <footer>Auto-refresh 2 detik</footer>
  </div>

<script>
const menuBtn = document.getElementById('menuBtn');
const menuIcon = document.getElementById('menuIcon');
const dropdown = document.getElementById('dropdown');
menuBtn.addEventListener('click', e => {
  e.stopPropagation();
  const open = dropdown.classList.toggle('open');
  menuIcon.className = open ? 'fa-solid fa-xmark' : 'fa-solid fa-bars';
});
document.addEventListener('click', e => {
  if (!dropdown.contains(e.target) && !menuBtn.contains(e.target)) {
    dropdown.classList.remove('open');
    menuIcon.className = 'fa-solid fa-bars';
  }
});

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
</script>
</body>
</html>
HTML

# =========================================================
# files.html
# =========================================================
cat > "$SERVER_DIR/files.html" <<'HTML'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>File · Home Server</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
<style>
  :root{--bg:#000;--surface:#0d0d0d;--surface-2:#121212;--border:#1c1c1c;--border-2:#262626;--text:#f0f0f0;--text-dim:#a0a0a0;--text-mute:#6a6a6a;--warn:#d4a056;--crit:#c86161;}
  *{box-sizing:border-box;margin:0;padding:0}
  html,body{background:#000}
  body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#000;color:var(--text);min-height:100vh;-webkit-font-smoothing:antialiased}

  .topbar{position:sticky;top:0;z-index:50;display:flex;align-items:center;justify-content:space-between;padding:18px 20px;background:#000;border-bottom:1px solid var(--border)}
  .brand{display:flex;align-items:center;gap:12px;font-size:17px;font-weight:700;letter-spacing:1.5px;color:var(--text)}
  .brand i{font-size:22px;color:var(--text)}
  .menu-btn{width:44px;height:44px;border-radius:12px;background:#121212;border:1px solid var(--border-2);color:var(--text);cursor:pointer;display:flex;align-items:center;justify-content:center;font-size:16px;transition:background .15s,border-color .15s}
  .menu-btn:hover{background:#1a1a1a;border-color:#333}
  .menu-wrap{position:relative}
  .dropdown{position:absolute;top:calc(100% + 10px);right:0;min-width:260px;background:#0d0d0d;border:1px solid var(--border-2);border-radius:16px;padding:8px;box-shadow:0 20px 60px rgba(0,0,0,.9);opacity:0;transform:translateY(-6px) scale(.98);pointer-events:none;transition:opacity .16s,transform .16s;transform-origin:top right}
  .dropdown.open{opacity:1;transform:translateY(0) scale(1);pointer-events:auto}
  .dropdown a{display:flex;align-items:center;gap:14px;padding:14px 16px;border-radius:10px;color:var(--text);text-decoration:none;font-size:15px;font-weight:500;transition:background .15s}
  .dropdown a:hover{background:#1a1a1a}
  .dropdown a.active{background:#1f1f1f}
  .dropdown a i.mi{font-size:18px;color:var(--text-dim);width:22px;text-align:center}
  .dropdown a .label{flex:1}
  .dropdown a .arrow{color:var(--text-mute);font-size:14px}

  .wrap{max-width:820px;margin:0 auto;padding:24px 20px 60px}
  .page-title{display:flex;align-items:center;justify-content:space-between;margin-bottom:22px}
  .page-title h2{font-size:22px;font-weight:700;letter-spacing:-.3px;color:var(--text)}

  .toolbar{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:14px;align-items:center}
  .btn{padding:10px 16px;border-radius:10px;border:1px solid var(--border-2);background:var(--surface-2);color:var(--text);font-size:13px;cursor:pointer;display:inline-flex;align-items:center;gap:8px;transition:.15s;font-weight:500}
  .btn:hover{background:#1a1a1a;border-color:#333}
  .btn.danger{border-color:#3a2020;color:var(--crit)}
  .btn.danger:hover{background:rgba(200,97,97,.08)}

  .path{flex:1;min-width:200px;padding:10px 14px;background:#080808;border:1px solid var(--border-2);border-radius:10px;color:var(--text);font-size:13px;font-family:ui-monospace,monospace}
  .path:focus{outline:none;border-color:#333}

  .card{background:var(--surface);border:1px solid var(--border);border-radius:16px;padding:8px}
  .item{display:flex;align-items:center;gap:14px;padding:14px 14px;border-radius:10px;border-bottom:1px solid var(--border);transition:background .15s}
  .item:last-child{border-bottom:none}
  .item:hover{background:#141414}
  .item .ico{width:38px;height:38px;display:flex;align-items:center;justify-content:center;border-radius:10px;background:#1a1a1a;color:var(--text-dim);flex-shrink:0;font-size:14px}
  .item .ico.dir{color:var(--warn)}
  .item .meta{flex:1;min-width:0}
  .item .name{font-size:14px;font-weight:500;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:var(--text)}
  .item .info{font-size:11px;color:var(--text-mute);margin-top:3px}
  .item .actions{display:flex;gap:6px}
  .item .actions button{width:36px;height:36px;border-radius:8px;border:1px solid var(--border-2);background:#0d0d0d;color:var(--text-dim);cursor:pointer;font-size:13px;transition:.15s}
  .item .actions button:hover{background:#1a1a1a;color:var(--text)}
  .item .actions button.dl:hover{color:var(--text)}
  .empty{text-align:center;padding:50px 20px;color:var(--text-mute);font-size:13px}

  .drop{border:1px dashed var(--border-2);border-radius:14px;padding:30px;text-align:center;color:var(--text-mute);font-size:13px;margin-bottom:14px;transition:.15s;background:#080808}
  .drop.over{border-color:#444;background:#111;color:var(--text)}
  .drop i{color:var(--text-dim);font-size:26px;margin-bottom:6px;display:block}

  .token-bar{display:flex;gap:8px;margin-bottom:14px}
  .token-bar input{flex:1;padding:10px 14px;background:#080808;border:1px solid var(--border-2);border-radius:10px;color:var(--text);font-size:13px;font-family:ui-monospace,monospace}
  .token-bar input:focus{outline:none;border-color:#333}

  .toast{position:fixed;bottom:20px;right:20px;background:#1a1a1a;border:1px solid var(--border-2);color:var(--text);padding:14px 20px;border-radius:12px;font-size:13px;opacity:0;transform:translateY(20px);transition:.25s;pointer-events:none;z-index:99;box-shadow:0 10px 40px rgba(0,0,0,.8)}
  .toast.show{opacity:1;transform:translateY(0)}
  .toast.err{border-color:#3a2020;color:var(--crit)}
</style>
</head>
<body>

<div class="topbar">
  <div class="brand"><i class="fa-solid fa-cloud"></i> HOME SERVER</div>
  <div class="menu-wrap">
    <button class="menu-btn" id="menuBtn" aria-label="Menu"><i class="fa-solid fa-xmark" id="menuIcon"></i></button>
    <div class="dropdown" id="dropdown">
      <a href="/"><i class="mi fa-solid fa-house"></i><span class="label">Home</span><i class="arrow fa-solid fa-chevron-right"></i></a>
      <a href="/files.html" class="active"><i class="mi fa-solid fa-server"></i><span class="label">File</span><i class="arrow fa-solid fa-chevron-right"></i></a>
      <a href="/terminal.html"><i class="mi fa-solid fa-receipt"></i><span class="label">Terminal</span><i class="arrow fa-solid fa-chevron-right"></i></a>
    </div>
  </div>
</div>

<div class="wrap">
  <div class="page-title"><h2>File</h2></div>

  <div class="token-bar">
    <input type="password" id="token" placeholder="Token akses">
    <button class="btn" onclick="saveToken()"><i class="fa-solid fa-key"></i></button>
  </div>

  <div class="toolbar">
    <input class="path" id="path" value="" placeholder="Path relatif dari HOME">
    <button class="btn" onclick="go()"><i class="fa-solid fa-arrow-right"></i></button>
    <button class="btn" onclick="goUp()"><i class="fa-solid fa-arrow-up"></i></button>
    <button class="btn" onclick="refresh()"><i class="fa-solid fa-rotate"></i></button>
  </div>

  <div class="drop" id="drop">
    <i class="fa-solid fa-cloud-arrow-up"></i>
    <div>Tarik & lepas file, atau <label for="fileInput" style="color:#e0e0e0;cursor:pointer;text-decoration:underline">pilih file</label></div>
    <input type="file" id="fileInput" multiple style="display:none">
  </div>

  <div class="card" id="list"><div class="empty">Memuat…</div></div>
</div>

<div class="toast" id="toast"></div>

<script>
const $ = id => document.getElementById(id);
let currentPath = "";

const menuBtn = document.getElementById('menuBtn');
const menuIcon = document.getElementById('menuIcon');
const dropdown = document.getElementById('dropdown');
menuBtn.addEventListener('click', e => {
  e.stopPropagation();
  const open = dropdown.classList.toggle('open');
  menuIcon.className = open ? 'fa-solid fa-xmark' : 'fa-solid fa-bars';
});
document.addEventListener('click', e => {
  if (!dropdown.contains(e.target) && !menuBtn.contains(e.target)) {
    dropdown.classList.remove('open');
    menuIcon.className = 'fa-solid fa-bars';
  }
});

function saveToken(){ localStorage.setItem("hs_token", $("token").value); toast("Token disimpan"); refresh(); }
function getToken(){ return localStorage.getItem("hs_token") || ""; }
$("token").value = getToken();

function toast(msg, err=false){
  const t = $("toast");
  t.textContent = msg;
  t.className = "toast show" + (err ? " err" : "");
  setTimeout(()=>t.className = "toast", 2500);
}
function fmtSize(b){
  if(b < 1024) return b + " B";
  if(b < 1024*1024) return (b/1024).toFixed(1) + " KB";
  if(b < 1024*1024*1024) return (b/1024/1024).toFixed(1) + " MB";
  return (b/1024/1024/1024).toFixed(2) + " GB";
}
function fmtDate(ts){ return new Date(ts*1000).toLocaleString("id-ID"); }

async function refresh(){
  $("list").innerHTML = '<div class="empty">Memuat…</div>';
  try{
    const r = await fetch("/api/list?path=" + encodeURIComponent(currentPath), { headers: { "X-Auth-Token": getToken() } });
    const d = await r.json();
    if(!d.ok){ $("list").innerHTML = '<div class="empty" style="color:var(--crit)">' + (d.error || "Error") + '</div>'; return; }
    if(d.items.length === 0){ $("list").innerHTML = '<div class="empty"><i class="fa-solid fa-folder-open"></i><br>Folder kosong</div>'; return; }
    let html = "";
    for(const it of d.items){
      const rel = currentPath ? currentPath.replace(/\/$/,"") + "/" + it.name : it.name;
      const icon = it.is_dir ? "fa-folder dir" : "fa-file";
      html += `
        <div class="item">
          <div class="ico ${it.is_dir ? "dir" : ""}"><i class="fa-solid ${icon}"></i></div>
          <div class="meta">
            <div class="name">${it.name}</div>
            <div class="info">${it.is_dir ? "Folder" : fmtSize(it.size)} · ${fmtDate(it.mtime)}</div>
          </div>
          <div class="actions">
            ${it.is_dir
              ? `<button class="dl" onclick="openDir('${rel.replace(/'/g,"\\'")}')"><i class="fa-solid fa-folder-open"></i></button>`
              : `<button class="dl" onclick="download('${rel.replace(/'/g,"\\'")}')"><i class="fa-solid fa-download"></i></button>`}
            <button onclick="del('${rel.replace(/'/g,"\\'")}', ${it.is_dir})"><i class="fa-solid fa-trash"></i></button>
          </div>
        </div>`;
    }
    $("list").innerHTML = html;
  }catch(e){ $("list").innerHTML = '<div class="empty" style="color:var(--crit)">Gagal memuat: '+e.message+'</div>'; }
}

function openDir(p){ currentPath = p; $("path").value = p; refresh(); }
function go(){ currentPath = $("path").value.trim(); refresh(); }
function goUp(){
  if(!currentPath) return;
  const parts = currentPath.split("/").filter(Boolean);
  parts.pop();
  currentPath = parts.join("/");
  $("path").value = currentPath;
  refresh();
}
function download(rel){
  const url = "/" + encodeURIComponent(rel).replace(/%2F/g, "/") + "?token=" + encodeURIComponent(getToken());
  window.open(url, "_blank");
}
async function del(rel, isDir){
  if(!confirm(`Hapus ${isDir ? "folder" : "file"} "${rel}"?`)) return;
  try{
    const r = await fetch("/api/delete", { method: "POST", headers: {"Content-Type": "application/json", "X-Auth-Token": getToken()}, body: JSON.stringify({path: rel}) });
    const d = await r.json();
    if(d.ok){ toast("Berhasil dihapus"); refresh(); } else toast(d.error || "Gagal", true);
  }catch(e){ toast(e.message, true); }
}
async function uploadFiles(files){
  if(!files.length) return;
  const fd = new FormData();
  fd.append("path", currentPath);
  for(const f of files) fd.append("files", f, f.name);
  try{
    const r = await fetch("/api/upload", { method: "POST", headers: {"X-Auth-Token": getToken()}, body: fd });
    const d = await r.json();
    if(d.ok){ toast("Terupload: " + d.saved.join(", ")); refresh(); } else toast(d.error || "Gagal upload", true);
  }catch(e){ toast(e.message, true); }
}
$("fileInput").addEventListener("change", e => uploadFiles(e.target.files));
const drop = $("drop");
["dragenter","dragover"].forEach(ev => drop.addEventListener(ev, e => { e.preventDefault(); drop.classList.add("over"); }));
["dragleave","drop"].forEach(ev => drop.addEventListener(ev, e => { e.preventDefault(); drop.classList.remove("over"); }));
drop.addEventListener("drop", e => uploadFiles(e.dataTransfer.files));
refresh();
</script>
</body>
</html>
HTML

# =========================================================
# terminal.html — Multi-tab / Multi-sesi
# =========================================================
cat > "$SERVER_DIR/terminal.html" <<'HTML'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Terminal · Home Server</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
<style>
  :root{--bg:#000;--surface:#0d0d0d;--surface-2:#121212;--border:#1c1c1c;--border-2:#262626;--text:#f0f0f0;--text-dim:#a0a0a0;--text-mute:#6a6a6a;--crit:#c86161;}
  *{box-sizing:border-box;margin:0;padding:0}
  html,body{background:#000;height:100%}
  body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#000;color:var(--text);min-height:100vh;display:flex;flex-direction:column;-webkit-font-smoothing:antialiased}

  .topbar{position:sticky;top:0;z-index:50;display:flex;align-items:center;justify-content:space-between;padding:18px 20px;background:#000;border-bottom:1px solid var(--border)}
  .brand{display:flex;align-items:center;gap:12px;font-size:17px;font-weight:700;letter-spacing:1.5px;color:var(--text)}
  .brand i{font-size:22px;color:var(--text)}
  .menu-btn{width:44px;height:44px;border-radius:12px;background:#121212;border:1px solid var(--border-2);color:var(--text);cursor:pointer;display:flex;align-items:center;justify-content:center;font-size:16px;transition:background .15s,border-color .15s}
  .menu-btn:hover{background:#1a1a1a;border-color:#333}
  .menu-wrap{position:relative}
  .dropdown{position:absolute;top:calc(100% + 10px);right:0;min-width:260px;background:#0d0d0d;border:1px solid var(--border-2);border-radius:16px;padding:8px;box-shadow:0 20px 60px rgba(0,0,0,.9);opacity:0;transform:translateY(-6px) scale(.98);pointer-events:none;transition:opacity .16s,transform .16s;transform-origin:top right}
  .dropdown.open{opacity:1;transform:translateY(0) scale(1);pointer-events:auto}
  .dropdown a{display:flex;align-items:center;gap:14px;padding:14px 16px;border-radius:10px;color:var(--text);text-decoration:none;font-size:15px;font-weight:500;transition:background .15s}
  .dropdown a:hover{background:#1a1a1a}
  .dropdown a.active{background:#1f1f1f}
  .dropdown a i.mi{font-size:18px;color:var(--text-dim);width:22px;text-align:center}
  .dropdown a .label{flex:1}
  .dropdown a .arrow{color:var(--text-mute);font-size:14px}

  .wrap{max-width:1200px;margin:0 auto;padding:20px 20px 40px;width:100%;flex:1;display:flex;flex-direction:column;min-height:0}
  .page-title{display:flex;align-items:center;justify-content:space-between;margin-bottom:16px;gap:12px;flex-wrap:wrap}
  .page-title h2{font-size:22px;font-weight:700;letter-spacing:-.3px;color:var(--text)}

  .tabbar{display:flex;align-items:center;gap:6px;background:#0d0d0d;border:1px solid var(--border);border-radius:12px 12px 0 0;padding:6px 8px;border-bottom:none;overflow-x:auto;scrollbar-width:none}
  .tabbar::-webkit-scrollbar{display:none}
  .tab{display:inline-flex;align-items:center;gap:8px;padding:9px 14px;border-radius:8px;background:#141414;border:1px solid var(--border-2);color:var(--text-dim);font-size:13px;font-weight:500;cursor:pointer;white-space:nowrap;transition:.15s;user-select:none}
  .tab:hover{background:#1a1a1a;color:var(--text)}
  .tab.active{background:#1f1f1f;color:var(--text);border-color:#333}
  .tab .close{width:18px;height:18px;border-radius:50%;display:inline-flex;align-items:center;justify-content:center;font-size:11px;color:var(--text-mute);transition:.15s}
  .tab .close:hover{background:var(--crit);color:#fff}
  .tab-add{padding:9px 12px;border-radius:8px;background:transparent;border:1px dashed var(--border-2);color:var(--text-dim);cursor:pointer;font-size:13px;transition:.15s;display:inline-flex;align-items:center;gap:6px}
  .tab-add:hover{border-color:#444;color:var(--text);background:#141414}
  .tab-add:disabled{opacity:.4;cursor:not-allowed}

  .status-pill{margin-left:auto;display:inline-flex;align-items:center;gap:6px;font-size:11px;color:var(--text-mute);padding:6px 10px;background:#0d0d0d;border:1px solid var(--border);border-radius:999px;white-space:nowrap}
  .dot{width:6px;height:6px;border-radius:50%;background:var(--crit)}
  .dot.on{background:#4ade80}

  .term-host{flex:1;background:#000;border:1px solid var(--border);border-radius:0 0 12px 12px;overflow:hidden;min-height:65vh;position:relative;display:flex;flex-direction:column}
  .term-pane{position:absolute;inset:0;display:none;background:#000}
  .term-pane.active{display:block}
  .term-pane iframe{width:100%;height:100%;border:none;display:block;background:#000}

  .empty-state{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:16px;color:var(--text-mute);text-align:center;padding:30px}
  .empty-state i{font-size:40px;color:#333}
  .empty-state p{font-size:14px;line-height:1.6}
  .empty-state .btn{padding:10px 20px;border-radius:10px;background:#1a1a1a;border:1px solid var(--border-2);color:var(--text);font-size:13px;cursor:pointer;font-weight:500;display:inline-flex;align-items:center;gap:8px}
  .empty-state .btn:hover{background:#222;border-color:#333}

  .toast{position:fixed;bottom:20px;right:20px;background:#1a1a1a;border:1px solid var(--border-2);color:var(--text);padding:14px 20px;border-radius:12px;font-size:13px;opacity:0;transform:translateY(20px);transition:.25s;pointer-events:none;z-index:99;box-shadow:0 10px 40px rgba(0,0,0,.8)}
  .toast.show{opacity:1;transform:translateY(0)}
  .toast.err{border-color:#3a2020;color:var(--crit)}

  .session-info{margin-top:10px;font-size:11px;color:var(--text-mute);text-align:center}
</style>
</head>
<body>

<div class="topbar">
  <div class="brand"><i class="fa-solid fa-cloud"></i> HOME SERVER</div>
  <div class="menu-wrap">
    <button class="menu-btn" id="menuBtn" aria-label="Menu"><i class="fa-solid fa-xmark" id="menuIcon"></i></button>
    <div class="dropdown" id="dropdown">
      <a href="/"><i class="mi fa-solid fa-house"></i><span class="label">Home</span><i class="arrow fa-solid fa-chevron-right"></i></a>
      <a href="/files.html"><i class="mi fa-solid fa-server"></i><span class="label">File</span><i class="arrow fa-solid fa-chevron-right"></i></a>
      <a href="/terminal.html" class="active"><i class="mi fa-solid fa-receipt"></i><span class="label">Terminal</span><i class="arrow fa-solid fa-chevron-right"></i></a>
    </div>
  </div>
</div>

<div class="wrap">
  <div class="page-title">
    <h2>Terminal</h2>
    <div class="status-pill"><span class="dot" id="globalDot"></span><span id="globalStatus">Memeriksa…</span></div>
  </div>

  <div class="tabbar" id="tabbar">
    <button class="tab-add" id="addTab"><i class="fa-solid fa-plus"></i> Sesi Baru</button>
  </div>

  <div class="term-host" id="termHost">
    <div class="empty-state" id="emptyState">
      <i class="fa-solid fa-terminal"></i>
      <p>Belum ada sesi terminal.<br>Klik <b>+ Sesi Baru</b> untuk mulai.</p>
      <button class="btn" id="emptyAdd"><i class="fa-solid fa-plus"></i> Buka Terminal</button>
    </div>
  </div>

  <div class="session-info" id="sessionInfo"></div>
</div>

<div class="toast" id="toast"></div>

<script>
const $ = id => document.getElementById(id);

const menuBtn = document.getElementById('menuBtn');
const menuIcon = document.getElementById('menuIcon');
const dropdown = document.getElementById('dropdown');
menuBtn.addEventListener('click', e => {
  e.stopPropagation();
  const open = dropdown.classList.toggle('open');
  menuIcon.className = open ? 'fa-solid fa-xmark' : 'fa-solid fa-bars';
});
document.addEventListener('click', e => {
  if (!dropdown.contains(e.target) && !menuBtn.contains(e.target)) {
    dropdown.classList.remove('open');
    menuIcon.className = 'fa-solid fa-bars';
  }
});

function toast(msg, err=false){
  const t = $("toast");
  t.textContent = msg;
  t.className = "toast show" + (err ? " err" : "");
  clearTimeout(t._to);
  t._to = setTimeout(()=>t.className = "toast", 2600);
}

const tabs = new Map();
let activeId = null;
let maxSessions = 6;
let ttydAvailable = true;

function renderTabs(){
  const bar = $("tabbar");
  [...bar.querySelectorAll(".tab")].forEach(n => n.remove());
  const addBtn = $("addTab");
  for (const t of tabs.values()){
    const el = document.createElement("div");
    el.className = "tab" + (t.id === activeId ? " active" : "");
    el.innerHTML = `
      <i class="fa-solid fa-terminal" style="font-size:11px;color:var(--text-mute)"></i>
      <span class="tn">${t.label}</span>
      <span class="close" title="Tutup">✕</span>
    `;
    el.addEventListener("click", e => {
      if (e.target.classList.contains("close")) return;
      setActive(t.id);
    });
    el.querySelector(".close").addEventListener("click", e => {
      e.stopPropagation();
      closeTab(t.id);
    });
    bar.insertBefore(el, addBtn);
  }
  updateAddButton();
  updateSessionInfo();
}

function updateAddButton(){
  const btn = $("addTab");
  const full = tabs.size >= maxSessions;
  btn.disabled = full || !ttydAvailable;
  if (!ttydAvailable) btn.title = "ttyd tidak terinstall";
  else if (full) btn.title = `Maksimal ${maxSessions} sesi`;
  else btn.title = "";
}

function updateSessionInfo(){
  $("sessionInfo").textContent = `${tabs.size} / ${maxSessions} sesi aktif`;
}

function updateEmptyState(){
  $("emptyState").style.display = tabs.size === 0 ? "flex" : "none";
}

function setActive(id){
  if (!tabs.has(id)) return;
  activeId = id;
  for (const t of tabs.values()){
    t.paneEl.classList.toggle("active", t.id === id);
  }
  renderTabs();
}

async function newTab(){
  if (tabs.size >= maxSessions){
    toast(`Maksimal ${maxSessions} sesi`, true);
    return;
  }
  try{
    const r = await fetch("/api/terminal/new", { method: "POST" });
    const d = await r.json();
    if (!d.ok){
      toast(d.error || "Gagal membuat sesi", true);
      return;
    }
    const id = d.id;
    const port = d.port;
    const label = `Terminal ${tabs.size + 1}`;

    const paneEl = document.createElement("div");
    paneEl.className = "term-pane";
    paneEl.dataset.id = id;
    const iframe = document.createElement("iframe");
    iframe.src = `http://${location.hostname}:${port}`;
    iframe.allow = "clipboard-read; clipboard-write";
    paneEl.appendChild(iframe);
    $("termHost").appendChild(paneEl);

    tabs.set(id, { id, port, label, paneEl, iframe });
    setActive(id);
    updateEmptyState();
    toast(`Sesi ${label} dibuka (port ${port})`);
  }catch(e){
    toast("Error: " + e.message, true);
  }
}

async function closeTab(id){
  if (!tabs.has(id)) return;
  if (!confirm("Tutup sesi ini? Semua proses di dalamnya akan dihentikan.")) return;
  const t = tabs.get(id);
  tabs.delete(id);
  t.paneEl.remove();
  if (activeId === id){
    const next = tabs.keys().next().value;
    activeId = next || null;
    if (next) setActive(next);
  }
  renderTabs();
  updateEmptyState();
  try{
    await fetch("/api/terminal/kill", {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({ id })
    });
  }catch(e){}
}

async function refreshStatus(){
  try{
    const r = await fetch("/api/terminal-status");
    const d = await r.json();
    ttydAvailable = d.available;
    maxSessions = d.max || 6;

    const serverIds = new Set((d.sessions || []).map(s => s.id));
    for (const [id, t] of [...tabs.entries()]){
      if (!serverIds.has(id)){
        t.paneEl.remove();
        tabs.delete(id);
        if (activeId === id) activeId = null;
      }
    }
    for (const s of (d.sessions || [])){
      if (!tabs.has(s.id)){
        const label = `Terminal ${tabs.size + 1}`;
        const paneEl = document.createElement("div");
        paneEl.className = "term-pane";
        paneEl.dataset.id = s.id;
        const iframe = document.createElement("iframe");
        iframe.src = `http://${location.hostname}:${s.port}`;
        paneEl.appendChild(iframe);
        $("termHost").appendChild(paneEl);
        tabs.set(s.id, { id: s.id, port: s.port, label, paneEl, iframe });
      }
    }
    if (!activeId && tabs.size > 0){
      setActive(tabs.keys().next().value);
    }

    renderTabs();
    updateEmptyState();

    const dot = $("globalDot");
    const st = $("globalStatus");
    if (ttydAvailable){
      dot.classList.add("on");
      st.textContent = `${tabs.size} sesi aktif`;
    } else {
      dot.classList.remove("on");
      st.textContent = "ttyd tidak terinstall";
    }
  }catch(e){
    $("globalStatus").textContent = "Error: " + e.message;
  }
}

$("addTab").addEventListener("click", newTab);
$("emptyAdd").addEventListener("click", newTab);

window.addEventListener("beforeunload", e => {
  if (tabs.size > 0){
    e.preventDefault();
    e.returnValue = "";
  }
});

refreshStatus();
setInterval(refreshStatus, 5000);
</script>
</body>
</html>
HTML

# =========================================================
# server.py — HTTP Server + API + File Manager + Multi-sesi ttyd
# =========================================================
cat > "$SERVER_DIR/server.py" <<PY
#!/usr/bin/env python3
import http.server
import socketserver
import subprocess
import os
import json
import cgi
import shutil
import signal
import time
import urllib.parse

PORT = $PORT
TTYD_BASE_PORT = $TTYD_BASE_PORT
TTYD_MAX_SESSIONS = $TTYD_MAX_SESSIONS
DIRECTORY = os.path.dirname(os.path.abspath(__file__))
AUTH_TOKEN = os.environ.get("HOME_SERVER_TOKEN", "$AUTH_TOKEN")
ALLOWED_ROOT = os.path.expanduser("~")

SESSIONS = {}
SESSION_COUNTER = [0]


def is_safe_path(base, path):
    base = os.path.abspath(base)
    target = os.path.abspath(os.path.join(base, path))
    return target.startswith(base)


def port_in_use(port):
    for s in SESSIONS.values():
        if s["port"] == port:
            return True
    return False


def alloc_port():
    p = TTYD_BASE_PORT
    while port_in_use(p):
        p += 1
    return p


def spawn_ttyd():
    if len(SESSIONS) >= TTYD_MAX_SESSIONS:
        return None
    port = alloc_port()
    try:
        proc = subprocess.Popen(
            ["ttyd", "-p", str(port), "-W", "-t", "titleFixed=Termux Shell", "bash"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            preexec_fn=os.setsid,
        )
    except FileNotFoundError:
        return None
    time.sleep(0.6)
    SESSION_COUNTER[0] += 1
    sid = f"s{SESSION_COUNTER[0]}"
    SESSIONS[sid] = {"port": port, "pid": proc.pid, "created": time.time()}
    return {"id": sid, "port": port}


def kill_ttyd(sid):
    s = SESSIONS.pop(sid, None)
    if not s:
        return False
    try:
        os.killpg(os.getpgid(s["pid"]), signal.SIGTERM)
    except Exception:
        try:
            os.kill(s["pid"], signal.SIGTERM)
        except Exception:
            pass
    return True


def cleanup_dead_sessions():
    dead = []
    for sid, s in SESSIONS.items():
        try:
            os.kill(s["pid"], 0)
        except OSError:
            dead.append(sid)
    for sid in dead:
        SESSIONS.pop(sid, None)


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _check_auth(self):
        token = self.headers.get("X-Auth-Token", "")
        if not token:
            qs = urllib.parse.urlparse(self.path).query
            params = urllib.parse.parse_qs(qs)
            token = params.get("token", [""])[0]
        if token != AUTH_TOKEN:
            self._json(401, {"ok": False, "error": "Unauthorized"})
            return False
        return True

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path

        if path.startswith("/info.json"):
            try:
                out = subprocess.check_output(
                    [os.path.join(DIRECTORY, "info.sh")],
                    timeout=10,
                    stderr=subprocess.DEVNULL,
                )
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(out)
            except Exception:
                self._json(200, {
                    "cpu": {"pct": 0, "cores": 0, "freq": 0, "freq_max": 0, "model": "Error", "arch": "-"},
                    "ram": {"total": 0, "used": 0, "avail": 0, "pct": 0},
                    "disk": {"total": 0, "used": 0, "free": 0, "pct": 0},
                    "net": {"iface": "-", "rx": 0, "tx": 0},
                })
            return

        if path.startswith("/api/list"):
            if not self._check_auth(): return
            qs = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            rel = qs.get("path", [""])[0]
            if not is_safe_path(ALLOWED_ROOT, rel):
                return self._json(403, {"ok": False, "error": "Forbidden"})
            target = os.path.join(ALLOWED_ROOT, rel)
            if not os.path.isdir(target):
                return self._json(404, {"ok": False, "error": "Not a directory"})
            try:
                items = []
                for name in sorted(os.listdir(target)):
                    fp = os.path.join(target, name)
                    try:
                        st = os.stat(fp)
                    except OSError:
                        continue
                    items.append({
                        "name": name,
                        "is_dir": os.path.isdir(fp),
                        "size": st.st_size,
                        "mtime": int(st.st_mtime),
                    })
                self._json(200, {"ok": True, "path": rel, "items": items})
            except Exception as e:
                self._json(500, {"ok": False, "error": str(e)})
            return

        if path.startswith("/api/terminal-status"):
            cleanup_dead_sessions()
            self._json(200, {
                "ok": True,
                "available": shutil.which("ttyd") is not None,
                "sessions": [{"id": k, "port": v["port"]} for k, v in SESSIONS.items()],
                "max": TTYD_MAX_SESSIONS,
            })
            return

        super().do_GET()

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path

        if path == "/api/upload":
            if not self._check_auth(): return
            try:
                ctype, pdict = cgi.parse_header(self.headers.get("Content-Type", ""))
                if ctype != "multipart/form-data":
                    return self._json(400, {"ok": False, "error": "Expected multipart"})
                form = cgi.FieldStorage(
                    fp=self.rfile, headers=self.headers,
                    environ={"REQUEST_METHOD": "POST", "CONTENT_TYPE": self.headers.get("Content-Type")}
                )
                rel_dir = form.getvalue("path", "")
                if not is_safe_path(ALLOWED_ROOT, rel_dir):
                    return self._json(403, {"ok": False, "error": "Forbidden"})
                target_dir = os.path.join(ALLOWED_ROOT, rel_dir)
                os.makedirs(target_dir, exist_ok=True)
                saved = []
                files = form["files"] if "files" in form else []
                if not isinstance(files, list):
                    files = [files]
                for f in files:
                    if not getattr(f, "filename", None): continue
                    safe_name = os.path.basename(f.filename)
                    dest = os.path.join(target_dir, safe_name)
                    with open(dest, "wb") as out:
                        shutil.copyfileobj(f.file, out)
                    saved.append(safe_name)
                self._json(200, {"ok": True, "saved": saved})
            except Exception as e:
                self._json(500, {"ok": False, "error": str(e)})
            return

        if path == "/api/delete":
            if not self._check_auth(): return
            try:
                length = int(self.headers.get("Content-Length", 0))
                data = json.loads(self.rfile.read(length) or b"{}")
                rel = data.get("path", "")
                if not is_safe_path(ALLOWED_ROOT, rel):
                    return self._json(403, {"ok": False, "error": "Forbidden"})
                target = os.path.join(ALLOWED_ROOT, rel)
                if not os.path.exists(target):
                    return self._json(404, {"ok": False, "error": "Not found"})
                if os.path.isdir(target):
                    shutil.rmtree(target)
                else:
                    os.remove(target)
                self._json(200, {"ok": True})
            except Exception as e:
                self._json(500, {"ok": False, "error": str(e)})
            return

        if path == "/api/terminal/new":
            cleanup_dead_sessions()
            r = spawn_ttyd()
            if r is None:
                if shutil.which("ttyd") is None:
                    return self._json(500, {"ok": False, "error": "ttyd tidak terinstall"})
                return self._json(429, {"ok": False, "error": f"Maksimal {TTYD_MAX_SESSIONS} sesi"})
            self._json(200, {"ok": True, **r})
            return

        if path == "/api/terminal/kill":
            try:
                length = int(self.headers.get("Content-Length", 0))
                data = json.loads(self.rfile.read(length) or b"{}")
                sid = data.get("id", "")
                ok = kill_ttyd(sid)
                self._json(200, {"ok": ok})
            except Exception as e:
                self._json(500, {"ok": False, "error": str(e)})
            return

        self._json(404, {"ok": False, "error": "Not found"})

    def log_message(self, fmt, *args):
        pass


socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
    print(f"Server berjalan di port {PORT}")
    httpd.serve_forever()
PY
chmod +x "$SERVER_DIR/server.py"

# =========================================================
# Deteksi IP lokal
# =========================================================
IP=$(ip -4 route get 1.1.1.1 2>/dev/null |
  awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
if [ -z "$IP" ]; then
  IP=$(ip -4 addr show wlan0 2>/dev/null |
    awk '/inet / {sub(/\/.*/, "", $2); print $2; exit}')
fi

# =========================================================
# Bersihkan ttyd lama (jika ada)
# =========================================================
pkill -f "ttyd -p " 2>/dev/null || true
sleep 1

echo
echo "================================"
echo "         SERVER SIAP"
echo "================================"
echo "Folder server    : $SERVER_DIR"
echo "Port web         : $PORT"
echo "Port ttyd (base) : $TTYD_BASE_PORT (multi-sesi, max $TTYD_MAX_SESSIONS)"
echo "Token akses      : $AUTH_TOKEN"
echo "IP lokal         : ${IP:-Tidak terdeteksi}"
echo
echo "Buka di browser perangkat lain:"
echo "  Dashboard : http://${IP:-IP-HP-SERVER}:$PORT"
echo "  File      : http://${IP:-IP-HP-SERVER}:$PORT/files.html"
echo "  Terminal  : http://${IP:-IP-HP-SERVER}:$PORT/terminal.html"
echo
echo "Multi-tab terminal: klik '+ Sesi Baru' untuk buka shell tambahan."
echo "Tekan CTRL+C untuk menghentikan server."
echo

cd "$SERVER_DIR"
trap 'pkill -f "ttyd -p " 2>/dev/null || true; exit 0' INT TERM
exec python server.py
