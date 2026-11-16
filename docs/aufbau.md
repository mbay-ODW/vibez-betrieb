# Aufbau des Echtbetriebs (Aufbauphase)

Stand 16.11.2026. Der Echtbetrieb wird von einer Claude-Code-Sitzung aufgebaut. Diese Ausnahme vom Grundsatz
„kein KI-Zugriff auf den Echtbetrieb“ hat Murat am 16.11.2026 freigegeben. Sie gilt **nur, solange keine echten Daten
vorhanden sind**.

## Inhalt

- [Regeln der Aufbauphase](#regeln-der-aufbauphase)
- [Serverwahl](#serverwahl)
- [Was VIBEZ und Murat vorbereiten](#was-vibez-und-murat-vorbereiten)
- [Remote Control auf dem Server einrichten](#remote-control-auf-dem-server-einrichten)
- [Tokens](#tokens)
- [Ablauf](#ablauf)
- [Aufbauprotokoll](#aufbauprotokoll)
- [Übergabe-Checkliste](#übergabe-checkliste)

## Regeln der Aufbauphase

1. **Keine echten Daten.** Während die KI-Sitzung Zugriff hat, ist die Datenbank leer. Angelegt werden nur Jugendämter,
   Einstellungen und Konten. Klient:innen werden erst nach der Übergabe erfasst.
2. **Geheimnisse entstehen auf dem Server und werden nie ausgegeben.** Atlas-Passwörter, restic-Passwort,
   `VN_SECRET_KEY`, das Startpasswort der Verwaltung und die Tunnel-Zugangsdaten erzeugt der Server selbst
   (`openssl rand`) direkt in `.env` bzw. `credentials.json`. Murat überträgt sie von dort in den Passwortmanager von VIBEZ.
3. **Tokens nur über das sichere Formular** der Claude-Sitzung, nie im Chat. Sie haben minimale Rechte und kurze Laufzeit.
4. **Jede Aktion steht im [Aufbauprotokoll](#aufbauprotokoll).**
5. **Vor dem ersten echten Datensatz** wird die [Übergabe-Checkliste](#übergabe-checkliste) vollständig abgearbeitet.

## Serverwahl

netcup **VPS Lite 1 G12.5s**: 2 vCore, 4 GB RAM, 80 GB SSD, 5,86 €/Monat (Angebot vom 16.11.2026), Standort Nürnberg.

| Variante | RAM | Bewertung |
|---|---|---|
| VPS pico (1 GB) | zu knapp | System und Docker belegen schon ca. 0,5 GB; Druckstapel und Restore-Test brauchen kurzzeitig mehrere hundert MB |
| VPS nano (2 GB) | knapp | läuft, aber Backup bzw. Restore-Test parallel zu einem Druckstapel kann einen Speichermangel-Neustart auslösen |
| **VPS Lite 1 (4 GB)** | ausreichend | Luft für App, Traefik, cloudflared, nächtliches Backup und monatlichen Restore-Test |

## Was VIBEZ und Murat vorbereiten

| Wer | Was |
|---|---|
| Tobias | Hilfsdomain bei All-Inkl registrieren (automatische Verlängerung an); Cloudflare-Konto für VIBEZ (Free, 2FA, Zahlungsmittel), Hilfsdomain dort hinzufügen, deren **Nameserver bei All-Inkl** auf die zwei Cloudflare-Nameserver umstellen. `vibez-jugendhilfe.de` selbst bleibt unverändert. |
| Tobias | netcup-VPS bestellen (VIBEZ als Kunde), AV-Vertrag im netcup-Kundencenter abschließen |
| Tobias | MongoDB Atlas: Organisation und Projekt „VIBEZ Nachweise“ (Zahlungsmittel, 2FA); Murat als Projektmitglied |
| Tobias | Hetzner Storage Box bestellen, SSH-Zugang aktivieren, automatische Snapshots an |
| Tobias / Murat | Festlegen: App-Adresse (`nachweise.vibez-jugendhilfe.de`?) und Name der Hilfsdomain |
| Murat | Debian 13 auf dem VPS installieren (netcup SCP), Remote Control einrichten (nächster Abschnitt) |
| Murat | Tokens erzeugen (Abschnitt [Tokens](#tokens)) und im Formular der Sitzung eintragen |

## Remote Control auf dem Server einrichten

Auf dem frischen VPS als root (SSH mit dem bei netcup hinterlegten Zugang):

```bash
apt-get update && apt-get install -y curl git tmux
curl -fsSL https://claude.ai/install.sh | bash
mkdir -p /opt/vibez && cd /opt/vibez
tmux new -s aufbau
```

In der tmux-Sitzung:

```bash
claude                  # einmalig anmelden: angezeigten Link im Browser öffnen, Code zurückkopieren, dann /exit
claude remote-control   # stellt /opt/vibez dieser Claude-Sitzung zur Verfügung
```

tmux mit `Strg+b`, dann `d` verlassen. Remote Control läuft weiter, auch wenn die SSH-Verbindung endet. Danach in der
Claude-Sitzung Bescheid geben. Die Sitzung fragt den Ordner an, und du bestätigst in der App.

## Tokens

| Für | Erzeugen | Rechte | Laufzeit / danach |
|---|---|---|---|
| Cloudflare (VIBEZ-Konto) | *My Profile → API Tokens → Create Token → Custom* | Zone (nur Hilfszone): DNS Edit, SSL and Certificates Edit, Zone Settings Edit, Zone WAF Edit, Cache Rules Edit; Account: Cloudflare Tunnel Edit, Notifications Edit | 7 Tage, nach Übergabe löschen |
| MongoDB Atlas | Projekt → *Access Manager → Service Accounts* | *Project Owner* nur für dieses Projekt | nach Übergabe löschen |
| GitHub (Image ziehen) | Fine-grained Token, Zugriff nur auf `vibez-nachweise`, Berechtigung *Packages: read* | Image ziehen | bleibt auf dem Server (in `docker login`), Ablauf 1 Jahr, im Kalender vermerken |
| Tailscale | *Settings → Keys → Generate auth key*, einmalig, Tag `tag:vibez-prod` | nur Anmeldung des Servers | verfällt nach Benutzung |

## Ablauf

1. Server härten (`host/bootstrap.sh`; Tailscale; Firewall), Repo nach `/opt/vibez` klonen
2. Atlas: Cluster Frankfurt, Benutzer `vibez_app`/`vibez_backup` (Passwörter auf dem Server erzeugt), IP-Zugriffsliste
   = Server-IP, Backups und Alerts
3. Cloudflare: Tunnel `vibez-prod`, Fallback-Origin, Custom Hostname, 5 WAF-Regeln, Ratenlimit, Cache-Regel,
   Einstellungen, Benachrichtigungen → **drei DNS-Einträge für Tobias** (All-Inkl)
4. Stack ausrollen (`stack/deploy.sh <version>` mit Digest), Verwaltungszugang `tobias` mit Startpasswort (auf dem
   Server erzeugt), Pflicht-2FA
5. Backup einrichten (Storage Box, restic init, erster Lauf, Restore-Test, Timer)
6. Abnahme-Checkliste aus [deployment.md](deployment.md#8-abnahme-und-freigabe)
7. Übergabe

## Aufbauprotokoll

Wird während des Aufbaus fortgeschrieben. Nur technische Angaben, keine Geheimnisse, keine Personendaten.

| Datum/Zeit | Schritt | Ergebnis | Bemerkung |
|---|---|---|---|
| 16.11.2026 | Repo vorbereitet, netcup gewählt, App 0.2.6 mit 2FA | ✅ | – |

## Übergabe-Checkliste

Vor dem ersten echten Datensatz – Murat hakt ab, Tobias bestätigt:

- [ ] Remote Control auf dem Server beendet (`tmux kill-session -t aufbau`)
- [ ] Claude Code vom Server entfernt (`rm -rf ~/.local/bin/claude ~/.local/share/claude ~/.claude ~/.claude.json`), Anmeldung im Claude-Konto unter *Geräte/Sitzungen* geprüft
- [ ] Cloudflare-Token der Aufbauphase gelöscht
- [ ] Atlas-Service-Account der Aufbauphase gelöscht; nur `vibez_app`, `vibez_backup` und der IP-Listen-Key bleiben
- [ ] Tailscale-Auth-Key verbraucht/gelöscht
- [ ] Alle auf dem Server erzeugten Geheimnisse liegen im Passwortmanager von VIBEZ (restic-Passwort, Atlas-Benutzer, Konsolenpasswort)
- [ ] Startpasswort von `tobias` wurde beim ersten Login geändert, 2FA eingerichtet
- [ ] Datenbank enthält keine Testdaten (nur Einstellungen, Jugendämter, Konten)
- [ ] Abnahme-Checkliste in [deployment.md](deployment.md#8-abnahme-und-freigabe) vollständig
- [ ] Ab jetzt gilt wieder: kein KI-Zugriff auf den Echtbetrieb (CLAUDE.md, DSFA T12)

Datum, Murat: ______________  Datum, Tobias: ______________
