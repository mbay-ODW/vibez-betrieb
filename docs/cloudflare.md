# Cloudflare – Konto, Hilfszone, Tunnel, WAF

Cloudflare steht vor der App: Es beendet TLS für `nachweise.vibez-jugendhilfe.de`, filtert Angriffe und leitet über einen
Tunnel zum Server, der keine offenen Ports hat. Die DNS von `vibez-jugendhilfe.de` bleibt bei All-Inkl; dafür nutzen wir
**Cloudflare for SaaS** mit einer kleinen Hilfszone. Hintergrund: [architektur.md](architektur.md#domain-und-dns-cloudflare-for-saas).

## Inhalt

- [Konto und Zugriffe](#konto-und-zugriffe)
- [Hilfszone](#hilfszone)
- [Tunnel](#tunnel)
- [Cloudflare for SaaS](#cloudflare-for-saas)
- [Einstellungen der Zone](#einstellungen-der-zone)
- [WAF-Regeln](#waf-regeln)
- [Ratenbegrenzung](#ratenbegrenzung)
- [Was Cloudflare sieht und speichert](#was-cloudflare-sieht-und-speichert)

## Konto und Zugriffe

- **Eigenes Cloudflare-Konto für VIBEZ** (Free). Inhaber ist eine VIBEZ-Adresse, z. B. `it@vibez-jugendhilfe.de`, nicht
  Murats Konto.
- Murat wird als **Mitglied** eingeladen (Rolle „Administrator“), 2FA für alle Mitglieder Pflicht.
- API-Tokens nur mit dem Nötigsten, z. B. für DNS der Hilfszone; **kein Global API Key**.
- Zahlungsmittel hinterlegen (nötig zum Aktivieren von Cloudflare for SaaS, siehe unten).
- Data Processing Addendum (DPA) von Cloudflare ist Teil der Self-Serve-Bedingungen. In der
  [Dienstleister-Übersicht](../datenschutz/dienstleister.md) ablegen.

## Hilfszone

Eine kleine Zusatz-Domain, nur als technischer Ankerpunkt, z. B. `vibez-edge.de`. Der Name ist ein Beispiel und vor dem
Kauf auf Verfügbarkeit prüfen.

1. Domain bei All-Inkl registrieren (im bestehenden VIBEZ-Kundenkonto).
2. In Cloudflare **Add a domain** → `vibez-edge.de` → Free-Plan.
3. Bei All-Inkl die **Nameserver** dieser Hilfsdomain auf die beiden von Cloudflare genannten Nameserver umstellen.
   Die Hauptdomain `vibez-jugendhilfe.de` bleibt unverändert bei All-Inkl.
4. Warten, bis die Zone in Cloudflare „Active“ ist.

## Tunnel

Lokal verwalteter Tunnel. Die Konfiguration liegt im Repo ([`stack/cloudflared/config.yml`](../stack/cloudflared/config.yml)),
die Zugangsdaten (`credentials.json`) nur auf dem Server.

```bash
# auf dem Admin-Rechner oder dem Server (einmalig)
cloudflared tunnel login                       # Browser: Zone vibez-edge.de auswählen
cloudflared tunnel create vibez-prod           # erzeugt <TUNNEL-ID>.json
cloudflared tunnel route dns vibez-prod origin.vibez-edge.de
```

- `<TUNNEL-ID>.json` als `/opt/vibez/stack/cloudflared/credentials.json` auf den Server kopieren (chmod 600). Danach
  vom Admin-Rechner löschen.
- `TUNNEL_ID` in `stack/cloudflared/config.yml` eintragen.
- `cloudflared tunnel route dns` legt `origin.vibez-edge.de` als **proxied CNAME** auf `<TUNNEL-ID>.cfargotunnel.com` an.
  Das ist die Fallback-Origin.
- Die Datei `cert.pem` aus `tunnel login` wird nach der Einrichtung gelöscht. Sie wird nur zum Anlegen von Tunneln gebraucht.

## Cloudflare for SaaS

Zone `vibez-edge.de` → **SSL/TLS → Custom Hostnames**:

1. **Enable** (Zahlungsmittel nötig).
2. **Fallback Origin**: `origin.vibez-edge.de` → warten auf Status *Active*.
3. **Add Custom Hostname**: `nachweise.vibez-jugendhilfe.de`
   - Minimum TLS: **1.2**
   - Zertifikats-Validierung: **TXT**
   - kein Custom Origin (Fallback reicht)
4. Cloudflare zeigt zwei Einträge an. Beide bei All-Inkl (KAS → DNS-Einstellungen `vibez-jugendhilfe.de`) anlegen:
   - `_cf-custom-hostname.nachweise` **TXT** → Wert für die Hostname-Validierung
   - `_acme-challenge.nachweise` **TXT** → Wert für die Zertifikats-Validierung
5. Wenn beide *Active* sind: bei All-Inkl `nachweise` **CNAME** → `origin.vibez-edge.de` anlegen.
6. Test: `https://nachweise.vibez-jugendhilfe.de/health` → `{"ok": true}`.

Hinweis: Das Zertifikat erneuert Cloudflare automatisch. Der TXT-Eintrag `_acme-challenge` muss dafür bestehen bleiben,
außer Cloudflare zeigt im Dashboard „Delegated DCV“ als Alternative an.

## Einstellungen der Zone

| Bereich | Einstellung | Wert | Grund |
|---|---|---|---|
| SSL/TLS | Encryption mode | Full (strict) | gilt nur für nicht getunnelte Ziele; schadet nicht |
| SSL/TLS → Edge Certificates | Always Use HTTPS | an | |
| | Minimum TLS Version | 1.2 | |
| | TLS 1.3 | an | |
| | HSTS | aus (setzt Traefik) | doppelte Header vermeiden |
| Security | Security Level | Medium | |
| | Browser Integrity Check | an | |
| | Bot Fight Mode | **aus** | keine JS-Challenges auf Diensthandys; Bots blockt Regel 4 |
| | Block AI Scrapers and Crawlers | an | |
| | Managed Ruleset (Free) | an | |
| Scrape Shield | Email Address Obfuscation | **aus** | würde Skripte einfügen → verletzt die CSP der App |
| Speed | Rocket Loader | **aus** | dto. |
| Analytics | Web Analytics (RUM) | **aus** | kein Tracking, kein eingefügtes Skript |
| Caching → Cache Rules | Regel „Seiten nie cachen“ | Hostname = `nachweise.vibez-jugendhilfe.de` und Pfad beginnt **nicht** mit `/static/` → **Bypass cache** | Seiten mit Sozialdaten dürfen nie im CDN liegen (die App sendet zusätzlich `Cache-Control: no-store`) |
| Network | WebSockets | egal | nicht genutzt |

## WAF-Regeln

Zone `vibez-edge.de` → **Security → Security rules → Custom rules**. Für Custom Hostnames gelten die Regeln der Zone (laut
Cloudflare-Doku „WAF rules with current zone plan“). Im Free-Tarif sind 5 Regeln möglich.

| Nr. | Name | Ausdruck | Aktion |
|---|---|---|---|
| 1 | Nur die App-Adresse | `(not http.host eq "nachweise.vibez-jugendhilfe.de")` | Block |
| 2 | Nur EU und Schweiz | `(not ip.src.country in {"AT" "BE" "BG" "CH" "CY" "CZ" "DE" "DK" "EE" "ES" "FI" "FR" "GR" "HR" "HU" "IE" "IT" "LI" "LT" "LU" "LV" "MT" "NL" "PL" "PT" "RO" "SE" "SI" "SK"})` | Block |
| 3 | Scanner-Pfade | `(http.request.uri.path contains "/." or http.request.uri.path contains ".php" or http.request.uri.path contains "wp-" or http.request.uri.path contains "xmlrpc" or http.request.uri.path contains "phpmyadmin" or http.request.uri.path contains "cgi-bin" or http.request.uri.path contains "/admin" or http.request.uri.path contains "/api/")` | Block |
| 4 | Bekannte Bots | `(cf.client.bot)` | Block |
| 5 | Nur übliche Methoden | `(not http.request.method in {"GET" "HEAD" "POST"})` | Block |

Ausnahmen bei Bedarf (z. B. Dienstreise ins Nicht-EU-Ausland): Land in Regel 2 **befristet** ergänzen und im
Wartungsprotokoll vermerken. Uptime Kuma prüft von Murats Server in Deutschland aus und wird nicht geblockt.

## Ratenbegrenzung

**Security → Security rules → Rate limiting rules** (Free: 1 Regel, Zeitraum 10 s):

| Name | Ausdruck | Zählung | Grenze | Aktion |
|---|---|---|---|---|
| Anmeldung bremsen | `(http.request.uri.path eq "/login" and http.request.method eq "POST")` | je IP | 5 Anfragen / 10 s | Block für 10 s |

Dazu kommen die Bremse in der App (8 Fehlversuche je Benutzer/IP in 10 Minuten) und die Ratenbegrenzung in Traefik
(20/s je IP, Burst 60).

## Absicherung von Konto und Domain

- **Benachrichtigungen** (Cloudflare → Notifications): Tunnel-Status („Tunnel Health Alert“) und Änderungen am SSL/TLS
  bzw. an Custom Hostnames. Ein unerwarteter **zweiter Connector** am Tunnel deutet auf gestohlene Zugangsdaten hin:
  dann sofort Tunnel neu erzeugen.
- **Hilfsdomain** `vibez-edge.de`: automatische Verlängerung und Domain-Sperre beim Registrar (All-Inkl). Läuft sie aus,
  könnte jemand anderes sie registrieren und `nachweise.vibez-jugendhilfe.de` übernehmen (siehe Sicherheitsanalyse C6).
- **CAA** bei All-Inkl für `vibez-jugendhilfe.de`: nur die Zertifizierungsstellen erlauben, die Cloudflare für Custom
  Hostnames nutzt, plus die der bestehenden Website. Die aktuelle Liste steht in der Cloudflare-Doku („CAA records“ für
  SSL for SaaS) und muss vor dem Setzen geprüft werden, sonst schlägt die Zertifikatsausstellung fehl.
- **Zertifikatstransparenz**: kostenlose Überwachung (z. B. Cert Spotter) für `vibez-jugendhilfe.de` mit Mail an Murat.
  So fällt ein fremd ausgestelltes Zertifikat für die App-Adresse auf.

## Was Cloudflare sieht und speichert

- Cloudflare entschlüsselt den Datenverkehr am Rand seines Netzes. Damit liegen **Inhalte** (z. B. Termintexte,
  Unterschriften beim Absenden) dort **kurzzeitig im Arbeitsspeicher** vor. Die Cache-Regel oben verhindert, dass Seiten
  gespeichert werden.
- Im Free-Tarif gibt es keine Beschränkung der TLS-Terminierung auf EU-Rechenzentren (Regional Services sind ein
  Enterprise-Zusatz). In der Praxis bedient das nächstgelegene Rechenzentrum, für Hessen meist Frankfurt.
- Cloudflare speichert **Metadaten** (IP, Land, Pfad, Zeitpunkt, Regel-Treffer) in Security-Events und Analytics für
  begrenzte Zeit.
- Bewertung und Maßnahmen: [Datenschutz-Folgenabschätzung, Risiko R5](../datenschutz/dsfa.md).
