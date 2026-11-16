# Dienstleister und Auftragsverarbeitung

Übersicht für VIBEZ als Verantwortliche. Stand 16.11.2026. Zu jedem Auftragsverarbeiter gehört ein **AV-Vertrag nach
Art. 28 DSGVO**. Ablage: **[VIBEZ: Ablageort eintragen]**.

| Dienstleister | Leistung | Ort der Daten | Klientendaten? | Vertrag | Status |
|---|---|---|---|---|---|
| **netcup GmbH**, Karlsruhe | Server (VPS Lite 1 G12.5s) | Deutschland (Rechenzentrum Nürnberg) | ja (Server mit laufender App; Daten selbst in Atlas) | AV-Vertrag im netcup-Kundencenter (CCP) online abschließen; Zertifikate des Rechenzentrums anfordern und ablegen | ⏳ |
| **Hetzner Online GmbH**, Gunzenhausen | Storage Box (zweite Sicherung) | Deutschland | nur verschlüsselt (restic, Schlüssel nur bei VIBEZ) | AV-Vertrag im Hetzner-Konto online abschließen | ⏳ |
| **MongoDB, Inc.**, New York (EU: MongoDB Ltd.) mit Unterauftragnehmer **Amazon Web Services** | Datenbank MongoDB Atlas | AWS eu-central-1 (Frankfurt) | ja | Data Processing Agreement (Bestandteil der Atlas-Bedingungen), Standardvertragsklauseln; DPF-Status prüfen | ⏳ |
| **Cloudflare, Inc.**, San Francisco | Proxy, WAF, TLS, Tunnel | weltweites Netz, i. d. R. nächstes Rechenzentrum | Durchleitung (kurzzeitig entschlüsselt), keine Speicherung von Inhalten | Data Processing Addendum (Self-Serve), Standardvertragsklauseln; DPF-Status prüfen | ⏳ |
| **Murat Bayram** (IT-Dienstleister) | Einrichtung, Betrieb, Updates, Backup, Störungsbehebung | Deutschland | Zugriff bei Wartung | **AV-Vertrag + Verpflichtung zur Verschwiegenheit nach § 203 Abs. 4 Satz 2 Nr. 1 StGB** | ⏳ |
| Neue Medien Münnich (**All-Inkl**) | Registrar von `vibez-jugendhilfe.de`, Website und E-Mail (DNS-Verwaltung bei Cloudflare) | Deutschland | nein | bestehender Hostingvertrag; kein AV für diese App nötig | – |
| GitHub, Inc. | Quellcode, CI, Container-Image | USA | nein (nur erfundene Demodaten) | – | – |
| Tailscale Inc. | Verwaltungszugang (VPN für SSH) | USA (Koordination), Verbindung direkt und Ende-zu-Ende verschlüsselt | nein | – | – |
| Anthropic (Claude Code) | **nur Aufbauphase**: Einrichtung des Servers über Remote Control, bevor echte Daten existieren | – | nein (Regeln in [Aufbau](../docs/aufbau.md)) | – | – |

## Prüfpunkte je Vertrag

- Gegenstand, Dauer, Art und Zweck, Datenarten, Betroffene (aus der [DSFA](dsfa.md#3-systematische-beschreibung-der-verarbeitung))
- Weisungsgebundenheit, Vertraulichkeit, TOM des Anbieters (Zertifikate ablegen: ISO/IEC 27001, SOC 2)
- Unterauftragnehmer und Widerspruchsmöglichkeit
- Unterstützung bei Betroffenenrechten und Datenpannen (Meldefristen)
- Löschung/Rückgabe nach Vertragsende
- Drittland: Angemessenheitsbeschluss (EU-US Data Privacy Framework; Zertifizierung des Anbieters auf
  dataprivacyframework.gov prüfen und Ausdruck ablegen) bzw. Standardvertragsklauseln

## Besonderheit IT-Dienstleister

Die Pädagog:innen von VIBEZ unterliegen § 203 StGB. Ein externer IT-Dienstleister darf an Geheimnissen nur mitwirken, wenn
er zur Geheimhaltung verpflichtet ist (§ 203 Abs. 3 und 4 StGB). Der AV-Vertrag mit Murat enthält deshalb ausdrücklich:

- Verpflichtung zur Verschwiegenheit mit Hinweis auf die Strafbarkeit nach § 203 Abs. 4 StGB
- Zugriff auf Inhalte nur, soweit für Wartung/Störungsbehebung erforderlich; Dokumentation im Wartungsprotokoll
- keine Nutzung von KI-Diensten oder sonstigen Dritten mit Zugriff auf Produktivdaten
- Herausgabe aller Zugänge und Löschung eigener Kopien bei Vertragsende ([Übergabe](../docs/betriebshandbuch.md#ende-der-betreuung--übergabe))
