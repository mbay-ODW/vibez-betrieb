# Deployment – Echtbetrieb von Null aufsetzen

Schritt-für-Schritt-Anleitung für den Echtbetrieb. Rollen: **VIBEZ** (Tobias) schließt die Verträge ab und besitzt die
Konten, **Murat** richtet ein. Zeitaufwand: etwa ein halber Tag, dazu Wartezeiten für DNS.

Vor dem ersten echten Datensatz müssen die Punkte aus der [Freigabe-Checkliste](#8-abnahme-und-freigabe) erledigt sein.

## Inhalt

1. [Verträge und Konten (VIBEZ)](#1-verträge-und-konten-vibez)
2. [Server bestellen und härten](#2-server-bestellen-und-härten)
3. [MongoDB Atlas](#3-mongodb-atlas)
4. [Cloudflare: Domain, Tunnel, Regeln](#4-cloudflare-domain-tunnel-regeln)
5. [Stack ausrollen](#5-stack-ausrollen)
6. [Backup einrichten](#6-backup-einrichten)
7. [Überwachung](#7-überwachung)
8. [Abnahme und Freigabe](#8-abnahme-und-freigabe)

## 1. Verträge und Konten (VIBEZ)

| Konto | Inhaber | Vertrag / AV | Zugang Murat |
|---|---|---|---|
| netcup (VPS) | Murat (Unterauftragsverarbeiter, Stand 18.11.2026) | AV-Vertrag Murat ↔ netcup im Kundencenter (CCP); Genehmigung im AV-Vertrag VIBEZ ↔ Murat | Inhaber; Notzugang für VIBEZ hinterlegen |
| Hetzner (nur Storage Box) | VIBEZ | AV-Vertrag im Hetzner-Konto abschließen | Projektmitglied, 2FA |
| MongoDB Atlas | VIBEZ (Organisation „VIBEZ“) | DPA aus den Atlas-Bedingungen dokumentieren | Projektmitglied „Project Owner“, 2FA |
| Cloudflare | VIBEZ | DPA aus den Self-Serve-Bedingungen dokumentieren | Mitglied „Administrator“, 2FA |
| Registrar `vibez-odenwald.de` | VIBEZ als Domaininhaber (sonst Übertragung bei Ende der Betreuung) | – (keine Klientendaten) | Verwaltung, 2FA |
| Tailscale | Murat | – (nur Verwaltungszugang, keine Inhalte) | – |

**Für alle Konten gilt: 2FA mit Passkey oder Hardwareschlüssel** (keine SMS), eigene Logins je Person, Wiederherstellungscodes
im Passwortmanager von VIBEZ. Bei GitHub zusätzlich: Branch-Schutz auf `main` (Änderungen nur über Pull Request mit grüner
CI). Begründung: [Sicherheitsanalyse, Abschnitt D](sicherheitsanalyse.md#d-konten-und-identitäten).
| GitHub `mbay-ODW` | Murat | – (Code und Image, keine Klientendaten) | – |
| Passwortmanager | VIBEZ | – | Einträge: restic-Passwort, Server-Konsolenpasswort, Atlas-Benutzer |

Außerdem: **AV-Vertrag VIBEZ ↔ Murat** (IT-Betreuung) inkl. Verpflichtung nach § 203 Abs. 4 StGB. Siehe
[Dienstleister](../datenschutz/dienstleister.md).

## 2. Server bestellen und härten

1. netcup → **VPS Lite 1 G12.5s** (2 vCore, 4 GB RAM, 80 GB SSD; Auswahl und Begründung: [aufbau.md](aufbau.md#serverwahl)):
   - Standort **Nürnberg** (netcup bietet auch Wien, Amsterdam, USA, Singapur an – nicht wählen)
   - Image **Debian 13** (im Server Control Panel, SCP, installieren)
   - feste IPv4 (für die Atlas-Zugriffsliste)
   - Hostname `vibez-prod`
   - Snapshot nach der Einrichtung im SCP anlegen (sichert den Server, nicht die Daten – die liegen in Atlas)
2. Bis zur Einrichtung ist SSH aus dem Internet erreichbar. Deshalb die Einrichtung zügig abschließen. Nach Schritt 5
   ist eingehend nichts mehr offen (`ufw`).
3. Einrichten (als root, einmalig) – im Aufbau übernimmt das die KI-Sitzung über Remote Control ([aufbau.md](aufbau.md)):

   ```bash
   scp host/bootstrap.sh root@<server-ip>:/root/
   ssh root@<server-ip> 'ADMIN=murat ADMIN_KEY="ssh-ed25519 AAAA… murat" TS_AUTHKEY=tskey-auth-… bash /root/bootstrap.sh'
   ```

   Das Skript aktualisiert das System, aktiviert automatische Sicherheitsupdates, legt das Admin-Konto an (nur
   Schlüssel), sperrt root- und Passwort-Login, installiert Docker und Tailscale und aktiviert die Host-Firewall, sobald
   Tailscale verbunden ist.
4. **Tailscale-ACL** setzen, sodass nur Murats Admin-Geräte den Server erreichen:

   ```json
   "tagOwners": { "tag:vibez-prod": ["autogroup:admin"] },
   "grants":    [ { "src": ["murat@…"], "dst": ["tag:vibez-prod"], "ip": ["tcp:22"] } ]
   ```

   Server mit `sudo tailscale up --advertise-tags=tag:vibez-prod` neu anmelden. Andere Geräte im Tailnet haben dann keinen Weg zum Server.
5. Prüfen: `ssh murat@vibez-prod` (über Tailscale) funktioniert und `ssh murat@<öffentliche-ip>` scheitert.
6. Ein **Konsolenpasswort** für `murat` setzen (`sudo passwd murat`) und im Passwortmanager von VIBEZ ablegen. Es wird nur
   für die netcup-Konsole (SCP, „Bildschirm“) im Notfall gebraucht, SSH nimmt weiterhin keine Passwörter an.

## 3. MongoDB Atlas

1. Organisation „VIBEZ“, Projekt **„VIBEZ Nachweise“**, Murat als Projektmitglied einladen, 2FA erzwingen.
2. Cluster anlegen: **AWS, eu-central-1 (Frankfurt)**, Tarif M0 zum Start (siehe
   [Architektur](architektur.md#atlas-einrichtung-wie-drk)), Name `vibez`.
3. **Backup:** M0 hat kein Cloud Backup. Die restic-Sicherung (Abschnitt 6) ist deshalb Pflicht vor dem Echtbetrieb.
   Ab Flex/M10 Cloud Backup einschalten.
4. **Database Access**:
   - `vibez_app`: Passwort generieren, Rolle *readWrite* nur auf Datenbank `vibez`
   - `vibez_backup`: Passwort generieren, nur *read* auf Datenbank `vibez` (M0 kennt die Rolle *backup* nicht sicher)
5. **Network Access**: einen Programmatic API Key für das Projekt mit der Rolle *Project IP Access List Admin*
   anlegen, dann auf dem Server ausführen:

   ```bash
   sudo ATLAS_PUBLIC_KEY=… ATLAS_PRIVATE_KEY=… ATLAS_GROUP_ID=… /opt/vibez/host/atlas-zugriffsliste.sh setzen
   ```

   Damit steht genau die IPv4 des Servers in der Liste. **Nie** `0.0.0.0/0` eintragen. Den API-Key danach nicht auf dem
   Server speichern.
6. Atlas-Alerts an Murat: Verbindung, Speicher, fehlgeschlagenes Backup.

## 4. Cloudflare: Domain, Tunnel, Regeln

Komplett in [cloudflare.md](cloudflare.md):

1. Domain `vibez-odenwald.de` registrieren, Zone in Cloudflare anlegen (leer)
2. Nameserver beim Registrar auf Cloudflare stellen, DNSSEC an (DS-Eintrag beim Registrar)
3. Mail-Schutz (Null-MX, SPF `-all`, DMARC `p=reject`) und CAA
4. Tunnel `vibez-prod` anlegen, `nachweise.vibez-odenwald.de` routen (proxied)
5. Zoneneinstellungen, 5 WAF-Regeln, Ratenlimit, Cache-Regel, Benachrichtigungen

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

1. Hetzner **Storage Box** bestellen (anderer Anbieter und anderer Standort als der netcup-Server). In der
   Storage-Box-Verwaltung SSH-Zugang aktivieren und **automatische Snapshots** einschalten (z. B. täglich, 14 Stück).
   Snapshots lassen sich nur in der Hetzner-Konsole löschen, nicht über SFTP. So übersteht die Sicherung auch einen
   kompromittierten Server.
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

- HTTP-Monitor `https://nachweise.vibez-odenwald.de/health`, Intervall 60 s, Schlüsselwort `"ok": true`,
  Zertifikatsablauf-Warnung an
- Push-Monitor „VIBEZ Backup“, Heartbeat-Intervall 26 Stunden → URL als `BACKUP_PING_URL` in `.env`
- Benachrichtigung per ntfy an Murat

## 8. Abnahme und Freigabe

Technik (Murat):

- [ ] `https://nachweise.vibez-odenwald.de` zeigt die Anmeldung, Zertifikat gültig
- [ ] Aufruf aus einem Nicht-EU-Land (VPN) wird blockiert, `/.env` wird blockiert
- [ ] `nmap` auf die öffentliche IP: keine offenen Ports
- [ ] Atlas-Zugriffsliste enthält nur die Server-IP; Verbindung von einem anderen Rechner scheitert
- [ ] Antwort-Header enthalten `Content-Security-Policy`, `Strict-Transport-Security`, `Cache-Control: no-store`
- [ ] Backup gelaufen, Restore-Test erfolgreich, Uptime-Kuma-Monitore grün
- [ ] Sicherung: erster restic-Lauf und Restore-Test erfolgreich (bei M0 die einzige Sicherung); Atlas-Speicheralarm bei 70 % eingerichtet
- [ ] restic-Passwort und Konsolenpasswort liegen im Passwortmanager von VIBEZ (Gegencheck durch Tobias)
- [ ] Der Server ist **nicht** in Portainer, MCP-Servern oder sonstigen KI-/Automationswerkzeugen eingebunden
- [ ] `VN_VERSION` enthält Version **und Digest**; Digest mit dem CI-Lauf verglichen
- [ ] Storage-Box-Snapshots aktiv; Tailscale-ACL aktiv (anderes Tailnet-Gerät erreicht Port 22 nicht)
- [ ] Domain `vibez-odenwald.de`: DNSSEC aktiv, CAA und Mail-Schutz gesetzt, Transfer Lock und automatische Verlängerung an, Zertifikats-Monitoring eingerichtet
- [ ] Cloudflare-Benachrichtigungen: Tunnel-Status, DNS-Änderungen
- [ ] 2FA mit Passkey in Cloudflare, Atlas, netcup, Hetzner, GitHub, Registrar; App-Verwaltung mit 2FA (sobald umgesetzt)

Organisation (VIBEZ):

- [ ] Datenschutz-Folgenabschätzung von Geschäftsführung und Datenschutzbeauftragter/m unterschrieben ([dsfa.md](../datenschutz/dsfa.md))
- [ ] Alle AV-Verträge abgeschlossen bzw. dokumentiert ([dienstleister.md](../datenschutz/dienstleister.md))
- [ ] Verzeichnis der Verarbeitungstätigkeiten ergänzt ([vvt.md](../datenschutz/vvt.md))
- [ ] Informationsblatt für Familien und Mitarbeitende ausgegeben ([informationen.md](../datenschutz/informationen.md))
- [ ] Mitarbeitende eingewiesen (Handy-Sperre, Abmelden, Verlust melden)
- [ ] Vor-Go-live-Maßnahmen der DSFA umgesetzt (z. B. Zwei-Faktor-Anmeldung, Löschkonzept)
