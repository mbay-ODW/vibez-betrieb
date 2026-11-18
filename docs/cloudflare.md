# Cloudflare – Konto, Zone, Tunnel, WAF

Cloudflare steht vor der App: Es beendet TLS für `nachweise.vibez-odenwald.de`, filtert Angriffe und leitet über einen
Tunnel zum Server, der keine offenen Ports hat. Die App hat dafür eine **eigene Domain `vibez-odenwald.de`**
(Entscheidung Murat, 18.11.2026), deren DNS komplett bei Cloudflare liegt. Die Domain von VIBEZ
(`vibez-jugendhilfe.de`, Website und E-Mail bei All-Inkl) bleibt davon unberührt.

## Inhalt

- [Konto und Zugriffe](#konto-und-zugriffe)
- [Domain und Zone einrichten](#domain-und-zone-einrichten)
- [Tunnel und App-Adresse](#tunnel-und-app-adresse)
- [Einstellungen der Zone](#einstellungen-der-zone)
- [WAF-Regeln](#waf-regeln)
- [Ratenbegrenzung](#ratenbegrenzung)
- [Absicherung von Konto und Domain](#absicherung-von-konto-und-domain)
- [Was Cloudflare sieht und speichert](#was-cloudflare-sieht-und-speichert)
- [Nebenbefund vibez-jugendhilfe.de](#nebenbefund-vibez-jugendhilfede)

## Konto und Zugriffe

- **Cloudflare-Konto für den Echtbetrieb** (Free), angelegt mit einer Adresse, auf die VIBEZ Zugriff hat. Wird es von
  Murat angelegt, wird es bei Ende der Betreuung an VIBEZ übergeben ([Betriebshandbuch](betriebshandbuch.md#ende-der-betreuung--übergabe)).
- 2FA mit **Passkey oder Hardwareschlüssel** für alle Mitglieder.
- Tobias wird als **Mitglied** eingeladen (mindestens lesend), damit VIBEZ jederzeit Einblick hat.
- API-Tokens nur mit dem Nötigsten, nur für die Zone `vibez-odenwald.de` und mit Ablaufdatum; **kein Global API Key**.
- Das Data Processing Addendum (DPA) von Cloudflare ist Teil der Self-Serve-Bedingungen, Ablage siehe
  [Dienstleister](../datenschutz/dienstleister.md).

## Domain und Zone einrichten

1. **Domain `vibez-odenwald.de` registrieren.** Als Domaininhaber (DENIC) möglichst **VIBEZ** eintragen, sonst bei Ende
   der Betreuung übertragen. Registrar und Inhaber im [Dienstleisterverzeichnis](../datenschutz/dienstleister.md) eintragen.
2. **In Cloudflare:** *Add a domain* → `vibez-odenwald.de` → Free-Plan. Vorgeschlagene Einträge des Imports löschen
   (die Zone soll leer starten).
3. **Nameserver** beim Registrar auf die zwei von Cloudflare angezeigten Nameserver setzen. Warten, bis Cloudflare
   „Active“ meldet (Minuten bis Stunden).
4. **DNSSEC** in Cloudflare einschalten und den angezeigten DS-Eintrag beim Registrar hinterlegen.
5. **Schutz vor gefälschten Absendern.** Die Domain verschickt und empfängt keine E-Mail. Damit niemand unter ihrem
   Namen Phishing verschickt, diese Einträge anlegen (alle DNS only):

   | Name | Typ | Wert |
   |---|---|---|
   | `@` | MX 0 | `.` (Null-MX nach RFC 7505: keine Mail) |
   | `@` | TXT | `v=spf1 -all` |
   | `_dmarc` | TXT | `v=DMARC1; p=reject; sp=reject; adkim=s; aspf=s;` |
   | `*._domainkey` | TXT | `v=DKIM1; p=` (leerer Schlüssel) |

   Nimmt Cloudflare den Null-MX nicht an, den MX weglassen; SPF und DMARC genügen.

6. **CAA** setzen: `0 issue "letsencrypt.org"` und `0 issue "pki.goog"` (die zwei Zertifizierungsstellen von Universal
   SSL, Stand 18.11.2026). Cloudflare ergänzt bei Bedarf weitere eigene CAs selbst.
7. Für `nachweise` **keinen** Eintrag von Hand anlegen; den erzeugt der Tunnel (nächster Abschnitt).
8. Optional: `@` und `www` als Weiterleitung auf `https://nachweise.vibez-odenwald.de` (Redirect Rule) oder leer lassen.

## Tunnel und App-Adresse

Lokal verwalteter Tunnel. Die Konfiguration liegt im Repo ([`config/cloudflared/config.yml`](../config/cloudflared/config.yml)),
die Zugangsdaten (`credentials.json`) nur auf dem Server.

```bash
cloudflared tunnel login                     # Browser: Zone vibez-odenwald.de auswählen
cloudflared tunnel create vibez-prod         # erzeugt <TUNNEL-ID>.json
cloudflared tunnel route dns vibez-prod nachweise.vibez-odenwald.de
```

- `route dns` legt `nachweise` als **proxied CNAME** auf `<TUNNEL-ID>.cfargotunnel.com` an. Das ist der einzige
  proxied Eintrag der Zone (außer einer optionalen Weiterleitung von `@`/`www`).
- Das Zertifikat für `nachweise.vibez-odenwald.de` stellt Cloudflare automatisch aus (Universal SSL).
- `<TUNNEL-ID>.json` wird zu `/srv/vibez/secrets/cloudflared/credentials.json` (400, UID 65532). `cert.pem` aus `tunnel login`
  wird nach dem Anlegen gelöscht.

## Einstellungen der Zone

| Bereich | Einstellung | Wert | Grund |
|---|---|---|---|
| SSL/TLS | Encryption mode | Full (strict) | gilt nur für proxied Einträge, also nur die App |
| SSL/TLS → Edge Certificates | Always Use HTTPS | an | |
| | Minimum TLS Version | 1.2 | |
| | TLS 1.3 | an | |
| | HSTS | aus (setzt Traefik für die App) | eine Stelle genügt; vermeidet widersprüchliche Werte |
| Security | Browser Integrity Check | an | |
| | Bot Fight Mode | **aus** | keine JS-Challenges auf Diensthandys; Bots blockt Regel 3 |
| | Block AI Scrapers and Crawlers | an | |
| | Managed Ruleset (Free) | an | |
| Scrape Shield | Email Address Obfuscation | **aus** | würde Skripte einfügen und damit die CSP der App verletzen |
| Speed | Rocket Loader | **aus** | aus demselben Grund |
| Analytics | Web Analytics (RUM) | **aus** | kein Tracking, kein eingefügtes Skript |
| Caching → Cache Rules | „App nie cachen“: Hostname = `nachweise.vibez-odenwald.de` und Pfad beginnt **nicht** mit `/static/` → **Bypass cache** | | Seiten mit Sozialdaten dürfen nie im CDN liegen |

Die Einstellungen wirken nur auf **proxied** Einträge, also auf die App.

## WAF-Regeln

**Security → Security rules → Custom rules** (Free: 5 Regeln). Regeln 2 und 4 gelten nur für die App (Portainer und LLDAP brauchen `/api/` und `PUT`/`DELETE`), 1, 3 und 5 für alle Adressen (Stand 18.11.2026, Version 4 des Regelsatzes).

| Nr. | Name | Ausdruck | Aktion |
|---|---|---|---|
| 1 | Nur EU und Schweiz (alle Adressen) | `(not ip.src.country in {"AT" "BE" "BG" "CH" "CY" "CZ" "DE" "DK" "EE" "ES" "FI" "FR" "GR" "HR" "HU" "IE" "IT" "LI" "LT" "LU" "LV" "MT" "NL" "PL" "PT" "RO" "SE" "SI" "SK"})` | Block |
| 2 | Scanner-Pfade | `(http.host eq "nachweise.vibez-odenwald.de" and (http.request.uri.path contains "/." or http.request.uri.path contains ".php" or http.request.uri.path contains "wp-" or http.request.uri.path contains "xmlrpc" or http.request.uri.path contains "phpmyadmin" or http.request.uri.path contains "cgi-bin" or http.request.uri.path contains "/admin" or http.request.uri.path contains "/api/"))` | Block |
| 3 | Bekannte Bots (alle Adressen) | `(cf.client.bot)` | Block |
| 4 | Nur übliche Methoden | `(http.host eq "nachweise.vibez-odenwald.de" and not http.request.method in {"GET" "HEAD" "POST"})` | Block |
| 5 | Unbekannte proxied Hosts | `(not http.host in {"nachweise.vibez-odenwald.de" "auth.vibez-odenwald.de" "ldap.vibez-odenwald.de" "portainer.vibez-odenwald.de" "logs.vibez-odenwald.de" "status.vibez-odenwald.de"})` | Block |

Regel 5 sperrt alle anderen Namen der Zone, die über Cloudflare laufen. Wird `@`/`www` als Weiterleitung genutzt,
Regel 5 auf `not http.host in {"nachweise.vibez-odenwald.de" "vibez-odenwald.de" "www.vibez-odenwald.de"}` erweitern.

## Ratenbegrenzung

**Security → Security rules → Rate limiting rules** (Free: 1 Regel, Zeitraum 10 s):

| Name | Ausdruck | Zählung | Grenze | Aktion |
|---|---|---|---|---|
| Anmeldung bremsen | `(http.host eq "nachweise.vibez-odenwald.de" and http.request.uri.path in {"/login" "/login/code"} and http.request.method eq "POST")` | je IP | 5 Anfragen / 10 s | Block für 10 s |

Dazu kommen die Bremsen in der App (je Konto und je IP) und in Traefik.

## Absicherung von Konto und Domain

- **Benachrichtigungen** (Cloudflare → Notifications): Tunnel-Status, DNS-Änderungen, neue Mitglieder. Ein unerwarteter
  **zweiter Connector** am Tunnel deutet auf gestohlene Zugangsdaten hin: dann sofort einen neuen Tunnel erzeugen.
- **Registrar-Konto** mit 2FA und Registrar-Sperre (Transfer Lock): Dort lassen sich die Nameserver ändern und damit die
  App umleiten.
- **Ablauf der Domain** im Kalender vermerken, automatische Verlängerung an. Eine verfallene Domain wäre ein Totalausfall.
- **DNSSEC** an (Schritt 4 oben), **CAA** gesetzt, Mail-Schutz-Einträge (Schritt 5).
- **Zertifikatstransparenz**: kostenlose Überwachung (Cloudflare *Certificate Transparency Monitoring* oder Cert Spotter)
  für `vibez-odenwald.de`.

## Was Cloudflare sieht und speichert

- Für die **App** entschlüsselt Cloudflare den Datenverkehr am Rand seines Netzes. Inhalte liegen dort kurzzeitig im
  Arbeitsspeicher. Die Cache-Regel verhindert, dass Seiten gespeichert werden.
- Im Free-Tarif ist die TLS-Terminierung nicht auf EU-Rechenzentren beschränkt (Regional Services: Enterprise). In der
  Praxis bedient das nächstgelegene Rechenzentrum, für Hessen meist Frankfurt.
- Metadaten (IP, Land, Pfad, Zeitpunkt, Regel-Treffer) speichert Cloudflare für begrenzte Zeit in Security-Events.
- Bewertung: [Datenschutz-Folgenabschätzung, R5](../datenschutz/dsfa.md).

## Nebenbefund vibez-jugendhilfe.de

Nicht Teil der App, beim Prüfen am 16.11.2026 aufgefallen (DNS bei All-Inkl, E-Mail bei Microsoft 365): Die DKIM-Einträge
für Microsoft 365 (`selector1._domainkey`, `selector2._domainkey`) fehlen, und DMARC steht auf `p=none`. Empfehlung an
VIBEZ: DKIM im Microsoft-Defender-Portal aktivieren, die zwei CNAMEs bei All-Inkl anlegen, danach DMARC schrittweise auf
`p=quarantine`.
