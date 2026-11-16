# Cloudflare – Konto, Zone, Tunnel, WAF

Cloudflare steht vor der App: Es beendet TLS für `nachweise.vibez-jugendhilfe.de`, filtert Angriffe und leitet über einen
Tunnel zum Server, der keine offenen Ports hat. Dafür verwaltet Cloudflare die **DNS der ganzen Domain**
`vibez-jugendhilfe.de` (Entscheidung Murat, 16.11.2026). Domain, Website und E-Mail bleiben bei All-Inkl. Nur die
Nameserver zeigen auf Cloudflare, und alle bisherigen DNS-Einträge werden dort 1:1 übernommen.

## Inhalt

- [Konto und Zugriffe](#konto-und-zugriffe)
- [Domain zu Cloudflare umziehen](#domain-zu-cloudflare-umziehen)
- [Tunnel und App-Adresse](#tunnel-und-app-adresse)
- [Einstellungen der Zone](#einstellungen-der-zone)
- [WAF-Regeln](#waf-regeln)
- [Ratenbegrenzung](#ratenbegrenzung)
- [Absicherung von Konto und Domain](#absicherung-von-konto-und-domain)
- [Was Cloudflare sieht und speichert](#was-cloudflare-sieht-und-speichert)

## Konto und Zugriffe

- **Eigenes Cloudflare-Konto für VIBEZ** (Free). Inhaber ist eine VIBEZ-Adresse, nicht Murats Konto.
- 2FA mit **Passkey oder Hardwareschlüssel** für alle Mitglieder. Wer dieses Konto übernimmt, kann jetzt auch Website
  und E-Mail umleiten.
- Murat wird als **Mitglied** eingeladen (Rolle „Administrator“).
- API-Tokens nur mit dem Nötigsten und mit Ablaufdatum; **kein Global API Key**.
- Das Data Processing Addendum (DPA) von Cloudflare ist Teil der Self-Serve-Bedingungen, Ablage siehe
  [Dienstleister](../datenschutz/dienstleister.md).

## Domain zu Cloudflare umziehen

Ziel: Am Verhalten von Website und E-Mail ändert sich **nichts**. Nur der Ort, an dem die DNS-Einträge gepflegt werden,
wandert zu Cloudflare.

1. **Bestand sichern.** In der All-Inkl-Verwaltung (KAS → DNS-Einstellungen für `vibez-jugendhilfe.de`) alle Einträge
   abfotografieren oder exportieren. Typisch sind:
   - `A` / `AAAA` für `@` und `www` (Website)
   - `MX` (E-Mail-Server)
   - `TXT` mit `v=spf1 …` (SPF)
   - `TXT` unter `…._domainkey` (DKIM von All-Inkl)
   - `TXT` unter `_dmarc` (falls vorhanden)
   - `CNAME`/`SRV` für `autoconfig`, `autodiscover`, `_imaps._tcp`, `_submission._tcp` (Mail-Einrichtung)
   - Bestätigungs-`TXT` anderer Dienste (z. B. Google, Microsoft, Apple)
   **Bestand am 16.11.2026** (KAS, 7 Einträge): Website bei **Webflow**, E-Mail bei **Microsoft 365**.

   | Name | Typ | Wert | In Cloudflare |
   |---|---|---|---|
   | `@` | A | `198.202.211.1` (Webflow) | DNS only – Pflicht bei Webflow |
   | `www` | CNAME | `cdn.webflow.com` | DNS only – Pflicht bei Webflow |
   | `@` | MX 0 | `vibezjugendhilfe-de01c.mail.protection.outlook.com` | DNS only |
   | `@` | TXT | `MS=ms32462337` (Microsoft-Domainnachweis) | DNS only |
   | `@` | TXT | `v=spf1 include:spf.protection.outlook.com -all` | DNS only |
   | `_dmarc` | TXT | `v=DMARC1; p=none;` | DNS only |
   | `kas202606290135._domainkey` | TXT | DKIM-Schlüssel von All-Inkl (für Microsoft 365 nicht genutzt) | übernehmen, schadet nicht |

   Am einfachsten: bei All-Inkl **„Export als BIND-Zonefile“**, in Cloudflare unter *DNS → Records → Import* hochladen,
   danach jede Zeile prüfen und alle Wolken auf grau stellen.

   Nebenbefund (nicht Teil der App): Für Microsoft 365 fehlen die DKIM-Einträge (`selector1._domainkey`,
   `selector2._domainkey`) und DMARC steht auf `p=none`. Empfehlung: DKIM im Microsoft-Defender-Portal aktivieren,
   danach DMARC schrittweise auf `p=quarantine`.
2. **DNSSEC** prüfen: Ist es bei All-Inkl aktiv, **vorher ausschalten**. Sonst ist die Domain nach dem Umstellen nicht
   erreichbar. Nach dem Umzug kann DNSSEC in Cloudflare neu eingeschaltet werden; den DS-Eintrag setzt dann All-Inkl.
3. **In Cloudflare:** *Add a domain* → `vibez-jugendhilfe.de` → Free-Plan. Cloudflare liest die vorhandenen Einträge ein.
4. **Abgleichen.** Jeden Eintrag aus Schritt 1 in Cloudflare finden, fehlende ergänzen.
   - **Alle bisherigen Einträge auf „DNS only“ (graue Wolke)** stellen, nicht „Proxied“. Website und E-Mail laufen dann
     genau wie vorher direkt zu All-Inkl. Insbesondere `MX`, Mail-Hosts und `www` nie proxien.
   - Für `nachweise` **keinen** Eintrag anlegen; den erzeugt der Tunnel (nächster Abschnitt).
5. **Nameserver umstellen.** Im All-Inkl-Kundenbereich bei der Domain `vibez-jugendhilfe.de` die Nameserver auf die
   beiden von Cloudflare angezeigten Nameserver ändern. Die Domain bleibt bei All-Inkl registriert; es ändert sich nur,
   wer die DNS beantwortet.
6. **Warten und prüfen.** Cloudflare meldet nach Minuten bis Stunden „Active“. Danach Website aufrufen und eine E-Mail
   **senden und empfangen** (auch von einer externen Adresse an VIBEZ).

Rückweg bei Problemen: Nameserver bei All-Inkl wieder auf die All-Inkl-Nameserver stellen. Die alten Einträge liegen dort
noch.

## Tunnel und App-Adresse

Lokal verwalteter Tunnel. Die Konfiguration liegt im Repo ([`stack/cloudflared/config.yml`](../stack/cloudflared/config.yml)),
die Zugangsdaten (`credentials.json`) nur auf dem Server.

```bash
cloudflared tunnel login                     # Browser: Zone vibez-jugendhilfe.de auswählen
cloudflared tunnel create vibez-prod         # erzeugt <TUNNEL-ID>.json
cloudflared tunnel route dns vibez-prod nachweise.vibez-jugendhilfe.de
```

- `route dns` legt `nachweise` als **proxied CNAME** auf `<TUNNEL-ID>.cfargotunnel.com` an. Das ist der einzige
  proxied Eintrag der Zone.
- Das Zertifikat für `nachweise.vibez-jugendhilfe.de` stellt Cloudflare automatisch aus (Universal SSL).
- `<TUNNEL-ID>.json` wird zu `/opt/vibez/stack/cloudflared/credentials.json` (chmod 600). `cert.pem` aus `tunnel login`
  wird nach dem Anlegen gelöscht.

## Einstellungen der Zone

| Bereich | Einstellung | Wert | Grund |
|---|---|---|---|
| SSL/TLS | Encryption mode | Full (strict) | gilt nur für proxied Einträge, also nur die App |
| SSL/TLS → Edge Certificates | Always Use HTTPS | an | |
| | Minimum TLS Version | 1.2 | |
| | TLS 1.3 | an | |
| | HSTS | aus (setzt Traefik nur für die App) | Website bei All-Inkl nicht beeinflussen |
| Security | Browser Integrity Check | an | |
| | Bot Fight Mode | **aus** | keine JS-Challenges auf Diensthandys; Bots blockt Regel 3 |
| | Block AI Scrapers and Crawlers | an | |
| | Managed Ruleset (Free) | an | |
| Scrape Shield | Email Address Obfuscation | **aus** | würde Skripte einfügen und damit die CSP der App verletzen |
| Speed | Rocket Loader | **aus** | aus demselben Grund |
| Analytics | Web Analytics (RUM) | **aus** | kein Tracking, kein eingefügtes Skript |
| Caching → Cache Rules | „App nie cachen“: Hostname = `nachweise.vibez-jugendhilfe.de` und Pfad beginnt **nicht** mit `/static/` → **Bypass cache** | | Seiten mit Sozialdaten dürfen nie im CDN liegen |

Die Einstellungen wirken nur auf **proxied** Einträge. Website und E-Mail (DNS only) sind davon nicht betroffen.

## WAF-Regeln

**Security → Security rules → Custom rules** (Free: 5 Regeln). Alle Regeln sind auf die App-Adresse beschränkt.

| Nr. | Name | Ausdruck | Aktion |
|---|---|---|---|
| 1 | Nur EU und Schweiz | `(http.host eq "nachweise.vibez-jugendhilfe.de" and not ip.src.country in {"AT" "BE" "BG" "CH" "CY" "CZ" "DE" "DK" "EE" "ES" "FI" "FR" "GR" "HR" "HU" "IE" "IT" "LI" "LT" "LU" "LV" "MT" "NL" "PL" "PT" "RO" "SE" "SI" "SK"})` | Block |
| 2 | Scanner-Pfade | `(http.host eq "nachweise.vibez-jugendhilfe.de" and (http.request.uri.path contains "/." or http.request.uri.path contains ".php" or http.request.uri.path contains "wp-" or http.request.uri.path contains "xmlrpc" or http.request.uri.path contains "phpmyadmin" or http.request.uri.path contains "cgi-bin" or http.request.uri.path contains "/admin" or http.request.uri.path contains "/api/"))` | Block |
| 3 | Bekannte Bots | `(http.host eq "nachweise.vibez-jugendhilfe.de" and cf.client.bot)` | Block |
| 4 | Nur übliche Methoden | `(http.host eq "nachweise.vibez-jugendhilfe.de" and not http.request.method in {"GET" "HEAD" "POST"})` | Block |
| 5 | Unbekannte proxied Hosts | `(http.host ne "nachweise.vibez-jugendhilfe.de")` | Block |

Regel 5 greift nur, falls versehentlich ein anderer Eintrag auf „Proxied“ gestellt wird. Website und Mail laufen als
„DNS only“ ohnehin nicht über Cloudflare.

## Ratenbegrenzung

**Security → Security rules → Rate limiting rules** (Free: 1 Regel, Zeitraum 10 s):

| Name | Ausdruck | Zählung | Grenze | Aktion |
|---|---|---|---|---|
| Anmeldung bremsen | `(http.host eq "nachweise.vibez-jugendhilfe.de" and http.request.uri.path in {"/login" "/login/code"} and http.request.method eq "POST")` | je IP | 5 Anfragen / 10 s | Block für 10 s |

Dazu kommen die Bremsen in der App (je Konto und je IP) und in Traefik.

## Absicherung von Konto und Domain

- **Benachrichtigungen** (Cloudflare → Notifications): Tunnel-Status, DNS-Änderungen, neue Mitglieder. Ein unerwarteter
  **zweiter Connector** am Tunnel deutet auf gestohlene Zugangsdaten hin: dann sofort einen neuen Tunnel erzeugen.
- **All-Inkl-Konto** mit 2FA: Dort lassen sich die Nameserver zurückstellen und damit alles umleiten.
- **DNSSEC** nach dem Umzug in Cloudflare aktivieren und den DS-Eintrag bei All-Inkl setzen lassen.
- **CAA**: nur die Zertifizierungsstellen erlauben, die Cloudflare (Universal SSL) und die Website bei All-Inkl nutzen.
  Cloudflare ergänzt seine CAs automatisch, sobald ein CAA-Eintrag existiert. Vor dem Setzen die aktuelle Doku prüfen.
- **Zertifikatstransparenz**: kostenlose Überwachung (Cloudflare *Certificate Transparency Monitoring* oder Cert Spotter)
  für `vibez-jugendhilfe.de`.

## Was Cloudflare sieht und speichert

- Für die **App** entschlüsselt Cloudflare den Datenverkehr am Rand seines Netzes. Inhalte liegen dort kurzzeitig im
  Arbeitsspeicher. Die Cache-Regel verhindert, dass Seiten gespeichert werden.
- Im Free-Tarif ist die TLS-Terminierung nicht auf EU-Rechenzentren beschränkt (Regional Services: Enterprise). In der
  Praxis bedient das nächstgelegene Rechenzentrum, für Hessen meist Frankfurt.
- Für **Website und E-Mail** beantwortet Cloudflare nur DNS-Anfragen. Inhalte laufen weiter direkt zu All-Inkl.
- Metadaten (IP, Land, Pfad, Zeitpunkt, Regel-Treffer) speichert Cloudflare für begrenzte Zeit in Security-Events.
- Bewertung: [Datenschutz-Folgenabschätzung, R5](../datenschutz/dsfa.md).
