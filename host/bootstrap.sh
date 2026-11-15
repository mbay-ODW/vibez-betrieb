#!/usr/bin/env bash
# Grundeinrichtung eines frischen Hetzner-Cloud-Servers (Debian 13) für VIBEZ Nachweise.
# Einmal als root ausführen:  ADMIN=murat ADMIN_KEY="ssh-ed25519 AAAA… murat" bash bootstrap.sh
# Danach ist SSH nur noch per Schlüssel und – nach `tailscale up` – nur noch über Tailscale erreichbar.
set -euo pipefail
: "${ADMIN:?ADMIN=<benutzername> setzen}"
: "${ADMIN_KEY:?ADMIN_KEY=<öffentlicher SSH-Schlüssel> setzen}"

export DEBIAN_FRONTEND=noninteractive
timedatectl set-timezone Europe/Berlin
apt-get update && apt-get -y full-upgrade
apt-get install -y --no-install-recommends ca-certificates curl gnupg ufw unattended-upgrades apt-listchanges \
  needrestart logrotate git jq

# Automatische Sicherheitsupdates inkl. nächtlichem Neustart, falls nötig
cat > /etc/apt/apt.conf.d/52vibez-unattended <<'CONF'
Unattended-Upgrade::Origins-Pattern { "origin=Debian,codename=${distro_codename},label=Debian-Security"; "origin=Debian,codename=${distro_codename}-security,label=Debian-Security"; };
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:15";
CONF
systemctl enable --now unattended-upgrades

# Administrator mit Schlüssel, root-Login und Passwort-Login aus
id "$ADMIN" >/dev/null 2>&1 || adduser --disabled-password --gecos "" "$ADMIN"
usermod -aG sudo "$ADMIN"
install -d -m 700 -o "$ADMIN" -g "$ADMIN" "/home/$ADMIN/.ssh"
echo "$ADMIN_KEY" > "/home/$ADMIN/.ssh/authorized_keys"
chown "$ADMIN:$ADMIN" "/home/$ADMIN/.ssh/authorized_keys"; chmod 600 "/home/$ADMIN/.ssh/authorized_keys"
cat > /etc/ssh/sshd_config.d/10-vibez.conf <<'CONF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
X11Forwarding no
AllowTcpForwarding no
MaxAuthTries 3
CONF
systemctl reload ssh

# Docker aus dem offiziellen Repository
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin
cat > /etc/docker/daemon.json <<'CONF'
{ "log-driver": "json-file", "log-opts": { "max-size": "10m", "max-file": "5" }, "live-restore": true, "no-new-privileges": true }
CONF
systemctl restart docker

# Tailscale (Verwaltungszugang). Mit TS_AUTHKEY (einmaliger Schlüssel aus der Tailscale-Verwaltung) automatisch.
curl -fsSL https://tailscale.com/install.sh | sh
if [[ -n "${TS_AUTHKEY:-}" ]]; then
  tailscale up --authkey "$TS_AUTHKEY" --hostname vibez-prod
fi

# Host-Firewall: eingehend nur SSH über Tailscale. Erst scharf schalten, wenn Tailscale verbunden ist –
# sonst sperrt man sich aus. (Die Hetzner-Cloud-Firewall blockt zusätzlich alles von außen.)
ufw default deny incoming
ufw default allow outgoing
ufw allow in on tailscale0 to any port 22 proto tcp
if tailscale status >/dev/null 2>&1; then
  ufw --force enable
  echo "Firewall aktiv: SSH nur noch über Tailscale ($(tailscale ip -4 | head -1))."
else
  echo "ACHTUNG: Tailscale nicht verbunden – Firewall NICHT aktiviert. Erst 'tailscale up', dann 'ufw --force enable'."
fi

# Verzeichnisse
install -d -m 700 /srv/vibez /srv/vibez/restic-cache
install -d -m 755 /opt/vibez
echo "Fertig. Weiter mit docs/deployment.md, Schritt „Tailscale verbinden“."
