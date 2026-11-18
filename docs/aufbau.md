# Aufbau des Echtbetriebs (Aufbauphase)

Stand 18.11.2026. Der Echtbetrieb wird von einer Claude-Code-Sitzung aufgebaut. Diese Ausnahme vom Grundsatz
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
| Murat | Domain `vibez-odenwald.de` registrieren (Domaininhaber möglichst VIBEZ), Cloudflare-Konto (Free, 2FA mit Passkey), Zone anlegen und Nameserver beim Registrar auf Cloudflare stellen. Schritt für Schritt: [cloudflare.md](cloudflare.md#domain-und-zone-einrichten) |
| Murat | netcup-VPS bestellen – **Kunde VIBEZ** (Kundendaten und Rechnungsadresse VIBEZ), AV-Vertrag im netcup-Kundencenter abschließen. Läuft der Vertrag doch auf Murat: netcup als Unterauftragsverarbeiter im AV-Vertrag mit VIBEZ genehmigen lassen und bei Ende der Betreuung übertragen |
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

## Tokens

| Für | Erzeugen | Rechte | Laufzeit / danach |
|---|---|---|---|
| Cloudflare | *My Profile → API Tokens → Create Token → Custom* | Zone (nur `vibez-odenwald.de`): DNS Edit, SSL and Certificates Edit, Zone Settings Edit, Zone WAF Edit, Cache Rules Edit; Account: Cloudflare Tunnel Edit, Notifications Edit | 7 Tage, nach Übergabe löschen |
| MongoDB Atlas | Projekt → *Access Manager → Service Accounts* | *Project Owner* nur für dieses Projekt | nach Übergabe löschen |
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
| 18.11.2026 | netcup-VPS bestellt (Murat) | ✅ | Vertragspartner und AV-Vertrag prüfen |
| 18.11.2026 | Cloudflare-Token (nur Zone `vibez-odenwald.de`) über das sichere Formular hinterlegt; Zoneneinstellungen gesetzt (Full strict, TLS ≥ 1.2, Always HTTPS, 0-RTT aus, Email Obfuscation/Rocket Loader/SSE aus, AI-Bots blockiert); 5 WAF-Regeln, Ratenlimit `/login`, Cache-Regel, Managed Free Ruleset; CAA `letsencrypt.org` und `pki.goog` | ✅ | Universal SSL aktiv (Let's Encrypt, Reserve Google). Benachrichtigungen (Konto-Ebene) noch von Hand |

## Übergabe-Checkliste

Vor dem ersten echten Datensatz – Murat hakt ab, Tobias bestätigt:

- [ ] Remote Control auf dem Server beendet (`tmux kill-session -t aufbau`)
- [ ] Claude Code vom Server entfernt (`rm -rf ~/.local/bin/claude ~/.local/share/claude ~/.claude ~/.claude.json`), Anmeldung im Claude-Konto unter *Geräte/Sitzungen* geprüft
- [ ] Cloudflare-Token der Aufbauphase gelöscht
- [ ] Domain `vibez-odenwald.de`, Cloudflare-Konto und netcup-Vertrag: Inhaber VIBEZ oder Übertragung schriftlich geregelt
- [ ] Atlas-Service-Account der Aufbauphase gelöscht; nur `vibez_app`, `vibez_backup` und der IP-Listen-Key bleiben
- [ ] Tailscale-Auth-Key verbraucht/gelöscht
- [ ] Alle auf dem Server erzeugten Geheimnisse liegen im Passwortmanager von VIBEZ (restic-Passwort, Atlas-Benutzer, Konsolenpasswort)
- [ ] Startpasswort von `tobias` wurde beim ersten Login geändert, 2FA eingerichtet
- [ ] Datenbank enthält keine Testdaten (nur Einstellungen, Jugendämter, Konten)
- [ ] Abnahme-Checkliste in [deployment.md](deployment.md#8-abnahme-und-freigabe) vollständig
- [ ] Ab jetzt gilt wieder: kein KI-Zugriff auf den Echtbetrieb (CLAUDE.md, DSFA T12)

Datum, Murat: ______________  Datum, Tobias: ______________
