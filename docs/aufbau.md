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

## Ablauf

1. Server härten (`host/bootstrap.sh`: Schlüssel-Login, SSH-Port 5022, Firewall), Repo nach `/opt/vibez` klonen
2. Atlas: Cluster Frankfurt, X.509-Benutzer `prod`/`vibez_backup` (Zertifikate auf dem Server erzeugt), IP-Zugriffsliste
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
| 18.11.2026 | Atlas: Cluster **Flex** (Frankfurt) von Murat angelegt; X.509-Zertifikat erzeugt und heruntergeladen | ✅ | Flex mit 7 Tagen Snapshots (Atlas-Oberfläche); restic für 12 Monate (DSFA 0.16); Zertifikat nur auf den Server übertragen |
| 18.11.2026 | Atlas: Rechte des X.509-Benutzers auf `readWrite@vibez` eingeschränkt (vorher alle Datenbanken) | ✅ | Ablaufdatum des Zertifikats im Kalender vermerken |
| 18.11.2026 | DS-Eintrag (Key Tag 2371) über den febas-Support beantragt; febas meldet: bei DENIC hinterlegt | ✅ | Cloudflare-Status noch „pending“ (prüft selbst in Abständen) |
| 18.11.2026 | netcup-VPS bestellt, Vertrag auf Murat | ✅ | AV-Vertrag Murat ↔ netcup offen; Unterauftrag im AV-Vertrag mit VIBEZ aufnehmen |
| 18.11.2026 | Cloudflare-Token (nur Zone `vibez-odenwald.de`) über das sichere Formular hinterlegt; Zoneneinstellungen gesetzt (Full strict, TLS ≥ 1.2, Always HTTPS, 0-RTT aus, Email Obfuscation/Rocket Loader/SSE aus, AI-Bots blockiert); 5 WAF-Regeln, Ratenlimit `/login`, Cache-Regel, Managed Free Ruleset; CAA `letsencrypt.org` und `pki.goog` | ✅ | Universal SSL aktiv (Let's Encrypt, Reserve Google). Benachrichtigungen (Konto-Ebene) noch von Hand |
| 18.11.2026 | Zugang der Aufbausitzung per SSH vom Mac (Schlüssel für root, dann `murat`); `git pull`, CLAUDE.md und aufbau.md gelesen | ✅ | SSH als Zugang am 18.11. freigegeben (Commit 7739ef6) |
| 18.11.2026 | `/etc/sudoers.d/90-aufbau`: `murat` sudo ohne Passwort (nur Aufbauphase) | ✅ | Vor Übergabe löschen (Checkliste) |
| 18.11.2026 | `host/bootstrap.sh` (ADMIN=`murat`, ohne `TS_AUTHKEY`): Updates, unattended-upgrades, Admin `murat` nur mit Schlüssel, root- und Passwort-Login aus, Docker 29.10.0, Tailscale-Paket installiert | ✅ | Kernel 6.12.117 |
| 18.11.2026 | **Abweichung (Entscheidung Murat):** kein Tailscale. SSH auf Port **5022** (`/etc/ssh/sshd_config.d/20-vibez-port.conf`), Port 22 zu; `ufw` aktiv: eingehend nur `5022/tcp` (limit), Rest deny | ✅ | Unterlagen angepasst (DSFA 0.17); Tailscale-Paket ungenutzt, kann deinstalliert werden |
| 18.11.2026 | Atlas (per API vom Server): X.509-Benutzer `vibez_backup` (read auf `vibez`) angelegt; Zertifikate für `prod` und `vibez_backup` auf dem Server erzeugt (`stack/secrets/`, 400, gültig bis 18.11.2028) | ✅ | X.509 statt Passwort (Entscheidung Murat); `/opt/vibez/stack` und `/opt/vibez/host` als Links auf das Repo |
| 18.11.2026 | `stack/.env` angelegt (600 root): `VN_SECRET_KEY`, Startpasswort `tobias` auf dem Server erzeugt; Atlas-Adressen mit X.509; `MONGO_TOOLS_VERSION` 8.0 | ✅ | `VN_VERSION` (Schritt 4), restic (Schritt 5) noch leer |
| 18.11.2026 | Test mit Wegwerf-Containern: `prod` ping ok, Rolle `readWrite@vibez` (als UID 10001); `vibez_backup` ping ok, `read@vibez`; `mongodump` ok (leere DB) | ✅ | – |
| 18.11.2026 | Atlas-Alerts ergänzt: Flex-Speicher > 3,5 GB (70 %), IP-Zugriffsliste Eintrag hinzugefügt/entfernt | ✅ | Änderungen an DB-Benutzern bietet Atlas nicht als Alert an. IP `91.18.162.56` (Murat) bleibt bewusst in der Zugriffsliste |
| 18.11.2026 | Cloudflare-Tunnel `vibez-prod` (ID `7299c757-f13e-42d4-8257-549a5dfe0163`) auf dem Server angelegt (`cloudflared tunnel login` mit Bestätigung durch Murat); `credentials.json` nur auf dem Server (400, UID 65532), ID in `config.yml` | ✅ | `cert.pem` aus dem Login danach gelöscht |
| 18.11.2026 | DNS: `nachweise.vibez-odenwald.de` als proxied CNAME auf den Tunnel (`tunnel route dns`, Freigabe Murat) | ✅ | Bis Schritt 4 antwortet die Adresse mit 530 (kein Connector) |
| 18.11.2026 | GHCR-Lesezugang auf dem Server (`docker login ghcr.io`, Classic Token nur `read:packages`, von Murat eingegeben) | ✅ | Ablauf 18.11.2027; ersetzen durch Fine-grained Token, sobald GitHub das für Pakete anbietet |
| 18.11.2026 | Digest von 0.2.6 geprüft: Registry = GitHub-Paket-API = `sha256:8c8fbf3d…af12f284` (Tag `sha-e74dfee`, CI grün 16.11.) | ✅ | Freigabe Murat |
| 18.11.2026 | Atlas: `prod` zusätzlich `dbAdmin@vibez` – die App legt beim Start Indizes an, `readWrite` erlaubt das auf Flex nicht (`createIndex` verweigert) | ✅ | – |
| 18.11.2026 | Stack gestartet: `VN_VERSION=0.2.6@sha256:8c8fbf3d…` in `.env`, `deploy.sh` ohne Versionsangabe (erster Start, leere Datenbank – Backup vor dem Update entfällt, restic folgt in Schritt 5); Verwaltungskonto `tobias` mit Startpasswort vom Server | ✅ | – |
| 18.11.2026 | Traefik-Health-Check sendet jetzt den App-Hostnamen (`hostname` in `vibez.yml`), sonst 400 wegen `VN_HOSTS` | ✅ | `/health`, `/login`, `/hilfe` über Cloudflare 200; HSTS, CSP, `X-Frame-Options`, `no-store` gesetzt; Tunnel mit 4 Verbindungen; eingehend nur 5022 |
| 18.11.2026 | `/root/aufbau/zugaenge-fuer-bitwarden.sh`: zeigt Murat die auf dem Server erzeugten Zugänge im eigenen Terminal zum Übertragen in Bitwarden | ✅ | Nur von Murat auszuführen |
| 18.11.2026 | Verwaltungs-Stack `stack-admin/` gestartet (Entscheidung Murat, wie DRK): Redis 8.8.4, LLDAP v0.6.3, Authelia 4.39.28, Portainer CE 2.45.3, Dozzle v11.4.3, Uptime Kuma 2.5.12; Geheimnisse auf dem Server erzeugt (`stack-admin/.env`, `stack-admin/secrets/`) | ✅ | Daten unter `/srv/vibez/admin/` |
| 18.11.2026 | LLDAP-Bootstrap: Gruppen `vibez-infra_admin`, `vibez-app_admin`, `vibez-app_user`, `vibez-testing_admin`, `vibez-testing_user`; Dienstkonto `authelia` (Gruppe `lldap_password_manager`) | ✅ | Benutzer legt Murat an |
| 18.11.2026 | Traefik am Netz `vibez-admin`, Routen `admin.yml` mit Authelia-ForwardAuth; cloudflared-Ingress und DNS für `auth`, `ldap`, `portainer`, `logs`, `status` (neuer `tunnel login`, `cert.pem` danach gelöscht) | ✅ | Erster Versuch ohne angekommene Bestätigung: nichts angelegt, Login neu gestartet |
| 18.11.2026 | Cloudflare-WAF angepasst (Wartungsprotokoll `wartung/2026.md`); Probe: alle fünf Adressen leiten ohne Anmeldung auf `auth.` um, gefälschte `Remote-User`/`Remote-Groups` werden ignoriert, App weiter 200 | ✅ | DSFA 0.18, TOM, Architektur angepasst |
| 18.11.2026 | LLDAP: Dienstkonto `vibez-usersync` (`lldap_strict_readonly`) und Konto `murat` (`vibez-infra_admin`, `vibez-app_admin`, Startpasswort vom Server) | ✅ | Startpasswort über `zugaenge-fuer-bitwarden.sh` |
| 18.11.2026 | App 0.3.0 (PR mbay-ODW/vibez-nachweise#7, CI grün) ausgerollt, Digest `sha256:41a5bb07…f7a683` (Registry = GitHub-API, Tag `sha-143439a`, Freigabe Murat); `VN_AUTH=authelia`, `VN_PROXY_SECRET` auf dem Server erzeugt | ✅ | – |
| 18.11.2026 | Traefik: Middleware `remote-weg` entfernt eingehende `Remote-*`/`X-Proxy-Secret` vor Authelia (auch Verwaltungsadressen), `proxy-geheimnis` setzt das Geheimnis danach; Authelia-Regel `nachweise` (2FA, Gruppen `vibez-app_*`, `/health` frei); Netz `vibez-ldap` für UserSync | ✅ | Probe: ohne Anmeldung → `auth.`; gefälschte Header + falsches Geheimnis → `auth.`; direkt an die App ohne Geheimnis → 403; `/health` 200 |
| 18.11.2026 | UserSync 0.3.0 brach mit `LDAPAttributeError` ab (LLDAP liefert Attributnamen klein) → Korrektur 0.3.1 (PR mbay-ODW/vibez-nachweise#8), einmal gegen das echte LLDAP geprüft: `murat` abgeglichen | ✅ | – |
| 18.11.2026 | App 0.3.1 ausgerollt (Merge `1fb1cf9`, CI grün), Digest `sha256:857aa459…f539b734` (Registry = GitHub-API, Freigabe Murat); UserSync: `Abgleich: aktiv 1, deaktiviert 0`; UserSync ohne HTTP-Health-Check | ✅ | `/health` 200, ohne Anmeldung → `auth.` |
| 18.11.2026 | Atlas Testprojekt: Server-IP in der Zugriffsliste, `mongodb_db_user` gelöscht, Zertifikat `testing` auf dem Server (bis 18.11.2028); Rolle `testing` bleibt `readWriteAnyDatabase` (Entscheidung Murat) | ✅ | – |
| 18.11.2026 | App-CI: Branch `testing` baut `:testing` (PR mbay-ODW/vibez-nachweise#9); Branch `testing` angelegt. Branch-Schutz auf `main` **nicht möglich** (GitHub Free, privates Repo) | ⚠️ | DSFA 0.19, Sicherheitsanalyse B2 |
| 18.11.2026 | Testumgebung `stack-testing/` (App mit Demodaten, `VN_AUTH=authelia`, Gruppen `vibez-testing_*`, eigener UserSync, eigenes Proxy-Geheimnis); Authelia-Regel, Traefik-Route `testing.yml`, Tunnel-Eintrag, DNS `nachweise-testing` (Freigabe Murat), WAF-Regel 5 von Murat erweitert | ✅ | Probe: ohne Anmeldung → `auth.`, gefälschte Header → `auth.`, `/health` 200 |
| 18.11.2026 | Automatisches Ausrollen: `host/autodeploy.sh` + `vibez-autodeploy.timer` (5 Min.), `deploy.sh --auto` mit Rücksprung; Probe: Testing auf `:testing@sha256:5df0def5…` umgestellt, zweiter Lauf ohne Änderung, Produktion unverändert 0.3.1 | ✅ | Ohne restic: Update ohne Backup mit Warnung – nur bis zum ersten echten Datensatz zulässig |

## Übergabe-Checkliste

Vor dem ersten echten Datensatz – Murat hakt ab, Tobias bestätigt:

- [ ] Remote Control auf dem Server beendet (`tmux kill-session -t aufbau`)
- [ ] restic eingerichtet (`RESTIC_REPOSITORY` in `stack/.env`) – sonst rollt `autodeploy` ohne Backup aus
- [ ] Konto `tobias` in LLDAP (Benutzername `tobias`, Gruppe `vibez-app_admin`) – übernimmt das bestehende App-Konto; Startpasswort von `murat` geändert
- [ ] LLDAP-`admin` und Portainer-Admin: Passwörter in Bitwarden, persönliche Konten in `vibez-infra_admin` mit 2FA eingerichtet; `stack-admin/secrets/portainer_admin_pass` und `lldap-users/` vom Server gelöscht
- [ ] `/etc/sudoers.d/90-aufbau` gelöscht (sudo für `murat` wieder mit Passwort; vorher Passwort setzen)
- [ ] Claude Code vom Server entfernt (`rm -rf ~/.local/bin/claude ~/.local/share/claude ~/.claude ~/.claude.json`), Anmeldung im Claude-Konto unter *Geräte/Sitzungen* geprüft
- [ ] Cloudflare-Token der Aufbauphase gelöscht
- [ ] Domain `vibez-odenwald.de`, Cloudflare-Zone und netcup-Vertrag (dauerhaft auf Murat): Unterauftrag im AV-Vertrag mit VIBEZ genehmigt, Vorgehen bei Ende der Betreuung schriftlich geregelt
- [ ] Cloudflare-Anbindung (MCP) bleibt als begrenzte Ausnahme nach DSFA T12 (Entscheidung 18.11.2026): Benachrichtigung bei DNS-Änderungen eingerichtet, Prüfung des Audit-Logs in die monatliche Wartung aufgenommen
- [ ] Atlas-Service-Account der Aufbauphase gelöscht; nur `prod`, `vibez_backup` und der IP-Listen-Key bleiben; von Murat heruntergeladenes `prod`-Zertifikat auf dem Mac gelöscht
- [ ] GitHub auf dem Server: `gh auth logout` (Anmeldung mit Murats ganzem Konto aus der Aufbauphase entfernt); für das Image nur noch der Fine-grained Token mit *Packages: read* in `docker login ghcr.io`; Repo-Updates mit Token nur *Contents: read*
- [ ] Alle auf dem Server erzeugten Geheimnisse liegen in Bitwarden bzw. im Passwortmanager von VIBEZ (Hilfe: `sudo /root/aufbau/zugaenge-fuer-bitwarden.sh`) (restic-Passwort, Konsolenpasswort, Startpasswort `tobias`)
- [ ] Startpasswort von `tobias` wurde beim ersten Login geändert, 2FA eingerichtet
- [ ] Datenbank enthält keine Testdaten (nur Einstellungen, Jugendämter, Konten)
- [ ] Abnahme-Checkliste in [deployment.md](deployment.md#8-abnahme-und-freigabe) vollständig
- [ ] Ab jetzt gilt wieder: kein KI-Zugriff auf den Echtbetrieb, außer der Cloudflare-Konfiguration nach DSFA T12 (CLAUDE.md)

Datum, Murat: ______________  Datum, Tobias: ______________
