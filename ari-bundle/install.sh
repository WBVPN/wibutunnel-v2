#!/usr/bin/env bash
# ARI BUNDLE INSTALLER — ZiVPN UDP + UDP Custom + SOCKS5 Dante
# Debian/Ubuntu, root required for installation.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD="$SCRIPT_DIR/payload"
export DEBIAN_FRONTEND=noninteractive

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()  { printf '%b\n' "${CYAN}[*]${NC} $*"; }
ok()   { printf '%b\n' "${GREEN}[+]${NC} $*"; }
warn() { printf '%b\n' "${YELLOW}[!]${NC} $*"; }
die()  { printf '%b\n' "${RED}[x]${NC} $*" >&2; exit 1; }

need_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Jalankan sebagai root: sudo bash install.sh"
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)   echo amd64 ;;
    aarch64|arm64)  echo arm64 ;;
    armv7l|armv6l|armhf) echo arm ;;
    *) return 1 ;;
  esac
}

gen_hex() {
  local bytes="$1"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "$bytes"
  else
    head -c "$bytes" /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

pkg_install() {
  apt-get update -y
  apt-get install -y --no-install-recommends "$@"
}

open_port() {
  local port="$1" proto="$2"
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi '^Status: active'; then
    ufw allow "${port}/${proto}" >/dev/null 2>&1 || true
  fi
  iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null \
    || iptables -I INPUT -p "$proto" --dport "$port" -j ACCEPT
}

save_iptables() {
  mkdir -p /etc/iptables
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1 || true
  fi
  iptables-save > /etc/iptables/rules.v4
}

default_iface() {
  ip -4 route show default 2>/dev/null \
    | awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}'
}

install_zivpn() {
  need_root
  local arch src pass exp iface
  arch="$(detect_arch)" || die "Arsitektur $(uname -m) tidak didukung untuk ZiVPN."
  src="$PAYLOAD/zivpn/udp-zivpn-linux-$arch"
  [[ -s "$src" ]] || die "Binary ZiVPN tidak ditemukan: $src"

  log "Memasang dependensi ZiVPN..."
  pkg_install curl wget ca-certificates openssl jq iptables iptables-persistent netfilter-persistent iproute2

  systemctl stop zivpn >/dev/null 2>&1 || true
  install -d -m 755 /etc/zivpn
  install -m 755 "$src" /usr/local/bin/zivpn

  pass="zivpn$(gen_hex 3)"
  exp=$(( $(date +%s) + 30 * 86400 ))

  cat > /etc/zivpn/config.json <<EOF
{
  "listen": ":553",
  "cert": "/etc/zivpn/zivpn.crt",
  "key": "/etc/zivpn/zivpn.key",
  "obfs": "zivpn",
  "auth": {
    "mode": "passwords",
    "config": ["$pass"]
  }
}
EOF

  printf '%s:%s\n' "$pass" "$exp" > /etc/zivpn/users.db
  chmod 600 /etc/zivpn/config.json /etc/zivpn/users.db

  if [[ ! -s /etc/zivpn/zivpn.crt || ! -s /etc/zivpn/zivpn.key ]]; then
    log "Membuat sertifikat self-signed..."
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
      -subj "/C=US/ST=California/L=Los Angeles/O=ZiVPN/OU=Server/CN=zivpn" \
      -keyout /etc/zivpn/zivpn.key -out /etc/zivpn/zivpn.crt >/dev/null 2>&1
    chmod 600 /etc/zivpn/zivpn.key
  fi

  cat > /etc/systemd/system/zivpn.service <<'EOF'
[Unit]
Description=ZiVPN UDP Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
LimitNOFILE=65535
Environment=ZIVPN_LOG_LEVEL=info
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

  cat > /etc/sysctl.d/99-zivpn.conf <<'EOF'
net.core.rmem_max=16777216
net.core.wmem_max=16777216
EOF
  sysctl --system >/dev/null 2>&1 || true

  iface="$(default_iface)"
  [[ -n "$iface" ]] || iface="$(ip -o link show | awk -F': ' '/eth|ens|enp/ {print $2; exit}')"
  [[ -n "$iface" ]] || die "Interface default tidak ditemukan."

  while iptables -t nat -C PREROUTING -i "$iface" -p udp --dport 6000:19999 -j DNAT --to-destination :553 2>/dev/null; do
    iptables -t nat -D PREROUTING -i "$iface" -p udp --dport 6000:19999 -j DNAT --to-destination :553
  done
  while iptables -t nat -C PREROUTING -i "$iface" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null; do
    iptables -t nat -D PREROUTING -i "$iface" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
  done
  iptables -t nat -I PREROUTING 1 -i "$iface" -p udp --dport 6000:19999 -j DNAT --to-destination :553

  open_port 553 udp
  open_port 6000:19999 udp
  save_iptables

  systemctl daemon-reload
  systemctl enable --now zivpn
  sleep 1
  systemctl --no-pager --full status zivpn | sed -n '1,12p' || true

  ok "ZiVPN aktif di UDP 553 (range publik 6000-19999)."
  printf '%b\n' "${BOLD}┌─ AKUN ZIVPN AWAL ─────────────────────────────┐${NC}"
  printf '  Password : %s\n' "$pass"
  printf '  Port     : 553 (langsung) / 6000-19999 (range)\n'
  printf '  Config   : /etc/zivpn/config.json\n'
  printf '  Masa     : 30 hari (epoch %s)\n' "$exp"
  printf '%b\n' "${BOLD}└───────────────────────────────────────────────┘${NC}"
}

install_udp_custom() {
  need_root
  local exclude="${1:-}" exec_args=""
  [[ -s "$PAYLOAD/udp/udp-custom" ]] || die "Binary UDP Custom tidak ditemukan."
  if [[ "$(uname -m)" != "x86_64" ]]; then
    warn "UDP Custom hanya tersedia untuk x86_64; arsitektur ini: $(uname -m)."
    return 1
  fi

  log "Memasang dependensi UDP Custom..."
  pkg_install curl ca-certificates iptables iptables-persistent netfilter-persistent iproute2

  systemctl stop udp-custom >/dev/null 2>&1 || true
  install -d -m 755 /etc/udp
  install -m 755 "$PAYLOAD/udp/udp-custom" /etc/udp/udp-custom
  install -m 644 "$PAYLOAD/udp/config.json" /etc/udp/config.json

  # remove broad legacy DNAT from older installs; --exclude keeps ZiVPN's 553 free
  local iface
  iface="$(default_iface)"
  while iptables -t nat -C PREROUTING -i "$iface" -p udp --dport 1:65535 -j DNAT --to-destination :36712 2>/dev/null; do
    iptables -t nat -D PREROUTING -i "$iface" -p udp --dport 1:65535 -j DNAT --to-destination :36712
  done

  [[ -n "$exclude" ]] && exec_args=" --exclude $exclude"

  cat > /etc/systemd/system/udp-custom.service <<EOF
[Unit]
Description=UDP Custom Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/udp/
ExecStart=/etc/udp/udp-custom server --config /etc/udp/config.json$exec_args
Restart=always
RestartSec=3
LimitNOFILE=65535
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

  open_port 36712 udp
  save_iptables
  systemctl daemon-reload
  systemctl enable --now udp-custom
  sleep 1
  systemctl --no-pager --full status udp-custom | sed -n '1,12p' || true
  ok "UDP Custom aktif di UDP 36712."
}

install_socks5() {
  need_root
  local s5_user s5_pass
  [[ -f "$PAYLOAD/socks5/socks5.sh" ]] || die "Script SOCKS5 tidak ditemukan."
  chmod +x "$PAYLOAD/socks5/socks5.sh" 2>/dev/null || true
  bash "$PAYLOAD/socks5/socks5.sh" --install

  s5_user="socks5$(gen_hex 3)"
  read -r s5_pass <<< "$(gen_hex 6)"
  bash "$PAYLOAD/socks5/socks5.sh" --add-user "$s5_user" "$s5_pass" 30

  if systemctl is-active --quiet danted 2>/dev/null || service danted status >/dev/null 2>&1; then
    ok "SOCKS5 Dante aktif di TCP 1080."
  else
    warn "Dante terpasang, tetapi service belum aktif. Cek: systemctl status danted"
  fi
  printf '%b\n' "${BOLD}┌─ AKUN SOCKS5 AWAL ────────────────────────────┐${NC}"
  printf '  Username : %s\n' "$s5_user"
  printf '  Password : %s\n' "$s5_pass"
  printf '  Port     : 1080 (TCP)\n'
  printf '  Masa     : 30 hari\n'
  printf '%b\n' "${BOLD}└───────────────────────────────────────────────┘${NC}"
  warn "Kelola user: bash $PAYLOAD/socks5/socks5.sh  (menu 3)"
}

install_all() {
  install_zivpn
  install_udp_custom 553 || warn "UDP Custom dilewati (arsitektur tidak didukung atau instalasi gagal)."
  install_socks5
}

status_all() {
  local svc
  for svc in zivpn udp-custom danted; do
    if systemctl list-unit-files "$svc.service" >/dev/null 2>&1; then
      printf '%-12s : %s\n' "$svc" "$(systemctl is-active "$svc" 2>/dev/null || true)"
    fi
  done
  echo
  ss -lunp 2>/dev/null | grep -E ':(553|36712)\b' || true
  ss -ltnp 2>/dev/null | grep -E ':1080\b' || true
}

show_zivpn_creds() {
  [[ -f /etc/zivpn/config.json ]] || die "ZiVPN belum terpasang."
  echo "Password aktif:"
  jq -r '.auth.config[]?' /etc/zivpn/config.json
  echo
  echo "users.db:"
  cat /etc/zivpn/users.db 2>/dev/null || true
}

check_bundle() {
  local f missing=0 arch
  arch="$(detect_arch 2>/dev/null || echo unsupported)"
  echo "Bundle : $SCRIPT_DIR"
  echo "Arch   : $(uname -m) -> $arch"
  echo
  for f in \
    payload/zivpn/udp-zivpn-linux-amd64 \
    payload/zivpn/udp-zivpn-linux-arm64 \
    payload/zivpn/udp-zivpn-linux-arm \
    payload/udp/udp-custom \
    payload/udp/config.json \
    payload/socks5/socks5.sh; do
    if [[ -s "$SCRIPT_DIR/$f" ]]; then
      printf '  OK   %s\n' "$f"
    else
      printf '  MISS %s\n' "$f"; missing=1
    fi
  done
  echo
  bash -n "$SCRIPT_DIR/install.sh" && echo "  OK   install.sh syntax"
  bash -n "$SCRIPT_DIR/payload/socks5/socks5.sh" && echo "  OK   socks5.sh syntax"
  if command -v jq >/dev/null 2>&1; then
    jq empty "$SCRIPT_DIR/payload/udp/config.json" && echo "  OK   udp config json"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -m json.tool "$SCRIPT_DIR/payload/udp/config.json" >/dev/null && echo "  OK   udp config json"
  fi
  if [[ -f "$SCRIPT_DIR/SHA256SUMS.txt" ]]; then
    (cd "$SCRIPT_DIR" && sha256sum -c SHA256SUMS.txt) || missing=1
  fi
  return "$missing"
}

pause() { read -r -p "Tekan Enter untuk kembali..." _ || true; }

menu() {
  local choice exclude
  while true; do
    clear 2>/dev/null || true
    cat <<'EOF'
╔══════════════════════════════════════════════════╗
║        ARI BUNDLE INSTALLER — UDP + SOCKS5       ║
╠══════════════════════════════════════════════════╣
║  1) Install ZiVPN UDP      (553 / 6000-19999)    ║
║  2) Install UDP Custom     (36712)               ║
║  3) Install SOCKS5 Dante   (1080)                ║
║  4) Install semua (ZiVPN + UDP + SOCKS5)         ║
║  5) Status layanan                               ║
║  6) Lihat kredensial ZiVPN                       ║
║  7) Cek isi bundle                               ║
║  0) Keluar                                       ║
╚══════════════════════════════════════════════════╝
EOF
    read -r -p "Pilih: " choice || exit 0
    case "$choice" in
      1) install_zivpn; pause ;;
      2)
        read -r -p "Exclude port UDP Custom (contoh 443, kosongkan jika tidak): " exclude || true
        install_udp_custom "$exclude"; pause ;;
      3) install_socks5; pause ;;
      4) install_all; pause ;;
      5) status_all; pause ;;
      6) show_zivpn_creds; pause ;;
      7) check_bundle; pause ;;
      0) exit 0 ;;
      *) ;;
    esac
  done
}

case "${1:-}" in
  --check) check_bundle ;;
  --install-zivpn) install_zivpn ;;
  --install-udp) install_udp_custom "${2:-}" ;;
  --install-socks5) install_socks5 ;;
  --install-all) install_all ;;
  --status) status_all ;;
  -h|--help)
    cat <<EOF
Usage: sudo bash install.sh [opsi]
  --install-zivpn     Install ZiVPN UDP saja
  --install-udp [p]   Install UDP Custom (opsional exclude port p)
  --install-socks5    Install SOCKS5 Dante saja
  --install-all       Install ketiganya
  --status            Cek status layanan
  --check             Validasi isi bundle (tanpa install)
EOF
    ;;
  "") menu ;;
  *) die "Opsi tidak dikenal: $1 (pakai --help)" ;;
esac
