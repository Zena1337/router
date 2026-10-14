#!/data/data/com.termux/files/usr/bin/bash
# =========================================================
#   ANDROID HOME SERVER - All in One (AVENOX THEME)
#   Dashboard + File Manager + Web Terminal (ttyd)
# =========================================================

set -e

PORT=8080
TTYD_PORT=7681
SERVER_DIR="$HOME/home-server"
# =========================================================
# TOKEN KEAMANAN - WAJIB DIGANTI!
# =========================================================
AUTH_TOKEN="${HOME_SERVER_TOKEN:-rahasia123}"

echo "================================"
echo "     ANDROID HOME SERVER"
echo "================================"

# ---------- Install dependencies ----------
pkg update -y
pkg install -y python openssh iproute2 procps ttyd

mkdir -p "$SERVER_DIR"

# =========================================================
# info.sh — Output JSON: CPU, RAM, Disk, Network
# =========================================================
cat > "$SERVER_DIR/info.sh" <<'SH'
#!/data/data/com.termux/files/usr/bin/bash
# Output JSON: CPU, RAM, Disk, Network

# =========================================================
# CPU USAGE (multi-strategi)
# =========================================================
CPU_PCT="0.0"

# --- Strategi 1: /proc/stat ---
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

# --- Strategi 2: top -bn1 ---
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

# --- Strategi 3: loadavg ---
if [ "$CPU_PCT" = "0.0" ]; then
  LA=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
  CORES=$(nproc 2>/dev/null || echo 1)
  if [ -n "$LA" ] && [ "$CORES" -gt 0 ]; then
    CPU_PCT=$(awk "BEGIN {p=($LA/$CORES)*100; if(p>100)p=100; printf \"%.1f\", p}")
  fi
fi

# =========================================================
# INFO PROCESSOR
# =========================================================
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

# =========================================================
# RAM
# =========================================================
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

# =========================================================
# DISK
# =========================================================
DISK_INFO=$(df -k "$HOME" | awk 'NR==2 {print $2, $3, $4}')
DISK_TOTAL=$(echo "$DISK_INFO" | awk '{printf "%.1f", $1/1024/1024}')
DISK_USED=$(echo "$DISK_INFO"  | awk '{printf "%.1f", $2/1024/1024}')
DISK_FREE=$(echo "$DISK_INFO"  | awk '{printf "%.1f", $3/1024/1024}')
if awk "BEGIN{exit !($DISK_TOTAL>0)}"; then
  DISK_PCT=$(awk "BEGIN {printf \"%.1f\", ($DISK_USED/$DISK_TOTAL)*100}")
else
  DISK_PCT="0.0"
fi

# =========================================================
# NETWORK
# =========================================================
IFACE=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
[ -z "$IFACE" ] && IFACE="wlan0"

RX1=$(cat /sys/class/net/$IFACE/statistics/rx_bytes 2>/dev/null || echo 0)
TX1=$(cat /sys/class/net/$IFACE/statistics/tx_bytes 2>/dev/null || echo 0)
sleep 0.5
RX2=$(cat /sys/class/net/$IFACE/statistics/rx_bytes 2>/dev/null || echo 0)
TX2=$(cat /sys/class/net/$IFACE/statistics/tx_bytes 2>/dev/null || echo 0)

RX_MBPS=$(awk "BEGIN {printf \"%.2f\", (($RX2-$RX1)*8)/500000}")
TX_MBPS=$(awk "BEGIN {printf \"%.2f\", (($TX2-$TX1)*8)/500000}")

# =========================================================
# JSON
# =========================================================
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
# index.html — Dashboard (AVENOX THEME)
# =========================================================
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
      --bg: #000000; --bg-soft: #0a0a0a;
      --card: #0d0d0d; --card-2: #111111; --border: #1f1f1f;
      --text: #f5f5f5; --muted: #8a8a8a;
      --accent: #00e0c6; --accent-2: #00b3a0;
      --green: #00e0c6; --amber: #ffb020; --red: #ff4d4d;
      --blue: #4db8ff; --purple: #a78bfa;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
      background: radial-gradient(circle at 50% 0%, #0a0a0a 0%, #000 70%);
      color: var(--text); min-height: 100vh; padding: 24px 16px;
    }
    .wrap { max-width: 760px; margin: 0 auto; }
    header { text-align: center; margin-bottom: 28px; }

    .logo {
      display: inline-flex; align-items: center; justify-content: center;
      width: 64px; height: 64px; border-radius: 16px;
      background: #0d0d0d;
      border: 1px solid var(--accent);
      box-shadow: 0 0 24px rgba(0,224,198,.25), inset 0 0 20px rgba(0,224,198,.08);
      font-size: 26px; color: var(--accent); margin-bottom: 14px;
    }
    h1 {
      font-size: 22px; font-weight: 700; letter-spacing: .5px;
      text-transform: uppercase;
      color: var(--text);
    }
    h1 span { color: var(--accent); }
    .sub {
      font-size: 12px; color: var(--muted); margin-top: 8px;
      display: inline-flex; align-items: center; gap: 8px;
      letter-spacing: 1.5px; text-transform: uppercase;
    }
    .dot {
      width: 7px; height: 7px; border-radius: 50%;
      background: var(--accent);
      box-shadow: 0 0 10px var(--accent);
      animation: pulse 1.6s infinite;
    }
    @keyframes pulse {
      0%,100% { opacity: 1; transform: scale(1); }
      50% { opacity: .4; transform: scale(.8); }
    }

    .nav { display: flex; gap: 8px; justify-content: center; margin-top: 18px; flex-wrap: wrap; }
    .nav a {
      color: var(--muted); text-decoration: none; font-size: 12px;
      padding: 8px 14px; border-radius: 8px;
      border: 1px solid var(--border);
      background: var(--card);
      letter-spacing: .5px; text-transform: uppercase;
      transition: .2s;
    }
    .nav a:hover { color: var(--accent); border-color: var(--accent); box-shadow: 0 0 12px rgba(0,224,198,.2); }
    .nav a.active { color: var(--accent); border-color: var(--accent); background: rgba(0,224,198,.06); }

    .grid { display: grid; grid-template-columns: 1fr; gap: 14px; }
    @media (min-width: 620px) {
      .grid { grid-template-columns: 1fr 1fr; }
      .card.full { grid-column: 1 / -1; }
    }

    .card {
      background: linear-gradient(160deg, var(--card) 0%, var(--card-2) 100%);
      border: 1px solid var(--border); border-radius: 14px;
      padding: 18px; position: relative; overflow: hidden;
    }
    .card::before {
      content: ''; position: absolute; top: 0; left: 0; right: 0; height: 1px;
      background: linear-gradient(90deg, transparent, var(--accent), transparent);
      opacity: .6;
    }

    .card-head { display: flex; align-items: center; gap: 10px; margin-bottom: 14px; }
    .card-head i.ic {
      width: 34px; height: 34px;
      display: inline-flex; align-items: center; justify-content: center;
      border-radius: 9px; font-size: 14px;
      background: #0a0a0a; border: 1px solid var(--border);
      color: var(--accent);
      flex-shrink: 0;
    }
    .ic-cpu, .ic-ram, .ic-disk, .ic-net {
      background: #0a0a0a !important;
      color: var(--accent) !important;
      border: 1px solid var(--border);
    }
    .card-head h2 {
      font-size: 12px; font-weight: 600;
      letter-spacing: 2px; text-transform: uppercase;
      color: var(--muted);
    }
    .card-head .badge {
      margin-left: auto; font-size: 10px; color: var(--accent);
      background: rgba(0,224,198,.06); padding: 3px 9px;
      border: 1px solid rgba(0,224,198,.25);
      border-radius: 6px; white-space: nowrap;
      letter-spacing: 1px; text-transform: uppercase;
    }

    .chip {
      display: flex; align-items: center; gap: 10px;
      padding: 10px 12px; background: #080808;
      border: 1px solid var(--border); border-radius: 9px;
      margin-bottom: 12px; font-size: 13px;
    }
    .chip i { color: var(--accent); }
    .chip .model { font-weight: 600; color: #ededed;
      overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .chip .arch {
      margin-left: auto; font-size: 10px; color: var(--muted);
      background: #0f0f0f; padding: 3px 8px; border-radius: 5px;
      border: 1px solid var(--border);
      letter-spacing: 1px; text-transform: uppercase;
    }

    .row { display: flex; justify-content: space-between; align-items: center;
      font-size: 13px; margin: 8px 0; }
    .row .lbl { color: var(--muted); display: inline-flex; align-items: center; gap: 8px; }
    .row .lbl i { color: var(--accent); opacity: .8; font-size: 11px; }
    .row .val { font-weight: 600; color: #ededed; font-variant-numeric: tabular-nums; }

    .bar {
      height: 6px; border-radius: 4px;
      background: #080808; overflow: hidden; margin-top: 14px;
      border: 1px solid var(--border);
    }
    .fill {
      height: 100%; width: 0%; border-radius: 4px;
      background: linear-gradient(90deg, var(--accent-2), var(--accent));
      box-shadow: 0 0 12px rgba(0,224,198,.5);
      transition: width .45s ease, background .3s;
    }
    .fill.warn { background: linear-gradient(90deg,#cc8c1a,#ffb020); box-shadow: 0 0 12px rgba(255,176,32,.5); }
    .fill.crit { background: linear-gradient(90deg,#cc3d3d,#ff4d4d); box-shadow: 0 0 12px rgba(255,77,77,.5); }

    .big-pct { font-size: 26px; font-weight: 700; font-variant-numeric: tabular-nums; letter-spacing: -.5px; }
    .pct-green { color: var(--accent); }
    .pct-amber { color: var(--amber); }
    .pct-red   { color: var(--red); }

    .net-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
    .net-box {
      background: #080808; border: 1px solid var(--border);
      border-radius: 11px; padding: 16px 10px; text-align: center;
    }
    .net-box i { font-size: 15px; margin-bottom: 8px; display: block; color: var(--accent); }
    .net-box .num {
      font-size: 20px; font-weight: 700;
      font-variant-numeric: tabular-nums; line-height: 1.2;
      color: var(--accent);
    }
    .net-box .lbl {
      font-size: 10px; color: var(--muted); margin-top: 6px;
      text-transform: uppercase; letter-spacing: 1.5px;
    }
    .dl i, .dl .num { color: var(--accent); }
    .ul i, .ul .num { color: var(--blue); }

    footer {
      text-align: center; font-size: 11px; color: var(--muted);
      margin-top: 24px; padding-top: 18px; border-top: 1px solid var(--border);
      letter-spacing: 1px; text-transform: uppercase;
    }
    footer i { color: var(--accent); }
  </style>
</head>
<body>
  <div class="wrap">
    <header>
      <div class="logo"><i class="fa-solid fa-server"></i></div>
      <h1>Home <span>Server</span></h1>
      <div class="sub"><span class="dot"></span>Live monitoring · Android</div>
      <div class="nav">
        <a href="/" class="active"><i class="fa-solid fa-gauge-high"></i> Dashboard</a>
        <a href="/files.html"><i class="fa-solid fa-folder"></i> Files</a>
        <a href="/terminal.html"><i class="fa-solid fa-terminal"></i> Terminal</a>
      </div>
    </header>

    <div class="grid">
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
    </div>

    <footer>
      <i class="fa-solid fa-rotate"></i> Auto-refresh 2 detik &nbsp;·&nbsp;
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
# files.html — File Manager (AVENOX THEME)
# =========================================================
cat > "$SERVER_DIR/files.html" <<'HTML'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>File Manager · Home Server</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
<style>
  :root{--bg:#000;--card:#0d0d0d;--card-2:#111;--border:#1f1f1f;--text:#f5f5f5;--muted:#8a8a8a;--accent:#00e0c6;--accent-2:#00b3a0;--green:#00e0c6;--red:#ff4d4d;--amber:#ffb020;--blue:#4db8ff;}
  *{box-sizing:border-box;margin:0;padding:0}
  body{font-family:'Segoe UI',system-ui,sans-serif;background:radial-gradient(circle at 50% 0%,#0a0a0a 0%,#000 70%);color:var(--text);min-height:100vh;padding:20px 14px}
  .wrap{max-width:820px;margin:0 auto}
  header{text-align:center;margin-bottom:20px}
  h1{font-size:18px;text-transform:uppercase;letter-spacing:1px;color:var(--text)}
  h1 i{color:var(--accent)}
  .sub{font-size:11px;color:var(--muted);margin-top:6px;letter-spacing:1.5px;text-transform:uppercase}
  .nav{display:flex;gap:8px;justify-content:center;margin-top:14px;flex-wrap:wrap}
  .nav a{color:var(--muted);text-decoration:none;font-size:11px;padding:8px 14px;border-radius:8px;border:1px solid var(--border);background:var(--card);letter-spacing:.8px;text-transform:uppercase;transition:.2s}
  .nav a:hover,.nav a.active{color:var(--accent);border-color:var(--accent);background:rgba(0,224,198,.05);box-shadow:0 0 12px rgba(0,224,198,.18)}

  .toolbar{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:14px;align-items:center}
  .btn{padding:8px 14px;border-radius:8px;border:1px solid var(--border);background:var(--card);color:var(--text);font-size:12px;cursor:pointer;display:inline-flex;align-items:center;gap:6px;transition:.2s;letter-spacing:.5px}
  .btn:hover{border-color:var(--accent);color:var(--accent);box-shadow:0 0 10px rgba(0,224,198,.15)}
  .btn.primary{background:linear-gradient(135deg,var(--accent-2),var(--accent));border:none;color:#000;font-weight:600}
  .btn.danger{border-color:var(--red);color:var(--red)}
  .btn.danger:hover{background:rgba(255,77,77,.08);box-shadow:0 0 10px rgba(255,77,77,.2)}

  .path{flex:1;min-width:200px;padding:9px 12px;background:#080808;border:1px solid var(--border);border-radius:8px;color:var(--text);font-size:12px;font-family:ui-monospace,monospace}
  .path:focus{outline:none;border-color:var(--accent);box-shadow:0 0 0 2px rgba(0,224,198,.12)}

  .card{background:linear-gradient(160deg,var(--card) 0%,var(--card-2) 100%);border:1px solid var(--border);border-radius:12px;padding:10px;position:relative;overflow:hidden}
  .card::before{content:'';position:absolute;top:0;left:0;right:0;height:1px;background:linear-gradient(90deg,transparent,var(--accent),transparent);opacity:.5}

  .item{display:flex;align-items:center;gap:12px;padding:11px 12px;border-radius:8px;border-bottom:1px solid var(--border);transition:.15s}
  .item:last-child{border-bottom:none}
  .item:hover{background:rgba(0,224,198,.04)}
  .item .ico{width:34px;height:34px;display:flex;align-items:center;justify-content:center;border-radius:8px;background:#080808;border:1px solid var(--border);color:var(--accent);flex-shrink:0;font-size:13px}
  .item .ico.dir{color:var(--amber)}
  .item .meta{flex:1;min-width:0}
  .item .name{font-size:13px;font-weight:500;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:#ededed}
  .item .info{font-size:10px;color:var(--muted);margin-top:3px;letter-spacing:.5px;text-transform:uppercase}
  .item .actions{display:flex;gap:6px}
  .item .actions button{width:32px;height:32px;border-radius:6px;border:1px solid var(--border);background:#080808;color:var(--muted);cursor:pointer;font-size:12px;transition:.2s}
  .item .actions button:hover{border-color:var(--red);color:var(--red)}
  .item .actions button.dl:hover{border-color:var(--accent);color:var(--accent);box-shadow:0 0 8px rgba(0,224,198,.25)}
  .empty{text-align:center;padding:40px 20px;color:var(--muted);font-size:12px;letter-spacing:1px;text-transform:uppercase}

  .drop{border:1px dashed var(--border);border-radius:12px;padding:26px;text-align:center;color:var(--muted);font-size:12px;margin-bottom:14px;transition:.2s;background:#080808;letter-spacing:.5px}
  .drop.over{border-color:var(--accent);background:rgba(0,224,198,.05);color:var(--accent);box-shadow:0 0 20px rgba(0,224,198,.15) inset}
  .drop i{color:var(--accent)}

  .token-bar{display:flex;gap:8px;margin-bottom:14px}
  .token-bar input{flex:1;padding:9px 12px;background:#080808;border:1px solid var(--border);border-radius:8px;color:var(--text);font-size:12px;font-family:ui-monospace,monospace}
  .token-bar input:focus{outline:none;border-color:var(--accent);box-shadow:0 0 0 2px rgba(0,224,198,.12)}

  .toast{position:fixed;bottom:20px;right:20px;background:var(--card);border:1px solid var(--accent);color:var(--accent);padding:12px 18px;border-radius:10px;font-size:12px;opacity:0;transform:translateY(20px);transition:.3s;pointer-events:none;z-index:99;letter-spacing:.5px;box-shadow:0 0 20px rgba(0,224,198,.2)}
  .toast.show{opacity:1;transform:translateY(0)}
  .toast.err{border-color:var(--red);color:var(--red);box-shadow:0 0 20px rgba(255,77,77,.2)}
</style>
</head>
<body>
<div class="wrap">
  <header>
    <h1><i class="fa-solid fa-folder-tree"></i> File Manager</h1>
    <div class="sub">Upload · Download · Hapus</div>
    <div class="nav">
      <a href="/"><i class="fa-solid fa-gauge-high"></i> Dashboard</a>
      <a href="/files.html" class="active"><i class="fa-solid fa-folder"></i> Files</a>
      <a href="/terminal.html"><i class="fa-solid fa-terminal"></i> Terminal</a>
    </div>
  </header>

  <div class="token-bar">
    <input type="password" id="token" placeholder="Token akses (X-Auth-Token)">
    <button class="btn" onclick="saveToken()"><i class="fa-solid fa-key"></i></button>
  </div>

  <div class="toolbar">
    <input class="path" id="path" value="" placeholder="Path relatif dari HOME">
    <button class="btn" onclick="go()"><i class="fa-solid fa-arrow-right"></i></button>
    <button class="btn" onclick="goUp()"><i class="fa-solid fa-arrow-up"></i></button>
    <button class="btn" onclick="refresh()"><i class="fa-solid fa-rotate"></i></button>
  </div>

  <div class="drop" id="drop">
    <i class="fa-solid fa-cloud-arrow-up" style="font-size:24px"></i>
    <div style="margin-top:8px">Tarik & lepas file di sini, atau <label for="fileInput" style="color:var(--accent);cursor:pointer;text-decoration:underline">pilih file</label></div>
    <input type="file" id="fileInput" multiple style="display:none">
  </div>

  <div class="card" id="list">
    <div class="empty">Memuat…</div>
  </div>
</div>

<div class="toast" id="toast"></div>

<script>
const $ = id => document.getElementById(id);
let currentPath = "";

function saveToken(){
  localStorage.setItem("hs_token", $("token").value);
  toast("Token disimpan");
  refresh();
}
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
    const r = await fetch("/api/list?path=" + encodeURIComponent(currentPath), {
      headers: { "X-Auth-Token": getToken() }
    });
    const d = await r.json();
    if(!d.ok){ $("list").innerHTML = '<div class="empty" style="color:var(--red)">' + (d.error || "Error") + '</div>'; return; }
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
  }catch(e){ $("list").innerHTML = '<div class="empty" style="color:var(--red)">Gagal memuat: '+e.message+'</div>'; }
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
    const r = await fetch("/api/delete", {
      method: "POST",
      headers: {"Content-Type": "application/json", "X-Auth-Token": getToken()},
      body: JSON.stringify({path: rel})
    });
    const d = await r.json();
    if(d.ok){ toast("Berhasil dihapus"); refresh(); }
    else toast(d.error || "Gagal", true);
  }catch(e){ toast(e.message, true); }
}

async function uploadFiles(files){
  if(!files.length) return;
  const fd = new FormData();
  fd.append("path", currentPath);
  for(const f of files) fd.append("files", f, f.name);
  try{
    const r = await fetch("/api/upload", {
      method: "POST",
      headers: {"X-Auth-Token": getToken()},
      body: fd
    });
    const d = await r.json();
    if(d.ok){ toast("Terupload: " + d.saved.join(", ")); refresh(); }
    else toast(d.error || "Gagal upload", true);
  }catch(e){ toast(e.message, true); }
}

$("fileInput").addEventListener("change", e => uploadFiles(e.target.files));

const drop = $("drop");
["dragenter","dragover"].forEach(ev => drop.addEventListener(ev, e => {
  e.preventDefault(); drop.classList.add("over");
}));
["dragleave","drop"].forEach(ev => drop.addEventListener(ev, e => {
  e.preventDefault(); drop.classList.remove("over");
}));
drop.addEventListener("drop", e => uploadFiles(e.dataTransfer.files));

refresh();
</script>
</body>
</html>
HTML

# =========================================================
# terminal.html — Web Terminal (AVENOX THEME)
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
  :root{--bg:#000;--card:#0d0d0d;--border:#1f1f1f;--text:#f5f5f5;--muted:#8a8a8a;--accent:#00e0c6;--green:#00e0c6;--red:#ff4d4d;}
  *{box-sizing:border-box;margin:0;padding:0}
  body{font-family:'Segoe UI',system-ui,sans-serif;background:radial-gradient(circle at 50% 0%,#0a0a0a 0%,#000 70%);color:var(--text);min-height:100vh;padding:20px 14px;display:flex;flex-direction:column}
  .wrap{max-width:1100px;margin:0 auto;width:100%;flex:1;display:flex;flex-direction:column}
  header{text-align:center;margin-bottom:16px}
  h1{font-size:18px;text-transform:uppercase;letter-spacing:1px}
  h1 i{color:var(--accent)}
  .sub{font-size:11px;color:var(--muted);margin-top:6px;letter-spacing:1.5px;text-transform:uppercase}
  .nav{display:flex;gap:8px;justify-content:center;margin-top:14px;flex-wrap:wrap}
  .nav a{color:var(--muted);text-decoration:none;font-size:11px;padding:8px 14px;border-radius:8px;border:1px solid var(--border);background:var(--card);letter-spacing:.8px;text-transform:uppercase;transition:.2s}
  .nav a:hover,.nav a.active{color:var(--accent);border-color:var(--accent);background:rgba(0,224,198,.05);box-shadow:0 0 12px rgba(0,224,198,.18)}

  .term-wrap{flex:1;background:#000;border:1px solid var(--border);border-radius:12px;overflow:hidden;min-height:70vh;position:relative;box-shadow:0 0 24px rgba(0,224,198,.08)}
  iframe{width:100%;height:100%;border:none;display:block;min-height:70vh}

  .notice{background:var(--card);border:1px solid var(--border);border-radius:10px;padding:14px;font-size:12px;color:var(--muted);margin-bottom:14px;letter-spacing:.3px}
  .notice code{background:rgba(0,224,198,.08);color:var(--accent);padding:2px 6px;border-radius:4px;font-family:ui-monospace,monospace;font-size:11px}
  .notice i{color:var(--accent)}

  .status{display:inline-flex;align-items:center;gap:6px;font-size:11px;color:var(--muted);margin-top:8px;letter-spacing:1px;text-transform:uppercase}
  .dot{width:8px;height:8px;border-radius:50%;background:var(--red)}
  .dot.on{background:var(--accent);box-shadow:0 0 10px var(--accent)}
</style>
</head>
<body>
<div class="wrap">
  <header>
    <h1><i class="fa-solid fa-terminal"></i> Web Terminal</h1>
    <div class="sub">Akses shell penuh via ttyd</div>
    <div class="nav">
      <a href="/"><i class="fa-solid fa-gauge-high"></i> Dashboard</a>
      <a href="/files.html"><i class="fa-solid fa-folder"></i> Files</a>
      <a href="/terminal.html" class="active"><i class="fa-solid fa-terminal"></i> Terminal</a>
    </div>
  </header>

  <div class="notice" id="notice">
    <div><i class="fa-solid fa-circle-info"></i> Status: <span id="statusText">Memeriksa…</span> <span class="status"><span class="dot" id="dot"></span></span></div>
    <div style="margin-top:8px" id="hint"></div>
  </div>

  <div class="term-wrap" id="termWrap" style="display:none">
    <iframe id="termFrame" src="about:blank"></iframe>
  </div>
</div>

<script>
async function check(){
  try{
    const r = await fetch("/api/terminal-status");
    const d = await r.json();
    const dot = document.getElementById("dot");
    const txt = document.getElementById("statusText");
    const hint = document.getElementById("hint");
    const wrap = document.getElementById("termWrap");
    const notice = document.getElementById("notice");

    if(d.port){
      dot.classList.add("on");
      txt.textContent = "ttyd aktif di port " + d.port;
      hint.textContent = "";
      wrap.style.display = "block";
      document.getElementById("termFrame").src = "http://" + location.hostname + ":" + d.port;
      notice.style.display = "none";
    } else {
      dot.classList.remove("on");
      txt.textContent = "ttyd tidak berjalan";
      hint.innerHTML = 'Jalankan di Termux: <code>ttyd -p 7681 -W bash</code><br>Atau install: <code>pkg install ttyd</code>';
      wrap.style.display = "none";
    }
  }catch(e){
    document.getElementById("statusText").textContent = "Error: " + e.message;
  }
}
check();
setInterval(check, 5000);
</script>
</body>
</html>
HTML

# =========================================================
# server.py — HTTP Server + API + File Manager + Terminal Check
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
import urllib.parse

PORT = $PORT
DIRECTORY = os.path.dirname(os.path.abspath(__file__))

# ========================
# KONFIGURASI KEAMANAN
# ========================
AUTH_TOKEN = os.environ.get("HOME_SERVER_TOKEN", "$AUTH_TOKEN")
ALLOWED_ROOT = os.path.expanduser("~")


def is_safe_path(base, path):
    """Pastikan path tidak keluar dari base directory."""
    base = os.path.abspath(base)
    target = os.path.abspath(os.path.join(base, path))
    return target.startswith(base)


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    # ---------- Helper ----------
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

    def _terminal_port(self):
        try:
            out = subprocess.check_output(
                ["pgrep", "-f", "ttyd"], stderr=subprocess.DEVNULL
            ).decode().strip()
            return $TTYD_PORT if out else 0
        except Exception:
            return 0

    # ---------- GET ----------
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
                    "cpu": {"pct": 0, "cores": 0, "freq": 0, "freq_max": 0,
                            "model": "Error", "arch": "-"},
                    "ram": {"total": 0, "used": 0, "avail": 0, "pct": 0},
                    "disk": {"total": 0, "used": 0, "free": 0, "pct": 0},
                    "net": {"iface": "-", "rx": 0, "tx": 0},
                })
            return

        if path.startswith("/api/list"):
            if not self._check_auth():
                return
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
            port = self._terminal_port()
            self._json(200, {"ok": True, "port": port})
            return

        super().do_GET()

    # ---------- POST ----------
    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path

        if path == "/api/upload":
            if not self._check_auth():
                return
            try:
                ctype, pdict = cgi.parse_header(self.headers.get("Content-Type", ""))
                if ctype != "multipart/form-data":
                    return self._json(400, {"ok": False, "error": "Expected multipart"})
                form = cgi.FieldStorage(
                    fp=self.rfile, headers=self.headers,
                    environ={"REQUEST_METHOD": "POST",
                             "CONTENT_TYPE": self.headers.get("Content-Type")}
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
                    if not getattr(f, "filename", None):
                        continue
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
            if not self._check_auth():
                return
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
# Jalankan ttyd (Web Terminal full access)
# =========================================================
if command -v ttyd >/dev/null 2>&1; then
  pkill -f "ttyd -p $TTYD_PORT" 2>/dev/null || true
  sleep 1
  nohup ttyd -p "$TTYD_PORT" -W -t titleFixed="Termux Shell" bash >/dev/null 2>&1 &
  sleep 1
  TTYD_STATUS="aktif di port $TTYD_PORT"
else
  TTYD_STATUS="tidak terinstall"
fi

echo
echo "================================"
echo "         SERVER SIAP"
echo "================================"
echo "Tema          : AVENOX (Black + Cyan Neon)"
echo "Folder server : $SERVER_DIR"
echo "Port web      : $PORT"
echo "Port terminal : $TTYD_PORT ($TTYD_STATUS)"
echo "Token akses   : $AUTH_TOKEN"
echo "IP lokal      : ${IP:-Tidak terdeteksi}"
echo
echo "Buka di browser perangkat lain:"
echo "  Dashboard : http://${IP:-IP-HP-SERVER}:$PORT"
echo "  Files     : http://${IP:-IP-HP-SERVER}:$PORT/files.html"
echo "  Terminal  : http://${IP:-IP-HP-SERVER}:$PORT/terminal.html"
echo
echo "Tekan CTRL+C untuk menghentikan server."
echo

cd "$SERVER_DIR"
trap 'pkill -f "ttyd -p $TTYD_PORT" 2>/dev/null || true; exit 0' INT TERM
exec python server.py
