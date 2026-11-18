# Aufbau des Echtbetriebs (Aufbauphase)

Stand 18.11.2026. Die Installation des Echtbetriebs mit KI ist **ausdrücklich erlaubt** (freigegeben von Murat am
16.11.2026, am 18.11.2026 auf jeden bereitgestellten Zugang erweitert: Claude Code auf dem Server, Remote Control, SSH,
API-Tokens, Cloudflare-Anbindung). Das gilt **nur, solange keine echten Daten vorhanden sind**.

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
| Murat | Domain `vibez-odenwald.de` registrieren (Domaininhaber möglichst VIBEZ), Cloudflare-Konto (Free, 2FA mit Passkey), Zone anlegen und Nameserver beim Registrar auf Cloudflare stellen. Schritt für Schritt: [cloudflare.md](cloudflare.md#domain-und-zone-einrichten) |
| Murat | ✅ netcup-VPS bestellt (Vertrag dauerhaft auf Murat). AV-Vertrag Murat ↔ netcup im Kundencenter (CCP) abschließen; netcup, Cloudflare und febas als Unterauftragsverarbeiter im AV-Vertrag VIBEZ ↔ Murat aufführen |
| Tobias | MongoDB Atlas: Organisation und Projekt „VIBEZ Nachweise“ (Zahlungsmittel, 2FA); Murat als Projektmitglied |
| Tobias | Hetzner Storage Box bestellen, SSH-Zugang aktivieren, automatische Snapshots an |
| ✅ | App-Adresse festgelegt: `nachweise.vibez-odenwald.de` (18.11.2026) |
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

### Weiterarbeiten in der Sitzung auf dem Server

Eine Cloud-Sitzung kann den Ordner auf dem Server nicht in jedem Konto anfordern (Stand 18.11.2026: nicht verfügbar).
Dann läuft der Aufbau **in der Remote-Control-Sitzung selbst**: Sie erscheint in der Claude-App (Code) unter dem Namen
des Servers. Dort weiterarbeiten.

Zuerst braucht der Server Lesezugriff auf GitHub. Murat erzeugt einen Fine-grained Token (Repos `vibez-betrieb` und
`vibez-nachweise`; *Contents: read*, *Packages: read*; Ablauf 1 Jahr) und meldet ihn **selbst im Terminal** an, nicht im Chat:

```bash
apt-get install -y gh
gh auth login --with-token     # Token einfügen, Enter, Strg+D
gh auth setup-git
git clone https://github.com/mbay-ODW/vibez-betrieb /opt/vibez/repo
```

Erste Nachricht an die Sitzung auf dem Server:

```text
Du baust den Echtbetrieb von VIBEZ Nachweise auf diesem Server auf. Lies zuerst
/opt/vibez/repo/CLAUDE.md und /opt/vibez/repo/docs/aufbau.md und halte dich streng an die
Regeln der Aufbauphase: keine echten Daten, Geheimnisse nur auf dem Server erzeugen und nie
ausgeben (auch nicht im Chat oder in Logs), jede Aktion ins Aufbauprotokoll (docs/aufbau.md),
Änderungen am Repo als Commit. Stand: Domain vibez-odenwald.de und Cloudflare-Zone sind fertig
(WAF, DNSSEC, Mail-Schutz); es fehlen Server-Härtung, Tunnel, Atlas, Stack, Backup.
Beginne mit Schritt 1 des Ablaufs (host/bootstrap.sh) und sag mir vorher, was du ausführst.
```

## Tokens

| Für | Erzeugen | Rechte | Laufzeit / danach |
|---|---|---|---|
| Cloudflare | *My Profile → API Tokens → Create Token → Custom* | Zone (nur `vibez-odenwald.de`): DNS Edit, SSL and Certificates Edit, Zone Settings Edit, Zone WAF Edit, Cache Rules Edit; Account: Cloudflare Tunnel Edit, Notifications Edit | 7 Tage, nach Übergabe löschen |
| MongoDB Atlas | Projekt → *Access Manager → API Keys* (oder Service Account); API-Zugriffsliste = Server-IP. Ablage nur auf dem Server in `/root/aufbau/atlas.env` (600) als `MONGODB_ATLAS_PUBLIC_API_KEY`, `MONGODB_ATLAS_PRIVATE_API_KEY`, `MONGODB_ATLAS_PROJECT_ID` – nie in Chat oder Screenshot | *Project Owner* nur für dieses Projekt | nach Übergabe löschen |
| GitHub (Image ziehen) | Fine-grained Token, Zugriff nur auf `vibez-nachweise`, Berechtigung *Packages: read* | Image ziehen | bleibt auf dem Server (in `docker login`), Ablauf 1 Jahr, im Kalender vermerken |
| Tailscale | *Settings → Keys → Generate auth key*, einmalig, Tag `tag:vibez-prod` | nur Anmeldung des Servers | verfällt nach Benutzung |

## Ablauf

1. Server härten (`host/bootstrap.sh`; Tailscale; Firewall), Repo nach `/opt/vibez` klonen
2. Atlas: Cluster Frankfurt, Benutzer `vibez_app`/`vibez_backup` (Passwörter auf dem Server erzeugt), IP-Zugriffsliste
   = Server-IP, Backups und Alerts
3. Cloudflare (sobald die Zone `vibez-odenwald.de` aktiv ist): Tunnel `vibez-prod`, `nachweise` als proxied Eintrag,
   Mail-Schutz und CAA, 5 WAF-Regeln, Ratenlimit, Cache-Regel, Einstellungen, Benachrichtigungen. DNSSEC schaltet Murat
   ein (DS-Eintrag beim Registrar).
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
| 18.11.2026 | Eigene Domain `vibez-odenwald.de` für die App festgelegt (statt DNS-Umzug von `vibez-jugendhilfe.de`) | ✅ | – |
| 18.11.2026 | Domain bei febas registriert (Murat); Zone in Cloudflare angelegt (vorerst Murats Konto, Nameserver `cory`/`kenia`) | ✅ | Übertragung an VIBEZ offen (Übergabe-Checkliste) |
| 18.11.2026 | Cloudflare-API: 10 vom Registrar übernommene Einträge gelöscht (Parkseite, febas-Mail); Null-MX, SPF `-all`, DMARC `p=reject`, leerer DKIM angelegt | ✅ | Zone noch „pending“, bis die Nameserver bei febas umgestellt sind |
| 18.11.2026 | Nameserver bei febas umgestellt, Zone „active“ (08:58 UTC); DNSSEC in Cloudflare eingeschaltet (Schlüssel 2371, Algorithmus 13) | ✅ | DS-Eintrag bei febas ausstehend |
| 18.11.2026 | Server: Debian 13, Claude Code, Remote Control (tmux `aufbau`); `gh` mit Murats Konto angemeldet (Browser-Anmeldung, Zusatzrecht `read:packages`); Repo nach `/opt/vibez/repo` | ✅ | GitHub-Anmeldung vor Übergabe ersetzen (Checkliste) |
| 18.11.2026 | Erster Atlas-API-Key versehentlich per Screenshot im Chat gezeigt → in Atlas gelöscht, neuer Key angelegt | ✅ | Bild in der Sitzungsumgebung gelöscht |
| 18.11.2026 | Atlas: Cluster **M0** (Frankfurt) von Murat angelegt; X.509-Zertifikat erzeugt und heruntergeladen | ✅ | M0 ohne Cloud Backup → restic einzige Sicherung (DSFA 0.16); Zertifikat nur auf den Server übertragen |
| 18.11.2026 | DS-Eintrag (Key Tag 2371) über den febas-Support beantragt; febas meldet: bei DENIC hinterlegt | ✅ | Cloudflare-Status noch „pending“ (prüft selbst in Abständen) |
| 18.11.2026 | netcup-VPS bestellt, Vertrag auf Murat | ✅ | AV-Vertrag Murat ↔ netcup offen; Unterauftrag im AV-Vertrag mit VIBEZ aufnehmen |
| 18.11.2026 | Cloudflare-Token (nur Zone `vibez-odenwald.de`) über das sichere Formular hinterlegt; Zoneneinstellungen gesetzt (Full strict, TLS ≥ 1.2, Always HTTPS, 0-RTT aus, Email Obfuscation/Rocket Loader/SSE aus, AI-Bots blockiert); 5 WAF-Regeln, Ratenlimit `/login`, Cache-Regel, Managed Free Ruleset; CAA `letsencrypt.org` und `pki.goog` | ✅ | Universal SSL aktiv (Let's Encrypt, Reserve Google). Benachrichtigungen (Konto-Ebene) noch von Hand |
| 18.11.2026 | Zugang der Aufbausitzung per SSH vom Mac (Schlüssel für root, dann `murat`); `git pull`, CLAUDE.md und aufbau.md gelesen | ✅ | SSH als Zugang am 18.11. freigegeben (Commit 7739ef6) |
| 18.11.2026 | `/etc/sudoers.d/90-aufbau`: `murat` sudo ohne Passwort (nur Aufbauphase) | ✅ | Vor Übergabe löschen (Checkliste) |
| 18.11.2026 | `host/bootstrap.sh` (ADMIN=`murat`, ohne `TS_AUTHKEY`): Updates, unattended-upgrades, Admin `murat` nur mit Schlüssel, root- und Passwort-Login aus, Docker 29.10.0, Tailscale-Paket installiert | ✅ | Kernel 6.12.117 |
| 18.11.2026 | **Abweichung (Entscheidung Murat):** kein Tailscale. SSH auf Port **5022** (`/etc/ssh/sshd_config.d/20-vibez-port.conf`), Port 22 zu; `ufw` aktiv: eingehend nur `5022/tcp` (limit), Rest deny | ✅ | Architektur, DSFA/TOM und deployment.md nennen noch „SSH nur über Tailscale“ – anpassen; Tailscale-Paket ungenutzt |

## Übergabe-Checkliste

Vor dem ersten echten Datensatz – Murat hakt ab, Tobias bestätigt:

- [ ] Remote Control auf dem Server beendet (`tmux kill-session -t aufbau`)
- [ ] `/etc/sudoers.d/90-aufbau` gelöscht (sudo für `murat` wieder mit Passwort; vorher Passwort setzen)
- [ ] Claude Code vom Server entfernt (`rm -rf ~/.local/bin/claude ~/.local/share/claude ~/.claude ~/.claude.json`), Anmeldung im Claude-Konto unter *Geräte/Sitzungen* geprüft
- [ ] Cloudflare-Token der Aufbauphase gelöscht
- [ ] Domain `vibez-odenwald.de`, Cloudflare-Zone und netcup-Vertrag (dauerhaft auf Murat): Unterauftrag im AV-Vertrag mit VIBEZ genehmigt, Vorgehen bei Ende der Betreuung schriftlich geregelt
- [ ] Cloudflare-Anbindung (MCP) bleibt als begrenzte Ausnahme nach DSFA T12 (Entscheidung 18.11.2026): Benachrichtigung bei DNS-Änderungen eingerichtet, Prüfung des Audit-Logs in die monatliche Wartung aufgenommen
- [ ] Atlas-Service-Account der Aufbauphase gelöscht; nur `vibez_app`, `vibez_backup` und der IP-Listen-Key bleiben
- [ ] Tailscale-Auth-Key verbraucht/gelöscht
- [ ] GitHub auf dem Server: `gh auth logout` (Anmeldung mit Murats ganzem Konto aus der Aufbauphase entfernt); für das Image nur noch der Fine-grained Token mit *Packages: read* in `docker login ghcr.io`; Repo-Updates mit Token nur *Contents: read*
- [ ] Alle auf dem Server erzeugten Geheimnisse liegen im Passwortmanager von VIBEZ (restic-Passwort, Atlas-Benutzer, Konsolenpasswort)
- [ ] Startpasswort von `tobias` wurde beim ersten Login geändert, 2FA eingerichtet
- [ ] Datenbank enthält keine Testdaten (nur Einstellungen, Jugendämter, Konten)
- [ ] Abnahme-Checkliste in [deployment.md](deployment.md#8-abnahme-und-freigabe) vollständig
- [ ] Ab jetzt gilt wieder: kein KI-Zugriff auf den Echtbetrieb, außer der Cloudflare-Konfiguration nach DSFA T12 (CLAUDE.md)

Datum, Murat: ______________  Datum, Tobias: ______________
