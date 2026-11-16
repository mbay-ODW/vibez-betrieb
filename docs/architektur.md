# Betriebsarchitektur – Echtbetrieb VIBEZ Nachweise

Stand: 15.11.2026 · gilt für den Echtbetrieb mit echten Klientendaten. Die Demo unter `vibez.bay-ram.de` läuft getrennt davon
auf dem Server von Murat und enthält nur erfundene Daten.

## Inhalt

- [Entscheidungen auf einen Blick](#entscheidungen-auf-einen-blick)
- [Gesamtbild](#gesamtbild)
- [Weg einer Anfrage](#weg-einer-anfrage)
- [Komponenten](#komponenten)
- [Netze und Erreichbarkeit](#netze-und-erreichbarkeit)
- [Domain und DNS](#domain-und-dns)
- [Daten, Backup und Wiederherstellung](#daten-backup-und-wiederherstellung)
- [Verwaltungszugang](#verwaltungszugang)
- [Überwachung](#überwachung)
- [Atlas-Einrichtung (wie DRK)](#atlas-einrichtung-wie-drk)
- [Kosten (Größenordnung)](#kosten-größenordnung)

## Entscheidungen auf einen Blick

| Thema | Entscheidung | Begründung |
|---|---|---|
| Server | Eigener VPS bei **netcup** (VPS Lite 1 G12.5s), Rechenzentrum **Nürnberg**, **Vertragspartner VIBEZ** | Klare Trennung von anderen Systemen, deutscher Anbieter mit AV-Vertrag und ISO 27001, VIBEZ bleibt Herr der Daten |
| Betrieb | Murat Bayram als IT-Dienstleister (Auftragsverarbeiter, Verschwiegenheit nach § 203 StGB) | Betreuung wie bisher, aber auf VIBEZ-eigener Infrastruktur |
| Adresse | `nachweise.vibez-jugendhilfe.de` (Name noch bestätigen) | Eigene Domain von VIBEZ; Registrierung, Website und E-Mail bleiben bei **All-Inkl**, die **DNS-Verwaltung zieht zu Cloudflare** |
| Schutz vor dem Server | **Cloudflare** (Free) als Proxy mit WAF, nur für `nachweise` | Geo-Block, Schutz vor Angriffen und Scannern, Server ohne offene Ports |
| Anbindung Server | **Cloudflare Tunnel** (`cloudflared`) | Keine eingehenden Ports, Server-IP bleibt verborgen |
| Reverse Proxy | **Traefik** v3 | Routing, Ratenbremse je echter IP, HSTS, Zugriffsprotokoll |
| Datenbank | **MongoDB Atlas**, Region **AWS Frankfurt (eu-central-1)**, Projekt nur für VIBEZ | Wie bei der DRK-Klientendokumentation: verschlüsselt gespeichert, repliziert, verwaltete Backups; Zugriff nur von der IP des VPS (per Atlas-API gepflegt) |
| Backup | **Atlas Cloud Backup** + zweite, unabhängige Kopie mit **restic** (verschlüsselt) auf einer **Hetzner Storage Box** | Zwei Anbieter, zwei Standorte; monatlicher Wiederherstellungstest |
| Verwaltung | SSH nur über **Tailscale**, keine öffentlichen Ports | Angriffsfläche minimal |
| Versionen | App-Image mit fester Versionsnummer (`VERSION` im App-Repo), Ausrollen mit `deploy.sh` | Nachvollziehbar, Rückweg möglich |

## Gesamtbild

```mermaid
flowchart LR
    subgraph Nutzer["Nutzer:innen"]
      H["Handy Pädagog:in"]
      P["PC Verwaltung"]
    end
    subgraph AI["All-Inkl (Registrar, Website, E-Mail)"]
      D["Nameserver → Cloudflare"]
    end
    subgraph CF["Cloudflare-Konto VIBEZ (Free)"]
      Z["Zone vibez-jugendhilfe.de<br/>nachweise: proxied, Rest: DNS only"]
      W["WAF: Geo-Block, Scanner, Ratenlimit<br/>TLS-Zertifikat für nachweise.…"]
      TU["Tunnel vibez-prod"]
    end
    subgraph HZ["netcup Nürnberg + Hetzner Storage Box (Verträge VIBEZ)"]
      subgraph VPS["VPS vibez-prod – keine offenen Ports"]
        CD["cloudflared"]
        TR["Traefik"]
        APP["App vibez-nachweise"]
      end
      SB[("Storage Box<br/>restic, verschlüsselt")]
    end
    subgraph AT["MongoDB Atlas, AWS Frankfurt (Vertrag VIBEZ)"]
      DB[("Cluster vibez<br/>IP-Liste: nur VPS")]
      AB[("Cloud Backup")]
    end
    ADM["Murat (Admin)"] -. "Tailscale SSH" .-> VPS
    H & P -- "HTTPS" --> W
    D -. "delegiert" .-> Z
    W --> Z --> TU
    TU <== "ausgehend aufgebaut" ==> CD
    CD --> TR --> APP -- "TLS, Benutzer vibez_app" --> DB
    DB --- AB
    DB -. "nachts mongodump (vibez_backup)" .-> SB
```

## Weg einer Anfrage

1. Das Handy fragt `nachweise.vibez-jugendhilfe.de` an. Die Nameserver von Cloudflare antworten mit einer
   Cloudflare-Adresse (proxied Eintrag).
2. Cloudflare beendet TLS mit einem eigenen Zertifikat für `nachweise.vibez-jugendhilfe.de` und prüft die Anfrage (WAF,
   Geo-Block EU/CH, Ratenlimit, Managed Rules).
3. Cloudflare schickt die Anfrage durch den **Tunnel** zu `cloudflared` auf dem Server. Diese Verbindung hat `cloudflared`
   von innen aufgebaut; am Server ist kein Port offen.
4. `cloudflared` gibt die Anfrage an **Traefik** weiter (internes Netz). Traefik prüft den Hostnamen, begrenzt die Rate je
   echter IP (`Cf-Connecting-Ip`), setzt HSTS und protokolliert Metadaten.
5. Traefik leitet an die **App** weiter. Sie prüft Anmeldung, Rolle und CSRF und setzt eigene Sicherheits-Header (CSP u. a.).
6. Die App liest und schreibt in **MongoDB Atlas** (Frankfurt), verschlüsselt per TLS. Atlas nimmt Verbindungen nur von
   der festen IPv4 des VPS an (IP-Zugriffsliste) und nur mit dem Benutzer `vibez_app`, der ausschließlich die Datenbank
   `vibez` lesen und schreiben darf.

## Komponenten

| Container | Image (fest) | Netz | Aufgabe | Härtung |
|---|---|---|---|---|
| `vibez-cloudflared` | `cloudflare/cloudflared:2026.10.7` | edge | Tunnel zu Cloudflare | read-only, no-new-privileges, 128 MB |
| `vibez-traefik` | `traefik:v3.7.17` | edge, web | Reverse Proxy | read-only, kein Dashboard, keine Docker-Socket-Anbindung (nur Datei-Konfiguration) |
| `vibez-app` | `ghcr.io/mbay-odw/vibez-nachweise:<VERSION>` | web, atlas | Anwendung | read-only, unprivilegierter Benutzer, ausgehend nur zu Atlas nötig |
| (Atlas) | MongoDB 7, dediziert empfohlen | – | Datenbank | TLS, IP-Zugriffsliste, getrennte Benutzer (App: `readWrite` auf `vibez`; Backup: `backup`), Verschlüsselung ruhender Daten |

Konfiguration: [`stack/compose.yml`](../stack/compose.yml), [`stack/traefik/`](../stack/traefik/),
[`stack/cloudflared/config.yml`](../stack/cloudflared/config.yml). Geheimnisse stehen ausschließlich in `stack/.env` und
`stack/cloudflared/credentials.json` auf dem Server (nicht im Repo).

## Netze und Erreichbarkeit

| Von → nach | Erlaubt | Wie erzwungen |
|---|---|---|
| Internet → Server | **nichts** | `ufw deny incoming`, keine veröffentlichten Docker-Ports |
| Cloudflare → App | nur über den Tunnel | `cloudflared` baut ausgehend auf |
| cloudflared → Traefik | HTTP im Netz `edge` | Traefik vertraut `X-Forwarded-*` nur aus `172.30.0.0/24` |
| Traefik → App | HTTP im Netz `web` (intern) | Docker-Netz `internal: true` |
| App → MongoDB Atlas | TLS über das Netz `atlas` | Atlas-IP-Zugriffsliste = nur VPS-IPv4; Benutzer mit Passwort (SCRAM) |
| Traefik → Internet | **nichts** | Traefik hängt nur an `edge` (für cloudflared) und `web` (intern) |
| Admin → Server | SSH nur über Tailscale, nur Schlüssel | `ufw allow in on tailscale0 port 22`, `PasswordAuthentication no`, `PermitRootLogin no` |
| Server → Internet | ausgehend (Updates, Tunnel, Backup, Image-Download) | – |

## Domain und DNS

Cloudflare verwaltet die **DNS der ganzen Domain** `vibez-jugendhilfe.de` (Entscheidung 16.11.2026). Domain-Registrierung,
Website und E-Mail bleiben bei All-Inkl. Bei All-Inkl zeigen nur die Nameserver auf Cloudflare, und alle bisherigen
Einträge werden in Cloudflare 1:1 als **„DNS only“** übernommen. Damit laufen Website und E-Mail weiterhin direkt zu
All-Inkl, ohne Cloudflare-Proxy.

| Wo | Eintrag | Zweck |
|---|---|---|
| All-Inkl (Registrar) | Nameserver von `vibez-jugendhilfe.de` → die zwei Cloudflare-Nameserver | Cloudflare beantwortet die DNS |
| Cloudflare, Zone `vibez-jugendhilfe.de` | alle bisherigen Einträge (Website, MX, SPF, DKIM, DMARC, Autodiscover …), **DNS only** | Website und E-Mail unverändert |
| Cloudflare | `nachweise` CNAME → `<TUNNEL-ID>.cfargotunnel.com`, **proxied** (legt `cloudflared tunnel route dns` an) | App über Tunnel, WAF und TLS |

Fakten (geprüft 15./16.11.2026):

- Universal SSL stellt das Zertifikat für `nachweise.vibez-jugendhilfe.de` automatisch aus (Free).
- WAF-Regeln, Ratenlimit und Zoneneinstellungen wirken nur auf proxied Einträge, also nur auf die App.
- **Regional Services** (TLS-Terminierung nur in EU-Rechenzentren) sind ein Enterprise-Zusatz. Im Free-Tarif kann die
  Entschlüsselung in jedem Cloudflare-Rechenzentrum stattfinden (in der Praxis das nächstgelegene, für Hessen meist
  Frankfurt). Bewertet in der [Datenschutz-Folgenabschätzung](../datenschutz/dsfa.md).
- Wichtig beim Umzug: DNSSEC vorher ausschalten, alle Mail-Einträge übernehmen, danach Mailversand und -empfang testen.

Das Cloudflare-Konto gehört VIBEZ. Kündigt VIBEZ die Betreuung, nimmt es Konten (Cloudflare, netcup, Hetzner, Atlas),
Server und Domain einfach mit.

Details und Regeln: [cloudflare.md](cloudflare.md).

## Daten, Backup und Wiederherstellung

| Was | Wo | Schutz |
|---|---|---|
| Datenbank | MongoDB Atlas, AWS Frankfurt (eu-central-1) | TLS, IP-Zugriffsliste, Benutzer je Zweck, Verschlüsselung ruhender Daten durch Atlas |
| Backup 1 | Atlas Cloud Backup (Snapshots, je nach Tarif Point-in-Time) | in Atlas, Region Frankfurt |
| Backup 2 | Hetzner Storage Box (DE) | `mongodump` mit Lese-Benutzer → **restic-Verschlüsselung (AES-256) auf dem VPS**; Hetzner sieht nur verschlüsselte Blöcke |
| restic-Passwort | `.env` auf dem Server **und** offline im Passwortmanager von VIBEZ | ohne Passwort keine Wiederherstellung – beide Kopien sind Pflicht |
| Zugriffsprotokoll Traefik | `/opt/vibez/stack/logs/traefik` | 14 Tage, nur Metadaten (IP, Land, Pfad, Status) |
| Änderungsprotokoll der App | in der Datenbank (`audit`) | Teil beider Backups |

Ablauf Backup 2: `vibez-backup.timer` jede Nacht um 02:30 Uhr → `mongodump` aus Atlas mit dem Backup-Benutzer →
`restic backup` → `restic forget` (7 tägliche, 5 wöchentliche, 12 monatliche Stände) → Meldung an Uptime Kuma. Sonntags
werden 10 % der Daten gegengelesen. Am 1. jedes Monats spielt `vibez-restoretest.timer` den neuesten Stand in eine
**Wegwerf-MongoDB ohne Netz** auf dem VPS ein, zählt Nachweise und Rechnungen und löscht sie wieder.

Wiederherstellungsziele: **RPO** ≤ 24 Stunden (bei Atlas mit Point-in-Time deutlich weniger), **RTO** ≤ 1 Arbeitstag
(neuer Server nach [Deployment](deployment.md), Datenbank bleibt in Atlas).

## Verwaltungszugang

- Nur Murat (Admin) hat SSH-Zugang: persönliches Konto, nur Schlüssel, nur über Tailscale (mit 2FA am Tailscale-Konto).
- Notzugang über die netcup-Konsole (SCP) mit dem Passwort des Admin-Kontos. Das Passwort liegt im Passwortmanager von VIBEZ.
- Die Konten bei netcup und Hetzner gehören VIBEZ. 2FA ist Pflicht; Murat bekommt eigene Zugänge, kein geteiltes Login.
- **Aufbauphase:** Nur solange keine echten Daten vorhanden sind, richtet eine KI-Sitzung den Server über Remote Control ein.
  Danach wird dieser Zugang vollständig entfernt ([aufbau.md](aufbau.md)).
- **Keine KI-/Automations-Zugänge zum Echtbetrieb:** Der VPS wird **nicht** in Portainer, MCP-Server oder andere
  Werkzeuge eingebunden, über die KI-Assistenten Befehle ausführen oder Daten lesen könnten. Entwicklung und Tests laufen
  ausschließlich mit der Demo und erfundenen Daten.
- Jede Wartung mit Datenbankzugriff wird im Wartungsprotokoll vermerkt ([Betriebshandbuch](betriebshandbuch.md#wartungsprotokoll)).

## Überwachung

| Prüfung | Werkzeug | Meldung |
|---|---|---|
| `https://nachweise.vibez-jugendhilfe.de/health` alle 60 s (HTTP-Monitor) | Uptime Kuma (bestehend, bei Murat) | ntfy an Murat |
| Backup-Heartbeat (Push-Monitor, 26 h) | Uptime Kuma | ntfy an Murat |
| Zertifikat `nachweise` | Cloudflare (automatische Verlängerung) + Uptime-Kuma-Zertifikatsprüfung | ntfy |
| Sicherheitsupdates Betriebssystem | `unattended-upgrades` mit Neustart 04:15 Uhr bei Bedarf | – |
| Container-Updates | monatlich manuell (Betriebshandbuch) | – |

Uptime Kuma sieht nur die öffentliche Health-Adresse (Antwort `{"ok": true}`), keine Inhalte.

## Atlas-Einrichtung (wie DRK)

| Einstellung | Wert |
|---|---|
| Organisation / Projekt | eigenes Projekt „VIBEZ Nachweise“; Organisation von VIBEZ (Murat als Projektmitglied mit 2FA) |
| Region | AWS **eu-central-1 (Frankfurt)** |
| Tarif | **dedizierter Cluster (M10)** empfohlen: Cloud Backup mit Point-in-Time, eigene Verschlüsselungsschlüssel möglich. Flex nur, wenn dessen Backup-Umfang laut aktuellem Preisblatt reicht |
| Netzwerkzugang | IP-Zugriffsliste **nur** die öffentliche IPv4 des VPS, gepflegt mit [`host/atlas-zugriffsliste.sh`](../host/atlas-zugriffsliste.sh) (Atlas Admin API); kein `0.0.0.0/0` |
| Datenbank-Benutzer | `vibez_app` (readWrite auf `vibez`), `vibez_backup` (Rolle `backup`); Admin-Rechte nur befristet für Wartung |
| Backup | Cloud Backup an, Aufbewahrung mindestens 7 Tage täglich + 4 Wochen + 12 Monate (an Backup 2 angleichen) |
| Benachrichtigungen | Atlas-Alerts (Verbindungen, Speicher, Backup fehlgeschlagen) an Murat |
| AV-Vertrag | MongoDB-DPA (Bestandteil der Atlas-Bedingungen) für VIBEZ dokumentieren, Region und Unterauftragnehmer (AWS) festhalten |

Alternative ohne Atlas: MongoDB als Container auf dem VPS (internes Netz, `--auth`). Dann entfallen MongoDB Inc. und AWS
als Auftragsverarbeiter; dafür liegen Verschlüsselung ruhender Daten und Backup vollständig in eigener Verantwortung.

## Kosten (Größenordnung)

| Posten | Größenordnung | Bemerkung |
|---|---|---|
| netcup VPS Lite 1 G12.5s (2 vCore, 4 GB, 80 GB, Nürnberg) | 5,86 € / Monat inkl. MwSt. (Angebot 16.11.2026) | 6 Monate Mindestlaufzeit |
| MongoDB Atlas (dediziert M10, Frankfurt) | mittlerer zweistelliger €-Betrag / Monat | Flex günstiger; aktuelles Preisblatt prüfen |
| Hetzner Storage Box (kleinste Größe) | wenige € / Monat | zweite Sicherung |
| Cloudflare Free | 0 € | |
| Tailscale (Personal/Starter) | 0 € | nur Admin-Zugang |
