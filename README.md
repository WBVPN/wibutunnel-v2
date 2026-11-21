# WIBUTUNNEL — Installer Mandiri

Repo ini adalah paket **rebrand ARI V7** menjadi WIBUTUNNEL. Tidak ada lisensi online, tidak ada pendaftaran, dan tidak ada koneksi ke server ARI.

## Install

Di VPS baru (Ubuntu 22.04/24.04 atau Debian 12), sebagai root:

```bash
apt update && apt install -y curl
curl -fL -o /root/wibutunnel-install.sh https://raw.githubusercontent.com/WBVPN/wibutunnel-v2/main/install.sh
chmod +x /root/wibutunnel-install.sh
bash /root/wibutunnel-install.sh
```

Atau download dari halaman **Releases** lalu:

```bash
chmod +x wibutunnel-install.sh
bash wibutunnel-install.sh
```

Setelah selesai:

```bash
menu
```

## Isi

- `install.sh` — installer satu file (21 MB), payload sudah tertanam di dalamnya.
- `SHA256SUMS` — checksum installer.
- `ari-bundle/` — bundle tambahan ZiVPN UDP + UDP Custom + SOCKS5 (lihat di bawah).

## Bundle tambahan — ZiVPN UDP + UDP Custom + SOCKS5

Folder `ari-bundle/` berisi installer offline untuk tiga layanan tambahan:

- ZiVPN UDP (amd64/arm64/arm)
- UDP Custom (x86_64)
- SOCKS5 Dante + manager user

Jalankan dari dalam folder bundle, bukan lewat `curl` satu file, karena payload-nya ada di `ari-bundle/payload/`:

```bash
git clone https://github.com/WBVPN/wibutunnel-v2.git
cd wibutunnel-v2/ari-bundle
sudo bash install.sh
```

Atau langsung pasang ketiganya:

```bash
sudo bash install.sh --install-all
```

Dokumentasi lengkap ada di `ari-bundle/README.md`.

## Perubahan dari ARI V7

- Brand ARI TUNNELING / Arivpnstore / @ARI_VPN_STORE → WIBUTUNNEL.
- Lisensi online diganti file lokal `/usr/local/share/wibutunnel/izin` (aktif sampai 2099-12-31), plus fallback `/usr/bin/e` agar menu tidak terkunci.
- Unduhan `rajaserver.web.id` (udp-custom, update, menu, plugin) diganti payload lokal.
- Kontak WhatsApp ARI dihapus.
- Sinkronisasi akun panel → config Xray: `xray-sync.service`, `xray-sync.path`, `xray-sync.timer`.
- Path Shadowsocks diseragamkan ke `/etc/shadowsocks/.shadowsocks.db`.
- Format DB `### user exp uuid quota iplimit` didukung, termasuk pencabutan client saat expired.

## Checksum

Lihat `SHA256SUMS`.

## Catatan

Installer tetap butuh internet untuk paket sistem (apt, Xray, Nginx, Node/npm). Yang diputus dari internet hanyalah lisensi dan aset ARI.
