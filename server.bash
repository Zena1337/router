
#!/data/data/com.termux/files/usr/bin/bash

set -e

PORT=8080
SERVER_DIR="$HOME/home-server"

echo "================================"
echo "     ANDROID HOME SERVER"
echo "================================"

# Update dan instal kebutuhan
pkg update -y
pkg install -y python openssh iproute2

# Membuat folder server
mkdir -p "$SERVER_DIR"

# Membuat halaman web
cat > "$SERVER_DIR/index.html" <<'HTML'
<!DOCTYPE html>
<html lang="id">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Home Server</title>
  <style>
    body {
      font-family: sans-serif;
      background: #101827;
      color: white;
      text-align: center;
      padding: 50px 15px;
    }
    .card {
      max-width: 400px;
      margin: auto;
      padding: 25px;
      border-radius: 16px;
      background: #1e293b;
    }
    h1 { color: #4ade80; }
    p { color: #cbd5e1; }
  </style>
</head>
<body>
  <div class="card">
    <h1>Home Server Aktif!</h1>
    <p>Server berjalan dari HP Android bekas.</p>
    <p>Terhubung melalui Wi-Fi lokal.</p>
  </div>
</body>
</html>
HTML

# Mencari IP lokal Wi-Fi
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
exec python -m http.server "$PORT" --bind 0.0.0.0
