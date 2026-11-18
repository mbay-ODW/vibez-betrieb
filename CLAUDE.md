# Regeln für dieses Repository (vibez-betrieb)

Betrieb und Datenschutzunterlagen für den **Echtbetrieb** von VIBEZ Nachweise (Sozialdaten von Kindern und Familien).

- **Keine Geheimnisse committen**: keine Passwörter, Tokens, Tunnel-Zugangsdaten, restic-Passwörter, Atlas-Keys.
  Nur Vorlagen (`.env.example`) mit leeren Werten oder Platzhaltern.
- **Keine Personendaten** in Repo, Wartungsprotokoll, Commits oder Issues – auch keine Klientennamen aus Störungsfällen.
- **Kein Zugriff auf den Echtbetrieb mit echten Daten aus KI-Sitzungen**: nicht per Portainer, MCP, SSH, Remote
  Control oder Datenbankverbindung. Änderungen hier sind Dokumentation und Konfiguration; im laufenden Betrieb rollt Murat
  manuell mit `stack/deploy.sh` aus.
- **Begrenzte Ausnahme – Cloudflare-Konfiguration** (Entscheidung Murat, 18.11.2026): Die Cloudflare-Anbindung (MCP)
  zu Murats Konto, in dem die Zone `vibez-odenwald.de` liegt, bleibt bestehen. Erlaubt ist nur die **Konfiguration** der
  Zone (DNS, WAF, Zoneneinstellungen), lesend jederzeit, ändernd **nur mit ausdrücklicher Freigabe von Murat im
  Einzelfall** und mit Eintrag im Wartungsprotokoll. Nie: Tunnel-Zugangsdaten, Server, Datenbank, Inhalte, Protokolle mit
  Personendaten. Regeln in DSFA T12.
- **Installation mit KI ausdrücklich erlaubt** (Aufbauphase; freigegeben von Murat am 16.11.2026, erweitert am
  18.11.2026): Solange die Datenbank leer ist und keine echten Daten erfasst wurden, darf eine KI-Sitzung den Echtbetrieb
  vollständig installieren und einrichten – über jeden Zugang, den Murat dafür bereitstellt (Claude Code auf dem Server,
  Remote Control, SSH, API-Tokens, Cloudflare-Anbindung).
  Regeln dafür in [`docs/aufbau.md`](docs/aufbau.md): Geheimnisse werden auf dem Server erzeugt und nie ausgegeben;
  jede Aktion steht im Aufbauprotokoll; **vor dem ersten echten Datensatz** endet der Zugang (Remote Control beendet,
  Claude Code vom Server entfernt, alle Tokens gelöscht – Übergabe-Checkliste).
- App-Code liegt in `mbay-ODW/vibez-nachweise`; hier werden nur feste Image-Versionen referenziert (nie `latest`).
- Sprache: Deutsch, klar und knapp; Fakten zu Anbietern (Cloudflare, Atlas, netcup, Hetzner) mit Prüfdatum versehen.
- Änderungen an Architektur oder Dienstleistern → DSFA (`datenschutz/dsfa.md`) und TOM prüfen und ggf. Version erhöhen.
