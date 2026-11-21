# ARI BUNDLE INSTALLER — ZiVPN UDP + UDP Custom + SOCKS5

Paket installer offline untuk tiga layanan:

- **ZiVPN UDP** — UDP tunneling (binary ZiVPN v1.5.0)
- **UDP Custom** — UDP custom server (binary v1.4, x86_64)
- **SOCKS5 Dante** — SOCKS5 server di port 1080 (Debian/Ubuntu)

Semua binary dan script sudah ada di dalam ZIP. Installer tidak perlu mengunduh payload dari internet; koneksi internet hanya dipakai untuk `apt-get` dependensi.

## Isi Paket

```
install.sh                     menu installer
README.md                      file ini
SHA256SUMS.txt                 checksum payload
payload/zivpn/                 binary ZiVPN (amd64, arm64, arm) + config contoh
payload/udp/                   binary UDP Custom + config
payload/socks5/socks5.sh       installer & manager SOCKS5 Dante
```

## Syarat

- Ubuntu 20.04/22.04/24.04 atau Debian 11/12
- root / `sudo`
- arsitektur:
  - ZiVPN: x86_64, arm64, armv7
  - UDP Custom: **x86_64 saja**
  - SOCKS5: semua arsitektur Debian/Ubuntu
- port yang dipakai:
  - `553/udp` — ZiVPN langsung
  - `6000-19999/udp` — range ZiVPN (DNAT ke 553)
  - `36712/udp` — UDP Custom
  - `1080/tcp` — SOCKS5 Dante

## Cara Pakai

```bash
unzip ARI-BUNDLE-INSTALLER.zip
cd ARI-BUNDLE-INSTALLER
sudo bash install.sh
```

Menu:

1. Install ZiVPN UDP
2. Install UDP Custom
3. Install SOCKS5 Dante
4. Install ketiganya
5. Cek status layanan
6. Lihat kredensial ZiVPN
7. Cek isi bundle

Atau jalankan langsung tanpa menu:

```bash
sudo bash install.sh --install-zivpn
sudo bash install.sh --install-udp
sudo bash install.sh --install-udp 443       # exclude port 443 dari aturan UDP Custom
sudo bash install.sh --install-socks5
sudo bash install.sh --install-all
sudo bash install.sh --status
bash install.sh --check                       # validasi file, tanpa install
```

## ZiVPN

Installer membuat password acak dan menampilkannya di akhir proses. Data tersimpan di:

- `/etc/zivpn/config.json`
- `/etc/zivpn/users.db`
- `/etc/zivpn/zivpn.crt` dan `/etc/zivpn/zivpn.key`
- service: `/etc/systemd/system/zivpn.service`

Cek kredensial:

```bash
sudo bash install.sh --status
sudo jq -r '.auth.config[]' /etc/zivpn/config.json
```

Tambah password baru:

```bash
sudo jq '.auth.config += ["passwordbaru"]' /etc/zivpn/config.json > /tmp/zivpn.json
sudo mv /tmp/zivpn.json /etc/zivpn/config.json
sudo systemctl restart zivpn
```

Range `6000-19999/udp` diarahkan ke port `553` lewat iptables NAT. Kalau VPS punya firewall eksternal, buka juga range tersebut di panel provider.

`--install-all` otomatis memakai `--exclude 553` untuk UDP Custom supaya port ZiVPN tidak direbut aturan DNAT UDP Custom.

## UDP Custom

Config ada di `/etc/udp/config.json`, listen `:36712`. Service:

```bash
systemctl status udp-custom
journalctl -u udp-custom -n 50 --no-pager
```

Kalau mau exclude port dari aturan iptables internal UDP Custom:

```bash
sudo bash install.sh --install-udp 443
```

## SOCKS5 Dante

Installer memanggil `payload/socks5/socks5.sh --install`, lalu membuat satu akun SOCKS5 awal secara otomatis dan menampilkan username/password-nya di akhir proses.

Untuk menambah, renew, atau menghapus user:

```bash
sudo bash payload/socks5/socks5.sh
```

Pilih menu **3) Manage Users**. User disimpan di `/etc/socks5/users.db`, autentikasi Dante memakai system user + `chpasswd`.

Tambah user langsung tanpa menu:

```bash
sudo bash payload/socks5/socks5.sh --add-user namauser passwordkuat 30
```

Angka terakhir adalah masa aktif dalam hari (`0` = lifetime).

## Jika Port Diblokir Provider

Sebagian VPS hanya membuka `443/tcp` dan `80/tcp`. Kalau `ss -ltnp` menunjukkan `1080` listen tetapi koneksi dari luar timeout, firewall provider kemungkinan memblokir port itu. Solusi: mux SOCKS5 di port 443 memakai `nginx stream` + `ssl_preread`.

```nginx
# /etc/nginx/stream.d/socks-mux.conf
stream {
    map $ssl_preread_protocol $socks_mux_backend {
        default 127.0.0.1:8443;   # TLS/HTTPS
        ""      127.0.0.1:1080;   # SOCKS5 polos
    }

    server {
        listen 443;
        listen [::]:443;
        proxy_pass $socks_mux_backend;
        ssl_preread on;
        proxy_connect_timeout 5s;
        proxy_timeout 1h;
    }
}
```

Pindahkan blok HTTPS yang sudah ada dari `listen 443 ssl` ke `listen 127.0.0.1:8443 ssl`, lalu:

```bash
sudo nginx -t && sudo systemctl reload nginx
curl --socks5-hostname USER:PASS@IP_VPS:443 https://api.ipify.org
```

Port `1080` tetap bisa dipakai dari dalam VPS. Untuk UDP, buka `553/udp`, `6000:19999/udp`, dan `36712/udp` di panel provider — bukan cuma di `ufw`.

## Verifikasi

```bash
sha256sum -c SHA256SUMS.txt
```

## Sumber Payload

- ZiVPN: https://github.com/arivpnstores/udp-zivpn
- UDP Custom: https://github.com/arivpnstores/udp-custom
- SOCKS5 script: https://github.com/arivpnstores/installer

Bundle ini **tidak** menyertakan panel/manager berlisensi Ari. Yang dipasang adalah service ZiVPN, UDP Custom, dan SOCKS5 beserta konfigurasi dasarnya.
