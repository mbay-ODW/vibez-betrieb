# Technische und organisatorische Maßnahmen (Art. 32 DSGVO, § 22 Abs. 2 BDSG) – VIBEZ Nachweise

Stand 15.11.2026 · Status: ✅ umgesetzt · ⏳ vor Echtbetrieb · ➕ empfohlen · Bezug zu Risiken: [DSFA](dsfa.md)

## Vertraulichkeit

| Maßnahme | Status |
|---|---|
| **Zutritt:** Rechenzentren von Hetzner (DE) und AWS Frankfurt (über MongoDB Atlas) mit Zutrittskontrolle; zertifiziert nach ISO/IEC 27001 (Nachweise der Anbieter ablegen) | ✅ |
| **Zugang Server:** keine offenen Ports; SSH nur über Tailscale, nur mit Schlüssel, kein root-Login; Notzugang über die Hetzner-Konsole mit Passwort im Passwortmanager von VIBEZ | ✅ |
| **Zugang App:** persönliche Konten, scrypt-Hashes, Anmeldebremse (App, Cloudflare, Traefik), Geo-Block EU/CH, Sitzung max. 12 h, sofortige Sperre beim Deaktivieren | ✅ |
| Zwei-Faktor-Anmeldung (Verwaltung Pflicht) | ⏳ M1 |
| Passwortregeln 12 Zeichen + Sperrliste + nicht der eigene Name | ✅ |
| Wechsel des Startpassworts erzwingen | ⏳ M2 |
| Abmeldung bei Inaktivität (2 h); Passwortwechsel beendet alle Sitzungen; „überall abmelden“ | ✅ |
| **Zugriff:** Rollen Pädagog:in / Verwaltung; Pädagog:innen standardmäßig nur eigene Klient:innen; serverseitige Prüfung in jeder Route | ✅ |
| Protokollierung der Vertretungsansicht und fehlgeschlagener Anmeldungen | ✅ |
| **Datenbank:** Atlas mit IP-Zugriffsliste (nur Server-IP), TLS, Benutzer je Zweck (App: readWrite `vibez`; Backup: `backup`); Admin-Rechte nur befristet | ✅ |
| **Verschlüsselung:** TLS 1.2+ zwischen Browser und Cloudflare; Tunnel zwischen Cloudflare und Server; TLS zur Datenbank; Verschlüsselung ruhender Daten in Atlas; Backups mit restic (AES-256) verschlüsselt, bevor sie den Server verlassen | ✅ |
| Eigener Schlüssel für Atlas (Customer Key Management) | ➕ |
| **Trennung:** eigener Server, eigenes Atlas-Projekt, eigenes Cloudflare-Konto nur für VIBEZ; Demo getrennt mit erfundenen Daten; interne Docker-Netze | ✅ |
| **Keine Drittinhalte:** Schrift lokal, keine CDNs/Tracker; Content-Security-Policy; Cloudflare-Skripteinfügungen abgeschaltet | ✅ |
| **Kein Caching sensibler Seiten:** `Cache-Control: no-store`, Cloudflare Cache-Regel „Bypass“ | ✅ |
| **Keine KI-/Automationszugriffe** auf den Echtbetrieb; Entwicklung nur mit erfundenen Daten | ✅ (Prüfpunkt Abnahme) |
| **Geheimnisse** nur auf dem Server (`.env` 600) bzw. im Passwortmanager von VIBEZ; nie im Repository | ✅ |

## Integrität

| Maßnahme | Status |
|---|---|
| Änderungsprotokoll aller fachlichen Änderungen mit alten/neuen Werten, Person, Zeit | ✅ |
| CSRF-Schutz, Maskierung aller Ausgaben, parametrisierte Datenbankabfragen, keine Uploads; CSV-Exporte gegen Formel-Injektion; Größenlimit 2 MB; nur bekannte Hostnamen | ✅ |
| Abhängigkeiten ohne bekannte Lücken (`pip-audit` in der CI, Dependabot); veröffentlichte Versionen unveränderlich, Echtbetrieb mit Digest | ✅ |
| Kopierte Unterschriftsbilder werden abgelehnt | ✅ |
| Rechnungen als unveränderlicher Schnappschuss; Storno statt Löschen; fortlaufende Nummern | ✅ |
| Plausibilitätsprüfungen vor dem Abschicken (Unterschrift, Bewilligung, Stundengrenzen); Vier-Augen-Prüfung durch die Verwaltung | ✅ |
| Unterschriften werden beim Speichern dekodiert, geprüft und neu kodiert | ✅ |
| Software: automatisierte Tests in der CI vor jedem Image; feste Versionen; Ausrollen nur über `deploy.sh` | ✅ |
| Container read-only, ohne Zusatzrechte; automatische Sicherheitsupdates des Betriebssystems | ✅ |
| WAF (Managed Rules, Scanner-Pfade, Methoden, Bots) | ✅ |

## Verfügbarkeit und Belastbarkeit

| Maßnahme | Status |
|---|---|
| Atlas Cloud Backup (Snapshots; je nach Tarif Point-in-Time) und Replikation des Clusters | ✅ |
| Zweite, verschlüsselte Sicherung nachts auf Hetzner Storage Box, 12 Monate | ✅ |
| Monatlicher automatischer Wiederherstellungstest; wöchentliche Prüfung der Backup-Daten | ✅ |
| Überwachung (Uptime Kuma: Erreichbarkeit, Zertifikat, Backup-Heartbeat; Atlas-Alerts) | ✅ |
| Wiederanlauf eines neuen Servers nach Anleitung innerhalb eines Arbeitstags | ✅ |
| Papier-Rückfallebene für Termine | ⏳ VIBEZ |

## Verfahren zur regelmäßigen Überprüfung

| Maßnahme | Status |
|---|---|
| Monatliche Wartung nach Checkliste ([Betriebshandbuch](../docs/betriebshandbuch.md#monatliche-wartung)) | ✅ |
| Wartungsprotokoll für Eingriffe mit Datenbankzugriff | ✅ |
| Jährliche Überprüfung der DSFA und dieser TOM | ⏳ VIBEZ |
| Externer Sicherheitstest | ➕ |

## Organisatorisch (VIBEZ)

| Maßnahme | Status |
|---|---|
| Verpflichtung der Beschäftigten auf Vertraulichkeit, Sozialgeheimnis, § 203 StGB | ✅ bestehend **[bestätigen]** |
| Geräteregeln für Pädagog:innen (Sperre, Updates, Verlustmeldung) und Einweisung | ⏳ O1 |
| Schulung: knappe, sachliche Termintexte | ⏳ O3 |
| Zugänge am letzten Arbeitstag deaktivieren | ✅ (Betriebshandbuch) |
| Datenschutzbeauftragte:r benannt | ⏳ O4 |
| Meldeweg für Datenpannen (72 Stunden) | ✅ (Betriebshandbuch) |
| AV-Verträge mit allen Dienstleistern | ⏳ M6 |
| Löschkonzept | ⏳ M5 |
