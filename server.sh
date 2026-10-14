#!/data/data/com.termux/files/usr/bin/bash

set -e

PORT=8080
SERVER_DIR="$HOME/home-server"
UPLOAD_DIR="$SERVER_DIR/files"
TERM_TOKEN="ganti-token-ini-jadi-rahasia"   # <-- GANTI!

echo "================================"
echo "     ANDROID HOME SERVER"
echo "================================"

pkg update -y
pkg install -y python openssh iproute2 procps

mkdir -p "$SERVER_DIR" "$UPLOAD_DIR"

# ======================
# info.sh — sama seperti sebelumnya (multi-strategi CPU)
# ======================
cat > "$SERVER_DIR/info.sh" <<'SH'
#!/data/data/com.termux/files/usr/bin/bash

# CPU
CPU_PCT="0.0"
if [ -r /proc/stat ]; then
  read_cpu_stat() {
    awk '/^cpu / {total=$2+$3+$4+$5+$6+$7+$8+$9; idle=$5+$6; print total, idle; exit}' /proc/stat 2>/dev/null
  }
  CPU1=$(read_cpu_stat); sleep 0.5; CPU2=$(read_cpu_stat)
  if [ -n "$CPU1" ] && [ -n "$CPU2" ]; then
    T1=$(echo "$CPU1"|awk '{print $1}'); I1=$(echo "$CPU1"|awk '{print $2}')
    T2=$(echo "$CPU2"|awk '{print $1}'); I2=$(echo "$CPU2"|awk '{print $2}')
    CPU_PCT=$(awk "BEGIN {dt=$T2-$T1;di=$I2-$I1; if(dt>0) printf \"%.1f\",(1-di/dt)*100; else print \"0.0\"}")
  fi
fi
if [ "$CPU_PCT" = "0.0" ]; then
  TOP_OUT=$(top -bn1 2>/dev/null | head -20)
  IDLE=$(echo "$TOP_OUT" | awk '/[Cc]pu/ {for(i=1;i<=NF;i++){ if($i ~ /^[0-9.]+%?$/ && $(i+1) ~ /id/){gsub(/%/,"",$i);print $i;exit} }}')
  [ -n "$IDLE" ] && CPU_PCT=$(awk "BEGIN {p=100-$IDLE; if(p<0)p=0; printf \"%.1f\", p}")
fi
if [ "$CPU_PCT" = "0.0" ]; then
  LA=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
  CORES=$(nproc 2>/dev/null || echo 1)
  [ -n "$LA" ] && CPU_PCT=$(awk "BEGIN {p=($LA/$CORES)*100; if(p>100)p=100; printf \"%.1f\", p}")
fi

# Processor info
CPU_MODEL=$(awk -F: '/^[Hh]ardware/ {gsub(/^ +/,"",$2);print $2;exit}' /proc/cpuinfo 2>/dev/null)
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(awk -F: '/^[Mm]odel name/ {gsub(/^ +/,"",$2);print $2;exit}' /proc/cpuinfo 2>/dev/null)
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

# RAM
RAM_TOTAL=$(awk '/MemTotal/ {printf "%.0f",$2/1024}' /proc/meminfo 2>/dev/null || echo 0)
RAM_AVAIL=$(awk '/MemAvailable/ {printf "%.0f",$2/1024}' /proc/meminfo 2>/dev/null || echo 0)
[ "$RAM_AVAIL" = "0" ] && RAM_AVAIL=$(awk '/MemFree/ {printf "%.0f",$2/1024}' /proc/meminfo 2>/dev/null || echo 0)
if [ "$RAM_TOTAL" -gt 0 ]; then
  RAM_USED=$((RAM_TOTAL-RAM_AVAIL))
  RAM_PCT=$(awk "BEGIN {printf \"%.1f\",($RAM_USED/$RAM_TOTAL)*100}")
else RAM_USED=0; RAM_PCT="0.0"; fi

# Disk
DISK_INFO=$(df -k "$HOME" | awk 'NR==2 {print $2,$3,$4}')
DISK_TOTAL=$(echo "$DISK_INFO"|awk '{printf "%.1f",$1/1024/1024}')
DISK_USED=$(echo "$DISK_INFO"|awk '{printf "%.1f",$2/1024/1024}')
DISK_FREE=$(echo "$DISK_INFO"|awk '{printf "%.1f",$3/1024/1024}')
DISK_PCT=$(awk "BEGIN {if($DISK_TOTAL>0) printf \"%.1f\",($DISK_USED/$DISK_TOTAL)*100; else print \"0.0\"}")

# Network
IFACE=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1);exit}}')
[ -z "$IFACE" ] && IFACE="wlan0"
RX1=$(cat /sys/class/net/$IFACE/statistics/rx_bytes 2>/dev/null || echo 0)
TX1=$(cat /sys/class/net/$IFACE/statistics/tx_bytes 2>/dev/null || echo 0)
sleep 0.5
RX2=$(cat /sys/class/net/$IFACE/statistics/rx_bytes 2>/dev/null || echo 0)
TX2=$(cat /sys/class/net/$IFACE/statistics/tx_bytes 2>/dev/null || echo 0)
RX_MBPS=$(awk "BEGIN {printf \"%.2f\",(($RX2-$RX1)*8)/500000}")
TX_MBPS=$(awk "BEGIN {printf \"%.2f\",(($TX2-$TX1)*8)/500000}")

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
cat > "$SERVER_DIR/index.html" <<HTML
<!DOCTYPE html>
<html lang="id">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Home Server · Dashboard</title>
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
  <style>
    :root {
      --bg:#0b1120; --card:#111c33; --card-2:#0f172a; --border:#1e293b;
      --text:#e2e8f0; --muted:#94a3b8; --accent:#22d3ee;
      --green:#4ade80; --amber:#fbbf24; --red:#f87171;
      --blue:#60a5fa; --purple:#a78bfa;
    }
    * { box-sizing:border-box; margin:0; padding:0; }
    body {
      font-family:'Segoe UI',system-ui,-apple-system,sans-serif;
      background:radial-gradient(circle at top,#1e293b 0%,var(--bg) 60%);
      color:var(--text); min-height:100vh; padding:20px 14px 40px;
    }
    .wrap { max-width:860px; margin:0 auto; }

    header { text-align:center; margin-bottom:22px; }
    .logo {
      display:inline-flex; align-items:center; justify-content:center;
      width:60px; height:60px; border-radius:16px;
      background:linear-gradient(135deg,#06b6d4,#3b82f6);
      box-shadow:0 8px 24px rgba(6,182,212,.35);
      font-size:26px; color:white; margin-bottom:10px;
    }
    h1 {
      font-size:21px; font-weight:700;
      background:linear-gradient(90deg,#22d3ee,#4ade80);
      -webkit-background-clip:text; -webkit-text-fill-color:transparent;
      background-clip:text;
    }
    .sub { font-size:12px; color:var(--muted); margin-top:4px;
      display:inline-flex; align-items:center; gap:6px; }
    .dot { width:8px; height:8px; border-radius:50%;
      background:var(--green); box-shadow:0 0 10px var(--green);
      animation:pulse 1.6s infinite; }
    @keyframes pulse { 0%,100%{opacity:1;transform:scale(1);} 50%{opacity:.5;transform:scale(.85);} }

    /* Tab nav */
    .tabs {
      display:flex; gap:6px; background:rgba(15,23,42,.7);
      border:1px solid var(--border); border-radius:12px;
      padding:5px; margin-bottom:16px;
    }
    .tab {
      flex:1; padding:9px 12px; text-align:center;
      font-size:13px; font-weight:600; color:var(--muted);
      border-radius:8px; cursor:pointer; transition:all .2s;
      user-select:none;
    }
    .tab i { margin-right:6px; }
    .tab.active { background:linear-gradient(135deg,#06b6d4,#3b82f6);
      color:white; box-shadow:0 4px 12px rgba(6,182,212,.3); }
    .tab:hover:not(.active) { color:var(--text); background:rgba(148,163,184,.08); }

    .panel { display:none; }
    .panel.active { display:block; animation:fade .25s ease; }
    @keyframes fade { from{opacity:0;transform:translateY(6px);} to{opacity:1;transform:translateY(0);} }

    .grid { display:grid; grid-template-columns:1fr; gap:14px; }
    @media (min-width:620px) {
      .grid { grid-template-columns:1fr 1fr; }
      .card.full { grid-column:1/-1; }
    }
    .card {
      background:linear-gradient(160deg,var(--card) 0%,var(--card-2) 100%);
      border:1px solid var(--border); border-radius:16px;
      padding:18px; position:relative; overflow:hidden;
    }
    .card::before {
      content:''; position:absolute; top:0; left:0; right:0; height:2px;
      background:linear-gradient(90deg,transparent,var(--accent),transparent);
      opacity:.5;
    }
    .card-head { display:flex; align-items:center; gap:10px; margin-bottom:14px; }
    .card-head i.ic {
      width:34px; height:34px; display:inline-flex;
      align-items:center; justify-content:center;
      border-radius:10px; font-size:15px; color:white; flex-shrink:0;
    }
    .ic-cpu{background:linear-gradient(135deg,#8b5cf6,#a78bfa);}
    .ic-ram{background:linear-gradient(135deg,#0ea5e9,#22d3ee);}
    .ic-disk{background:linear-gradient(135deg,#f59e0b,#fbbf24);}
    .ic-net{background:linear-gradient(135deg,#10b981,#4ade80);}
    .ic-file{background:linear-gradient(135deg,#ec4899,#f472b6);}
    .ic-term{background:linear-gradient(135deg,#64748b,#94a3b8);}
    .card-head h2 { font-size:14px; font-weight:600; letter-spacing:.3px; }
    .card-head .badge {
      margin-left:auto; font-size:11px; color:var(--muted);
      background:rgba(148,163,184,.1); padding:3px 8px;
      border-radius:6px; white-space:nowrap;
    }
    .chip {
      display:flex; align-items:center; gap:10px;
      padding:10px 12px; background:rgba(15,23,42,.7);
      border:1px solid var(--border); border-radius:10px;
      margin-bottom:12px; font-size:13px;
    }
    .chip i { color:var(--purple); }
    .chip .model { font-weight:600; color:#f1f5f9;
      overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
    .chip .arch { margin-left:auto; font-size:11px; color:var(--muted);
      background:rgba(148,163,184,.1); padding:2px 8px; border-radius:6px; }

    .row { display:flex; justify-content:space-between; align-items:center;
      font-size:13px; margin:7px 0; }
    .row .lbl { color:var(--muted); display:inline-flex; align-items:center; gap:6px; }
    .row .val { font-weight:600; color:#f1f5f9; font-variant-numeric:tabular-nums; }
    .bar { height:8px; border-radius:6px;
      background:rgba(148,163,184,.12); overflow:hidden; margin-top:12px; }
    .fill { height:100%; width:0%; border-radius:6px;
      background:linear-gradient(90deg,#22c55e,#4ade80);
      transition:width .45s ease, background .3s; }
    .fill.warn { background:linear-gradient(90deg,#f59e0b,#fbbf24); }
    .fill.crit { background:linear-gradient(90deg,#ef4444,#f87171); }
    .big-pct { font-size:26px; font-weight:700; font-variant-numeric:tabular-nums; }
    .pct-green{color:var(--green);} .pct-amber{color:var(--amber);} .pct-red{color:var(--red);}

    .net-grid { display:grid; grid-template-columns:1fr 1fr; gap:10px; }
    .net-box {
      background:rgba(15,23,42,.7); border:1px solid var(--border);
      border-radius:12px; padding:14px 10px; text-align:center;
    }
    .net-box i { font-size:16px; margin-bottom:6px; display:block; }
    .net-box .num { font-size:20px; font-weight:700;
      font-variant-numeric:tabular-nums; line-height:1.2; }
    .net-box .lbl { font-size:11px; color:var(--muted);
      margin-top:4px; text-transform:uppercase; letter-spacing:.5px; }
    .dl i,.dl .num{color:var(--green);} .ul i,.ul .num{color:var(--blue);}

    /* File manager */
    .toolbar { display:flex; gap:8px; flex-wrap:wrap; margin-bottom:14px; }
    .btn {
      display:inline-flex; align-items:center; gap:7px;
      padding:9px 14px; border-radius:10px; border:none;
      font-size:13px; font-weight:600; cursor:pointer;
      background:rgba(148,163,184,.12); color:var(--text);
      transition:all .2s; font-family:inherit;
    }
    .btn:hover { background:rgba(148,163,184,.2); }
    .btn.primary {
      background:linear-gradient(135deg,#06b6d4,#3b82f6); color:white;
      box-shadow:0 4px 12px rgba(6,182,212,.3);
    }
    .btn.primary:hover { transform:translateY(-1px); }
    .btn.danger { background:rgba(239,68,68,.15); color:var(--red); }
    .btn.danger:hover { background:rgba(239,68,68,.25); }
    .btn i { font-size:12px; }

    .breadcrumb {
      font-size:12px; color:var(--muted); margin-bottom:10px;
      padding:8px 12px; background:rgba(15,23,42,.7);
      border:1px solid var(--border); border-radius:8px;
      font-family:'JetBrains Mono',monospace; word-break:break-all;
    }
    .breadcrumb a { color:var(--accent); cursor:pointer; text-decoration:none; }

    .file-list { display:flex; flex-direction:column; gap:6px; }
    .file-item {
      display:flex; align-items:center; gap:12px;
      padding:11px 14px; background:rgba(15,23,42,.7);
      border:1px solid var(--border); border-radius:10px;
      font-size:13px; transition:all .15s;
    }
    .file-item:hover { border-color:rgba(34,211,238,.4); background:rgba(15,23,42,.95); }
    .file-item .fi-icon { font-size:16px; width:22px; text-align:center; flex-shrink:0; }
    .file-item .fi-name {
      flex:1; overflow:hidden; text-overflow:ellipsis;
      white-space:nowrap; cursor:pointer;
    }
    .file-item .fi-name:hover { color:var(--accent); }
    .file-item .fi-size { font-size:11px; color:var(--muted);
      font-variant-numeric:tabular-nums; white-space:nowrap; }
    .file-item .fi-actions { display:flex; gap:4px; }
    .file-item .fi-actions button {
      background:transparent; border:none; color:var(--muted);
      cursor:pointer; font-size:13px; padding:4px 6px;
      border-radius:6px; transition:all .15s;
    }
    .file-item .fi-actions button:hover { background:rgba(148,163,184,.15); color:var(--text); }
    .file-item .fi-actions button.del:hover { background:rgba(239,68,68,.2); color:var(--red); }
    .folder { color:var(--amber); }
    .file-img { color:var(--green); }
    .file-txt { color:var(--blue); }
    .file-zip { color:var(--purple); }
    .file-default { color:var(--muted); }

    /* Terminal */
    .term-wrap {
      background:#000; border:1px solid var(--border);
      border-radius:12px; overflow:hidden;
      font-family:'JetBrains Mono','Courier New',monospace;
    }
    .term-head {
      display:flex; align-items:center; gap:8px;
      padding:8px 12px; background:#0a0f1a;
      border-bottom:1px solid var(--border); font-size:12px;
      color:var(--muted);
    }
    .term-head .tdot { width:10px; height:10px; border-radius:50%; }
    .term-head .tdot.r { background:#ff5f57; }
    .term-head .tdot.y { background:#febc2e; }
    .term-head .tdot.g { background:#28c840; }
    .term-body {
      height:420px; overflow-y:auto; padding:12px 14px;
      font-size:12.5px; line-height:1.55;
      color:#e2e8f0; white-space:pre-wrap; word-break:break-word;
    }
    .term-body .cmd { color:#4ade80; }
    .term-body .err { color:#f87171; }
    .term-body .dim { color:#94a3b8; }
    .term-input-row {
      display:flex; align-items:center; gap:8px;
      padding:10px 14px; background:#0a0f1a;
      border-top:1px solid var(--border);
    }
    .term-prompt { color:#22d3ee; font-family:'JetBrains Mono',monospace;
      font-size:13px; white-space:nowrap; }
    .term-input {
      flex:1; background:transparent; border:none; outline:none;
      color:#e2e8f0; font-family:'JetBrains Mono',monospace;
      font-size:13px; padding:4px 0;
    }
    .term-send {
      background:linear-gradient(135deg,#06b6d4,#3b82f6);
      border:none; color:white; border-radius:8px;
      padding:7px 12px; cursor:pointer; font-size:13px;
    }
    .term-send:hover { opacity:.9; }

    footer { text-align:center; font-size:11px; color:var(--muted);
      margin-top:22px; padding-top:16px; border-top:1px solid var(--border); }
    footer i { color:var(--accent); }

    /* Upload progress */
    .progress {
      height:4px; background:rgba(148,163,184,.15);
      border-radius:4px; overflow:hidden; margin-top:10px; display:none;
    }
    .progress.show { display:block; }
    .progress-fill {
      height:100%; width:0%;
      background:linear-gradient(90deg,#22d3ee,#4ade80);
      transition:width .2s;
    }
    .toast {
      position:fixed; bottom:20px; left:50%; transform:translateX(-50%) translateY(60px);
      background:rgba(15,23,42,.95); border:1px solid var(--border);
      color:var(--text); padding:10px 18px; border-radius:10px;
      font-size:13px; z-index:999; opacity:0; transition:all .3s;
      box-shadow:0 8px 24px rgba(0,0,0,.4);
    }
    .toast.show { opacity:1; transform:translateX(-50%) translateY(0); }
    .toast.err { border-color:var(--red); color:var(--red); }
    .toast.ok { border-color:var(--green); color:var(--green); }
  </style>
</head>
<body>
  <div class="wrap">
    <header>
      <div class="logo"><i class="fa-solid fa-server"></i></div>
      <h1>Home Server Dashboard</h1>
      <div class="sub"><span class="dot"></span>Live monitoring · Android</div>
    </header>

    <div class="tabs">
      <div class="tab active" data-tab="dash"><i class="fa-solid fa-gauge-high"></i>Dashboard</div>
      <div class="tab" data-tab="files"><i class="fa-solid fa-folder"></i>Files</div>
      <div class="tab" data-tab="term"><i class="fa-solid fa-terminal"></i>Terminal</div>
    </div>

    <!-- DASHBOARD -->
    <div class="panel active" id="panel-dash">
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
          <div class="row"><span class="lbl"><i class="fa-solid fa-gauge-high"></i> Pemakaian</span>
            <span class="big-pct" id="cpu-pct">-</span></div>
          <div class="row"><span class="lbl"><i class="fa-solid fa-bolt"></i> Frekuensi</span>
            <span class="val" id="cpu-freq">-</span></div>
          <div class="bar"><div class="fill" id="cpu-bar"></div></div>
        </div>

        <div class="card">
          <div class="card-head"><i class="ic ic-ram fa-solid fa-memory"></i><h2>RAM</h2></div>
          <div class="row"><span class="lbl"><i class="fa-solid fa-chart-pie"></i> Pemakaian</span><span class="val" id="ram-pct">-</span></div>
          <div class="row"><span class="lbl"><i class="fa-solid fa-database"></i> Terpakai</span><span class="val" id="ram-used">-</span></div>
          <div class="row"><span class="lbl"><i class="fa-solid fa-check"></i> Tersedia</span><span class="val" id="ram-avail">-</span></div>
          <div class="row"><span class="lbl"><i class="fa-solid fa-server"></i> Total</span><span class="val" id="ram-total">-</span></div>
          <div class="bar"><div class="fill" id="ram-bar"></div></div>
        </div>

        <div class="card">
          <div class="card-head"><i class="ic ic-disk fa-solid fa-hard-drive"></i><h2>Disk</h2></div>
          <div class="row"><span class="lbl"><i class="fa-solid fa-chart-pie"></i> Pemakaian</span><span class="val" id="disk-pct">-</span></div>
          <div class="row"><span class="lbl"><i class="fa-solid fa-database"></i> Terpakai</span><span class="val" id="disk-used">-</span></div>
          <div class="row"><span class="lbl"><i class="fa-solid fa-check"></i> Kosong</span><span class="val" id="disk-free">-</span></div>
          <div class="row"><span class="lbl"><i class="fa-solid fa-server"></i> Total</span><span class="val" id="disk-total">-</span></div>
          <div class="bar"><div class="fill" id="disk-bar"></div></div>
        </div>

        <div class="card full">
          <div class="card-head"><i class="ic ic-net fa-solid fa-wifi"></i><h2>Jaringan</h2>
            <span class="badge" id="iface">-</span></div>
          <div class="net-grid">
            <div class="net-box dl"><i class="fa-solid fa-arrow-down"></i>
              <div class="num" id="rx">-</div><div class="lbl">Download · Mbps</div></div>
            <div class="net-box ul"><i class="fa-solid fa-arrow-up"></i>
              <div class="num" id="tx">-</div><div class="lbl">Upload · Mbps</div></div>
          </div>
        </div>
      </div>
    </div>

    <!-- FILES -->
    <div class="panel" id="panel-files">
      <div class="card full" style="margin-bottom:14px">
        <div class="card-head">
          <i class="ic ic-file fa-solid fa-folder-open"></i>
          <h2>File Manager</h2>
          <span class="badge" id="file-count">- item</span>
        </div>
        <div class="toolbar">
          <button class="btn primary" onclick="document.getElementById('fileInput').click()">
            <i class="fa-solid fa-upload"></i> Upload
          </button>
          <button class="btn" onclick="promptNewFolder()">
            <i class="fa-solid fa-folder-plus"></i> Folder Baru
          </button>
          <button class="btn" onclick="loadFiles()">
            <i class="fa-solid fa-rotate"></i> Refresh
          </button>
        </div>
        <input type="file" id="fileInput" multiple style="display:none">
        <div class="progress" id="progress"><div class="progress-fill" id="progressFill"></div></div>
        <div class="breadcrumb" id="breadcrumb">/</div>
        <div class="file-list" id="fileList"></div>
      </div>
    </div>

    <!-- TERMINAL -->
    <div class="panel" id="panel-term">
      <div class="card full">
        <div class="card-head">
          <i class="ic ic-term fa-solid fa-terminal"></i>
          <h2>Terminal</h2>
          <span class="badge"><i class="fa-solid fa-shield-halved"></i> Full Access</span>
        </div>
        <div class="term-wrap">
          <div class="term-head">
            <span class="tdot r"></span><span class="tdot y"></span><span class="tdot g"></span>
            <span style="margin-left:8px">bash — Termux</span>
          </div>
          <div class="term-body" id="termBody"></div>
          <div class="term-input-row">
            <span class="term-prompt" id="termPrompt">$</span>
            <input type="text" class="term-input" id="termInput"
              placeholder="ketik perintah lalu Enter..."
              autocomplete="off" spellcheck="false">
            <button class="term-send" id="termSend"><i class="fa-solid fa-paper-plane"></i></button>
          </div>
        </div>
      </div>
    </div>

    <footer>
      <i class="fa-solid fa-heart"></i> Termux · Home Server
    </footer>
  </div>

  <div class="toast" id="toast"></div>

<script>
const TOKEN = "$TERM_TOKEN";

// ============ TAB ============
document.querySelectorAll('.tab').forEach(t => {
  t.onclick = () => {
    document.querySelectorAll('.tab').forEach(x => x.classList.remove('active'));
    document.querySelectorAll('.panel').forEach(x => x.classList.remove('active'));
    t.classList.add('active');
    document.getElementById('panel-' + t.dataset.tab).classList.add('active');
  };
});

// ============ TOAST ============
function toast(msg, type='ok') {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.className = 'toast show ' + type;
  clearTimeout(t._timer);
  t._timer = setTimeout(() => t.className = 'toast', 2500);
}

// ============ DASHBOARD ============
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
    let f = d.cpu.freq + ' MHz';
    if (d.cpu.freq_max > 0) f += ' / ' + d.cpu.freq_max + ' MHz';
    document.getElementById('cpu-freq').textContent = f;
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

// ============ FILES ============
let currentPath = '';
function fmtSize(b) {
  if (b < 1024) return b + ' B';
  if (b < 1024*1024) return (b/1024).toFixed(1) + ' KB';
  if (b < 1024*1024*1024) return (b/1024/1024).toFixed(1) + ' MB';
  return (b/1024/1024/1024).toFixed(2) + ' GB';
}
function iconFor(name, isDir) {
  if (isDir) return '<i class="fa-solid fa-folder folder"></i>';
  const ext = name.split('.').pop().toLowerCase();
  if (['png','jpg','jpeg','gif','webp','svg','bmp'].includes(ext)) return '<i class="fa-solid fa-image file-img"></i>';
  if (['txt','md','log','json','xml','html','css','js','py','sh'].includes(ext)) return '<i class="fa-solid fa-file-lines file-txt"></i>';
  if (['zip','tar','gz','7z','rar'].includes(ext)) return '<i class="fa-solid fa-file-zipper file-zip"></i>';
  if (['mp3','wav','ogg','m4a'].includes(ext)) return '<i class="fa-solid fa-file-audio file-default"></i>';
  if (['mp4','mkv','avi','mov'].includes(ext)) return '<i class="fa-solid fa-file-video file-default"></i>';
  return '<i class="fa-solid fa-file file-default"></i>';
}
function escapeHtml(s) {
  return s.replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}
async function loadFiles() {
  try {
    const r = await fetch('/api/files?path=' + encodeURIComponent(currentPath));
    const d = await r.json();
    if (d.error) { toast(d.error, 'err'); return; }
    document.getElementById('file-count').textContent = d.items.length + ' item';

    // Breadcrumb
    const bc = document.getElementById('breadcrumb');
    const parts = currentPath ? currentPath.split('/') : [];
    let html = '<a onclick="goDir(\'\')"><i class="fa-solid fa-house"></i> root</a>';
    let acc = '';
    parts.forEach(p => {
      acc += (acc ? '/' : '') + p;
      html += ' / <a onclick="goDir(\'' + acc + '\')">' + escapeHtml(p) + '</a>';
    });
    bc.innerHTML = html;

    // List
    const list = document.getElementById('fileList');
    if (!d.items.length) {
      list.innerHTML = '<div style="text-align:center;color:var(--muted);padding:20px;font-size:13px">Folder kosong</div>';
      return;
    }
    list.innerHTML = d.items.map(it => {
      const safe = escapeHtml(it.name).replace(/'/g, '&#39;');
      return '<div class="file-item">' +
        '<span class="fi-icon">' + iconFor(it.name, it.isDir) + '</span>' +
        '<span class="fi-name" onclick="' + (it.isDir ? 'goDir(\'' + safe + '\')' : 'downloadFile(\'' + safe + '\')') + '">' + escapeHtml(it.name) + '</span>' +
        '<span class="fi-size">' + (it.isDir ? '-' : fmtSize(it.size)) + '</span>' +
        '<span class="fi-actions">' +
          (!it.isDir ? '<button onclick="downloadFile(\'' + safe + '\')" title="Download"><i class="fa-solid fa-download"></i></button>' : '') +
          '<button onclick="renameItem(\'' + safe + '\')" title="Rename"><i class="fa-solid fa-pen"></i></button>' +
          '<button class="del" onclick="deleteItem(\'' + safe + '\')" title="Hapus"><i class="fa-solid fa-trash"></i></button>' +
        '</span></div>';
    }).join('');
  } catch(e) { toast('Gagal memuat file', 'err'); }
}
function goDir(name) {
  if (!name) { currentPath = ''; }
  else if (name.startsWith('/') || currentPath === '') { currentPath = name; }
  else { currentPath = currentPath + '/' + name; }
  loadFiles();
}
function downloadFile(name) {
  const p = currentPath ? currentPath + '/' + name : name;
  window.open('/api/download?path=' + encodeURIComponent(p), '_blank');
}
async function deleteItem(name) {
  if (!confirm('Hapus "' + name + '"?')) return;
  const p = currentPath ? currentPath + '/' + name : name;
  const r = await fetch('/api/delete', {
    method: 'POST',
    headers: {'Content-Type':'application/json'},
    body: JSON.stringify({path: p})
  });
  const d = await r.json();
  if (d.ok) { toast('Terhapus', 'ok'); loadFiles(); }
  else toast(d.error || 'Gagal hapus', 'err');
}
async function renameItem(name) {
  const nn = prompt('Nama baru:', name);
  if (!nn || nn === name) return;
  const p = currentPath ? currentPath + '/' + name : name;
  const np = currentPath ? currentPath + '/' + nn : nn;
  const r = await fetch('/api/rename', {
    method: 'POST',
    headers: {'Content-Type':'application/json'},
    body: JSON.stringify({from: p, to: np})
  });
  const d = await r.json();
  if (d.ok) { toast('Diganti nama', 'ok'); loadFiles(); }
  else toast(d.error || 'Gagal', 'err');
}
async function promptNewFolder() {
  const n = prompt('Nama folder baru:');
  if (!n) return;
  const p = currentPath ? currentPath + '/' + n : n;
  const r = await fetch('/api/mkdir', {
    method: 'POST',
    headers: {'Content-Type':'application/json'},
    body: JSON.stringify({path: p})
  });
  const d = await r.json();
  if (d.ok) { toast('Folder dibuat', 'ok'); loadFiles(); }
  else toast(d.error || 'Gagal', 'err');
}

// Upload
document.getElementById('fileInput').onchange = async (e) => {
  const files = e.target.files;
  if (!files.length) return;
  const prog = document.getElementById('progress');
  const fill = document.getElementById('progressFill');
  prog.classList.add('show');

  for (let i = 0; i < files.length; i++) {
    const fd = new FormData();
    fd.append('file', files[i]);
    fd.append('path', currentPath);
    await new Promise((resolve) => {
      const xhr = new XMLHttpRequest();
      xhr.upload.onprogress = (ev) => {
        if (ev.lengthComputable) {
          const pct = ((i + ev.loaded/ev.total) / files.length) * 100;
          fill.style.width = pct + '%';
        }
      };
      xhr.onload = () => resolve();
      xhr.onerror = () => resolve();
      xhr.open('POST', '/api/upload');
      xhr.send(fd);
    });
  }
  setTimeout(() => { prog.classList.remove('show'); fill.style.width = '0%'; }, 500);
  toast(files.length + ' file diupload', 'ok');
  loadFiles();
  e.target.value = '';
};

// ============ TERMINAL ============
const termBody = document.getElementById('termBody');
const termInput = document.getElementById('termInput');
const termSend = document.getElementById('termSend');

function termWrite(html) {
  termBody.innerHTML += html;
  termBody.scrollTop = termBody.scrollHeight;
}
termWrite('<span class="dim">Home Server Terminal — full access. Ketik </span><span class="cmd">help</span><span class="dim"> untuk bantuan.</span>\n\n');

async function runCmd(cmd) {
  if (!cmd.trim()) return;
  termWrite('<span class="cmd">$ ' + escapeHtml(cmd) + '</span>\n');
  try {
    const r = await fetch('/api/exec', {
      method: 'POST',
      headers: {'Content-Type':'application/json','X-Token': TOKEN},
      body: JSON.stringify({cmd})
    });
    const d = await r.json();
    if (d.stdout) termWrite(escapeHtml(d.stdout));
    if (d.stderr) termWrite('<span class="err">' + escapeHtml(d.stderr) + '</span>');
    if (!d.stdout && !d.stderr) termWrite('<span class="dim">(no output)</span>\n');
    termWrite('\n');
  } catch(e) {
    termWrite('<span class="err">Error: ' + e.message + '</span>\n\n');
  }
}
termSend.onclick = () => { runCmd(termInput.value); termInput.value = ''; termInput.focus(); };
termInput.onkeydown = (e) => {
  if (e.key === 'Enter') { runCmd(termInput.value); termInput.value = ''; }
  // history dengan panah atas/bawah
  if (e.key === 'ArrowUp') {
    e.preventDefault();
    if (window._cmdHist && window._cmdHist.length) {
      window._histIdx = Math.min((window._histIdx ?? window._cmdHist.length), window._cmdHist.length - 1);
      termInput.value = window._cmdHist[window._histIdx];
    }
  }
};
// simpan history
const _origRun = runCmd;
runCmd = async function(cmd) {
  if (cmd.trim()) {
    window._cmdHist = window._cmdHist || [];
    window._cmdHist.push(cmd);
    window._histIdx = window._cmdHist.length;
  }
  return _origRun(cmd);
};
termInput.onkeydown = (e) => {
  if (e.key === 'Enter') { runCmd(termInput.value); termInput.value = ''; }
  else if (e.key === 'ArrowUp') {
    e.preventDefault();
    if (window._cmdHist && window._cmdHist.length) {
      window._histIdx = Math.max(0, (window._histIdx ?? window._cmdHist.length) - 1);
      termInput.value = window._cmdHist[window._histIdx];
    }
  } else if (e.key === 'ArrowDown') {
    e.preventDefault();
    if (window._cmdHist && window._cmdHist.length) {
      window._histIdx = Math.min(window._cmdHist.length, (window._histIdx ?? 0) + 1);
      termInput.value = window._cmdHist[window._histIdx] || '';
    }
  }
};

// Load files saat pertama kali buka tab
document.querySelector('[data-tab="files"]').addEventListener('click', () => {
  if (!document.getElementById('fileList').children.length) loadFiles();
});
</script>
</body>
</html>
HTML

# ======================
# server.py — dengan API files + exec
# ======================
cat > "$SERVER_DIR/server.py" <<'PY'
#!/usr/bin/env python3
import http.server, socketserver, subprocess, os, json, shutil, cgi, io
from urllib.parse import urlparse, parse_qs, unquote

PORT = 8080
DIRECTORY = os.path.dirname(os.path.abspath(__file__))
FILES_DIR = os.path.join(DIRECTORY, "files")
TOKEN = os.environ.get("HOME_SERVER_TOKEN", "ganti-token-ini-jadi-rahasia")

os.makedirs(FILES_DIR, exist_ok=True)


def safe_path(rel):
    """Cegah path traversal. Return absolute path atau None."""
    rel = unquote(rel or "").lstrip("/")
    abs_path = os.path.realpath(os.path.join(FILES_DIR, rel))
    if not abs_path.startswith(os.path.realpath(FILES_DIR)):
        return None
    return abs_path


def json_resp(handler, data, status=200):
    body = json.dumps(data).encode()
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Cache-Control", "no-store")
    handler.end_headers()
    handler.wfile.write(body)


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def log_message(self, fmt, *args):
        pass

    # ---------- GET ----------
    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path.startswith("/info.json"):
            return self.handle_info()
        if path == "/api/files":
            return self.handle_list(parsed)
        if path == "/api/download":
            return self.handle_download(parsed)
        return super().do_GET()

    def handle_info(self):
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
            fallback = ('{"cpu":{"pct":0,"cores":0,"freq":0,"freq_max":0,"model":"Error","arch":"-"},'
                        '"ram":{"total":0,"used":0,"avail":0,"pct":0},'
                        '"disk":{"total":0,"used":0,"free":0,"pct":0},'
                        '"net":{"iface":"-","rx":0,"tx":0}}')
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(fallback.encode())

    def handle_list(self, parsed):
        qs = parse_qs(parsed.query)
        rel = qs.get("path", [""])[0]
        target = safe_path(rel)
        if not target or not os.path.isdir(target):
            return json_resp(self, {"error": "Folder tidak ditemukan"}, 404)

        items = []
        try:
            for name in sorted(os.listdir(target),
                              key=lambda n: (not os.path.isdir(os.path.join(target, n)), n.lower())):
                full = os.path.join(target, name)
                try:
                    st = os.stat(full)
                    items.append({
                        "name": name,
                        "isDir": os.path.isdir(full),
                        "size": st.st_size,
                    })
                except OSError:
                    continue
        except PermissionError:
            return json_resp(self, {"error": "Tidak punya izin"}, 403)

        json_resp(self, {"items": items, "path": rel})

    def handle_download(self, parsed):
        qs = parse_qs(parsed.query)
        rel = qs.get("path", [""])[0]
        target = safe_path(rel)
        if not target or not os.path.isfile(target):
            return json_resp(self, {"error": "File tidak ditemukan"}, 404)
        try:
            with open(target, "rb") as f:
                data = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Disposition",
                             'attachment; filename="%s"' % os.path.basename(target))
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except Exception as e:
            return json_resp(self, {"error": str(e)}, 500)

    # ---------- POST ----------
    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/api/upload":
            return self.handle_upload()
        if path == "/api/delete":
            return self.handle_json(lambda d: self.op_delete(d))
        if path == "/api/rename":
            return self.handle_json(lambda d: self.op_rename(d))
        if path == "/api/mkdir":
            return self.handle_json(lambda d: self.op_mkdir(d))
        if path == "/api/exec":
            return self.handle_exec()

        json_resp(self, {"error": "Not found"}, 404)

    def _read_json(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b"{}"
        return json.loads(raw or b"{}")

    def handle_json(self, fn):
        try:
            data = self._read_json()
        except Exception as e:
            return json_resp(self, {"error": "JSON invalid: %s" % e}, 400)
        try:
            result = fn(data)
            json_resp(self, result)
        except Exception as e:
            json_resp(self, {"error": str(e)}, 500)

    def handle_upload(self):
        ctype = self.headers.get("Content-Type", "")
        if "multipart/form-data" not in ctype:
            return json_resp(self, {"error": "Butuh multipart"}, 400)

        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)

        # Parse multipart
        boundary = ctype.split("boundary=")[1].strip().encode()
        parts = body.split(b"--" + boundary)

        target_dir_rel = ""
        saved = []

        for part in parts:
            if b"Content-Disposition" not in part:
                continue
            head, _, data = part.partition(b"\r\n\r\n")
            data = data.rstrip(b"\r\n--")
            head_str = head.decode(errors="ignore")

            # Nama field
            if 'name="path"' in head_str:
                target_dir_rel = data.decode(errors="ignore").strip()
            elif 'name="file"' in head_str:
                # Ambil filename
                fn = "upload"
                for seg in head_str.split(";"):
                    if "filename=" in seg:
                        fn = seg.split("filename=")[1].strip().strip('"')
                        break
                fn = os.path.basename(fn)  # security
                if not fn:
                    fn = "upload"

                target_dir = safe_path(target_dir_rel)
                if not target_dir or not os.path.isdir(target_dir):
                    return json_resp(self, {"error": "Folder tujuan invalid"}, 400)
                out_path = os.path.join(target_dir, fn)
                with open(out_path, "wb") as f:
                    f.write(data)
                saved.append(fn)

        json_resp(self, {"ok": True, "saved": saved})

    def op_delete(self, d):
        p = d.get("path", "")
        target = safe_path(p)
        if not target or not os.path.exists(target):
            return {"error": "Tidak ditemukan"}
        if os.path.isdir(target):
            shutil.rmtree(target)
        else:
            os.remove(target)
        return {"ok": True}

    def op_rename(self, d):
        src = safe_path(d.get("from", ""))
        dst = safe_path(d.get("to", ""))
        if not src or not dst or not os.path.exists(src):
            return {"error": "Path invalid"}
        os.rename(src, dst)
        return {"ok": True}

    def op_mkdir(self, d):
        p = d.get("path", "")
        target = safe_path(p)
        if not target:
            return {"error": "Path invalid"}
        os.makedirs(target, exist_ok=True)
        return {"ok": True}

    def handle_exec(self):
        # Cek token
        if self.headers.get("X-Token", "") != TOKEN:
            return json_resp(self, {"error": "Unauthorized"}, 401)

        try:
            data = self._read_json()
        except Exception as e:
            return json_resp(self, {"error": "JSON invalid"}, 400)

        cmd = data.get("cmd", "").strip()
        if not cmd:
            return json_resp(self, {"stdout": "", "stderr": ""})

        try:
            proc = subprocess.run(
                cmd,
                shell=True,
                cwd=os.path.expanduser("~"),
                capture_output=True,
                timeout=30,
                text=True,
                errors="replace",
            )
            return json_resp(self, {
                "stdout": proc.stdout[-20000:] if proc.stdout else "",
                "stderr": proc.stderr[-20000:] if proc.stderr else "",
                "code": proc.returncode,
            })
        except subprocess.TimeoutExpired:
            return json_resp(self, {"error": "Timeout 30 detik"})
        except Exception as e:
            return json_resp(self, {"error": str(e)})


socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
    print(f"Server berjalan di port {PORT}")
    print(f"Token terminal: {TOKEN}")
    httpd.serve_forever()
PY
chmod +x "$SERVER_DIR/server.py"

# Export token ke env supaya server pakai nilai yang sama
export HOME_SERVER_TOKEN="$TERM_TOKEN"

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
echo "Folder upload : $UPLOAD_DIR"
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
