#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
r=/opt/beta3/public-root
raw=/opt/beta3/public.raw
mkdir -p "$r" public/payload
simg2img base/rootfs.img "$raw"
mount -o loop "$raw" "$r"
trap 'umount "$r"' EXIT
test -f "$r/usr/lib/lshz-3399/status-display-beta3"
test -z "$(btrfs subvolume list "$r")"
rm -f "$r"/etc/ssh/ssh_host_* "$r/root/.bash_history" "$r/root/.psql_history" "$r/root/.viminfo" "$r/var/lib/systemd/random-seed"
rm -f "$r/etc/ssl/private/ssl-cert-snakeoil.key" "$r/etc/ssl/certs/ssl-cert-snakeoil.pem"
sed -i 's/^root:[^:]*:/root:!:/' "$r/etc/shadow" "$r/etc/shadow-"
: > "$r/etc/machine-id"
install -d "$r/etc/systemd/system/ssh.service.d"
cat > "$r/etc/systemd/system/lshz-generate-local-cert.service" <<'EOF'
[Unit]
Description=Generate the device-local TLS certificate
ConditionPathExists=!/etc/ssl/private/ssl-cert-snakeoil.key
Before=postgresql.service trim_nginx.service

[Service]
Type=oneshot
ExecStart=/usr/sbin/make-ssl-cert generate-default-snakeoil --force-overwrite

[Install]
WantedBy=multi-user.target
EOF
ln -s ../lshz-generate-local-cert.service "$r/etc/systemd/system/multi-user.target.wants/lshz-generate-local-cert.service"
cat > "$r/etc/systemd/system/ssh.service.d/10-generate-host-keys.conf" <<'EOF'
[Service]
ExecStartPre=/usr/bin/ssh-keygen -A
EOF
install -d "$r/etc/ssh/sshd_config.d"
printf 'PermitRootLogin no\n' > "$r/etc/ssh/sshd_config.d/00-lshz-public.conf"
grep -Ei '^Include.*sshd_config.d' "$r/etc/ssh/sshd_config"
for dir in "$r/etc" "$r/root" "$r/home" "$r/var/lib"; do
    find "$dir" -xdev -type f -name authorized_keys -delete
done
test ! -e "$r/etc/ssh/ssh_host_ed25519_key"
test -z "$(awk -F: '$2 !~ /^[!*]/ && $2 != "" {print $1}' "$r/etc/shadow")"
sync
fstrim -v "$r"
umount "$r"
trap - EXIT
btrfs check --readonly "$raw"
img2simg "$raw" public/payload/rootfs.img 4096
simg2img public/payload/rootfs.img /opt/beta3/public-roundtrip.raw
cmp "$raw" /opt/beta3/public-roundtrip.raw
for file in package-file parameter.txt uboot.img trust.img boot.img; do
    cp "base/$file" public/payload/
done
