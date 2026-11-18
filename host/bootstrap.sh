#!/usr/bin/env bash
# Grundeinrichtung eines frischen netcup-VPS (Debian 13) für VIBEZ Nachweise.
# Einmal als root ausführen:  ADMIN=murat ADMIN_KEY="ssh-ed25519 AAAA… murat" [SSH_PORT=5022] bash bootstrap.sh
# Danach ist SSH nur noch per Schlüssel auf SSH_PORT erreichbar (Entscheidung 18.11.2026: kein Tailscale).
# Vorher eine zweite SSH-Sitzung offen halten und den neuen Port testen, sonst bleibt nur die netcup-Konsole.
set -euo pipefail
: "${ADMIN:?ADMIN=<benutzername> setzen}"
: "${ADMIN_KEY:?ADMIN_KEY=<öffentlicher SSH-Schlüssel> setzen}"
SSH_PORT="${SSH_PORT:-5022}"

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

# SSH auf eigenem Port (weniger Rauschen durch Scanner; Schutz kommt von Schlüssel-Login und Ratenbegrenzung)
echo "Port $SSH_PORT" > /etc/ssh/sshd_config.d/20-vibez-port.conf
systemctl reload ssh

# Host-Firewall: eingehend nur SSH (mit Ratenbegrenzung). Die App ist nur über den Cloudflare-Tunnel erreichbar,
# 80/443 bleiben zu.
ufw default deny incoming
ufw default allow outgoing
ufw limit "$SSH_PORT"/tcp
ufw --force enable
echo "Firewall aktiv: eingehend nur SSH auf Port $SSH_PORT."

# Verzeichnisse
install -d -m 700 /srv/vibez /srv/vibez/restic-cache
install -d -m 755 /opt/vibez
echo "Fertig. Neuen Port testen: ssh -p $SSH_PORT $ADMIN@<server>. Weiter mit docs/deployment.md."
