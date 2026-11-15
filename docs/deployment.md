# Deployment – Echtbetrieb von Null aufsetzen

Schritt-für-Schritt-Anleitung für den Echtbetrieb. Rollen: **VIBEZ** (Tobias) schließt die Verträge ab und besitzt die
Konten, **Murat** richtet ein. Zeitaufwand: etwa ein halber Tag, dazu Wartezeiten für DNS.

Vor dem ersten echten Datensatz müssen die Punkte aus der [Freigabe-Checkliste](#8-abnahme-und-freigabe) erledigt sein.

## Inhalt

1. [Verträge und Konten (VIBEZ)](#1-verträge-und-konten-vibez)
2. [Server bestellen und härten](#2-server-bestellen-und-härten)
3. [MongoDB Atlas](#3-mongodb-atlas)
4. [Cloudflare: Hilfszone, Tunnel, Custom Hostname](#4-cloudflare-hilfszone-tunnel-custom-hostname)
5. [Stack ausrollen](#5-stack-ausrollen)
6. [Backup einrichten](#6-backup-einrichten)
7. [Überwachung](#7-überwachung)
8. [Abnahme und Freigabe](#8-abnahme-und-freigabe)

## 1. Verträge und Konten (VIBEZ)

| Konto | Inhaber | Vertrag / AV | Zugang Murat |
|---|---|---|---|
| Hetzner (Cloud + Storage Box) | VIBEZ | AV-Vertrag im Hetzner-Konto abschließen | Projektmitglied, 2FA |
| MongoDB Atlas | VIBEZ (Organisation „VIBEZ“) | DPA aus den Atlas-Bedingungen dokumentieren | Projektmitglied „Project Owner“, 2FA |
| Cloudflare | VIBEZ | DPA aus den Self-Serve-Bedingungen dokumentieren | Mitglied „Administrator“, 2FA |
| All-Inkl (Domain, DNS) | VIBEZ (bestehend) | – (keine Klientendaten) | nur DNS-Einträge, auf Zuruf |
| Tailscale | Murat | – (nur Verwaltungszugang, keine Inhalte) | – |
| GitHub `mbay-ODW` | Murat | – (Code und Image, keine Klientendaten) | – |
| Passwortmanager | VIBEZ | – | Einträge: restic-Passwort, Server-Konsolenpasswort, Atlas-Benutzer |

Außerdem: **AV-Vertrag VIBEZ ↔ Murat** (IT-Betreuung) inkl. Verpflichtung nach § 203 Abs. 4 StGB. Siehe
[Dienstleister](../datenschutz/dienstleister.md).

## 2. Server bestellen und härten

1. Hetzner Cloud → neues Projekt „VIBEZ Nachweise“ → Server:
   - Standort **Nürnberg** oder **Falkenstein** (Deutschland)
   - Image **Debian 13**
   - Typ: 2 vCPU, 4 GB RAM reichen (Shared vCPU, x86)
   - IPv4 **an** (feste IP für die Atlas-Zugriffsliste), IPv6 an
   - SSH-Schlüssel von Murat hinterlegen
   - Name `vibez-prod`
   - Backups (Hetzner-Snapshots) **an**: sichert den Server, nicht die Daten (die liegen in Atlas)
2. **Hetzner Cloud Firewall** „vibez-prod“:
   - eingehend nur `22/tcp` von Murats aktueller IP (nur für die Einrichtung)
   - **nach Schritt 2.4 die Regel löschen**, sodass eingehend nichts erlaubt ist
3. Einrichten (als root, einmalig):

   ```bash
   scp host/bootstrap.sh root@<server-ip>:/root/
   ssh root@<server-ip> 'ADMIN=murat ADMIN_KEY="ssh-ed25519 AAAA… murat" TS_AUTHKEY=tskey-auth-… bash /root/bootstrap.sh'
   ```

   Das Skript aktualisiert das System, aktiviert automatische Sicherheitsupdates, legt das Admin-Konto an (nur
   Schlüssel), sperrt root- und Passwort-Login, installiert Docker und Tailscale und aktiviert die Host-Firewall, sobald
   Tailscale verbunden ist.
4. Prüfen: `ssh murat@vibez-prod` (über Tailscale) funktioniert. **Dann** die Firewall-Regel aus 2.2 löschen und testen,
   dass `ssh murat@<öffentliche-ip>` scheitert.
5. Ein **Konsolenpasswort** für `murat` setzen (`sudo passwd murat`) und im Passwortmanager von VIBEZ ablegen. Es wird nur
   für die Hetzner-Webkonsole im Notfall gebraucht, SSH nimmt weiterhin keine Passwörter an.

## 3. MongoDB Atlas

1. Organisation „VIBEZ“, Projekt **„VIBEZ Nachweise“**, Murat als Projektmitglied einladen, 2FA erzwingen.
2. Cluster anlegen: **AWS, eu-central-1 (Frankfurt)**, dedizierter Tarif (M10) oder Flex (siehe
   [Architektur](architektur.md#atlas-einrichtung-wie-drk)), Name `vibez`.
3. **Backup** aktivieren (Cloud Backup), Aufbewahrung wie in der Architektur.
4. **Database Access**:
   - `vibez_app`: Passwort generieren, Rolle *readWrite* nur auf Datenbank `vibez`
   - `vibez_backup`: Passwort generieren, Rolle *backup*
5. **Network Access**: einen Programmatic API Key für das Projekt mit der Rolle *Project IP Access List Admin*
   anlegen, dann auf dem Server ausführen:

   ```bash
   sudo ATLAS_PUBLIC_KEY=… ATLAS_PRIVATE_KEY=… ATLAS_GROUP_ID=… /opt/vibez/host/atlas-zugriffsliste.sh setzen
   ```

   Damit steht genau die IPv4 des Servers in der Liste. **Nie** `0.0.0.0/0` eintragen. Den API-Key danach nicht auf dem
   Server speichern.
6. Atlas-Alerts an Murat: Verbindung, Speicher, fehlgeschlagenes Backup.

## 4. Cloudflare: Hilfszone, Tunnel, Custom Hostname

Komplett in [cloudflare.md](cloudflare.md):

1. Hilfsdomain registrieren und Zone bei Cloudflare aktivieren
2. Tunnel `vibez-prod` anlegen, `origin.vibez-edge.de` routen
3. Cloudflare for SaaS aktivieren, Fallback-Origin setzen, Custom Hostname `nachweise.vibez-jugendhilfe.de` anlegen
4. Zwei TXT-Einträge bei All-Inkl, danach den CNAME `nachweise`
5. Zone-Einstellungen, 5 WAF-Regeln, Ratenlimit, Cache-Regel

## 5. Stack ausrollen

```bash
ssh murat@vibez-prod
sudo git clone https://github.com/mbay-ODW/vibez-betrieb /opt/vibez
cd /opt/vibez/stack
sudo cp .env.example .env && sudo chmod 600 .env && sudo nano .env      # alle Werte setzen
sudo nano cloudflared/config.yml                                          # TUNNEL_ID eintragen
sudo install -m 600 /tmp/credentials.json cloudflared/credentials.json    # aus Schritt 4
sudo install -d -m 755 logs/traefik
# Zugriff auf das private Container-Image (GitHub-Token nur mit read:packages):
echo "$GHCR_TOKEN" | sudo docker login ghcr.io -u mbay-ODW --password-stdin
sudo ./deploy.sh
```

- `VN_ADMIN_PASSWORD` ist das Startpasswort für `tobias`. Es wirkt nur beim allerersten Start.
- `VN_DEMO=0` ist im Compose fest gesetzt. Es werden **keine Demodaten** erzeugt.
- Logrotate für das Traefik-Protokoll:
  `sudo install -m 644 /opt/vibez/host/logrotate-vibez /etc/logrotate.d/vibez`

## 6. Backup einrichten

1. Hetzner **Storage Box** bestellen, Standort möglichst ein anderes Rechenzentrum als der Server. In der
   Storage-Box-Verwaltung SSH-Zugang aktivieren.
2. SSH-Schlüssel für root auf dem Server erzeugen und hinterlegen:

   ```bash
   sudo ssh-keygen -t ed25519 -N "" -f /root/.ssh/storagebox
   sudo cat /root/.ssh/storagebox.pub | ssh -p 23 u000000@u000000.your-storagebox.de install-ssh-key
   printf 'Host u000000.your-storagebox.de\n  Port 23\n  IdentityFile /root/.ssh/storagebox\n' | sudo tee -a /root/.ssh/config
   sudo ssh u000000@u000000.your-storagebox.de exit   # Host-Schlüssel bestätigen (known_hosts)
   ```

3. In `.env` setzen: `RESTIC_REPOSITORY`, ein starkes `RESTIC_PASSWORD` (**sofort zusätzlich in den Passwortmanager
   von VIBEZ**), `BACKUP_PING_URL`.
4. Repository anlegen und ersten Lauf starten:

   ```bash
   sudo bash -c 'set -a; . /opt/vibez/stack/.env; docker run --rm -e RESTIC_REPOSITORY -e RESTIC_PASSWORD -v /root/.ssh:/root/.ssh:ro restic/restic:$RESTIC_VERSION init'
   sudo /opt/vibez/host/backup.sh && sudo /opt/vibez/host/restore.sh latest --test
   ```

5. Timer aktivieren:

   ```bash
   sudo cp /opt/vibez/host/systemd/vibez-* /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now vibez-backup.timer vibez-restoretest.timer
   ```

## 7. Überwachung

In Uptime Kuma (bestehend):

- HTTP-Monitor `https://nachweise.vibez-jugendhilfe.de/health`, Intervall 60 s, Schlüsselwort `"ok": true`,
  Zertifikatsablauf-Warnung an
- Push-Monitor „VIBEZ Backup“, Heartbeat-Intervall 26 Stunden → URL als `BACKUP_PING_URL` in `.env`
- Benachrichtigung per ntfy an Murat

## 8. Abnahme und Freigabe

Technik (Murat):

- [ ] `https://nachweise.vibez-jugendhilfe.de` zeigt die Anmeldung, Zertifikat gültig
- [ ] Aufruf aus einem Nicht-EU-Land (VPN) wird blockiert, `/.env` wird blockiert
- [ ] `nmap` auf die öffentliche IP: keine offenen Ports
- [ ] Atlas-Zugriffsliste enthält nur die Server-IP; Verbindung von einem anderen Rechner scheitert
- [ ] Antwort-Header enthalten `Content-Security-Policy`, `Strict-Transport-Security`, `Cache-Control: no-store`
- [ ] Backup gelaufen, Restore-Test erfolgreich, Uptime-Kuma-Monitore grün
- [ ] Atlas Cloud Backup: erster Snapshot vorhanden
- [ ] restic-Passwort und Konsolenpasswort liegen im Passwortmanager von VIBEZ (Gegencheck durch Tobias)
- [ ] Der Server ist **nicht** in Portainer, MCP-Servern oder sonstigen KI-/Automationswerkzeugen eingebunden

Organisation (VIBEZ):

- [ ] Datenschutz-Folgenabschätzung von Geschäftsführung und Datenschutzbeauftragter/m unterschrieben ([dsfa.md](../datenschutz/dsfa.md))
- [ ] Alle AV-Verträge abgeschlossen bzw. dokumentiert ([dienstleister.md](../datenschutz/dienstleister.md))
- [ ] Verzeichnis der Verarbeitungstätigkeiten ergänzt ([vvt.md](../datenschutz/vvt.md))
- [ ] Informationsblatt für Familien und Mitarbeitende ausgegeben ([informationen.md](../datenschutz/informationen.md))
- [ ] Mitarbeitende eingewiesen (Handy-Sperre, Abmelden, Verlust melden)
- [ ] Vor-Go-live-Maßnahmen der DSFA umgesetzt (z. B. Zwei-Faktor-Anmeldung, Löschkonzept)
