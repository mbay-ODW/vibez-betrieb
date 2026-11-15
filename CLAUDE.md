# Regeln für dieses Repository (vibez-betrieb)

Betrieb und Datenschutzunterlagen für den **Echtbetrieb** von VIBEZ Nachweise (Sozialdaten von Kindern und Familien).

- **Keine Geheimnisse committen**: keine Passwörter, Tokens, Tunnel-Zugangsdaten, restic-Passwörter, Atlas-Keys.
  Nur Vorlagen (`.env.example`) mit leeren Werten oder Platzhaltern.
- **Keine Personendaten** in Repo, Wartungsprotokoll, Commits oder Issues – auch keine Klientennamen aus Störungsfällen.
- **Kein Zugriff auf den Echtbetrieb aus KI-Sitzungen**: nicht per Portainer, MCP, SSH oder Datenbankverbindung.
  Änderungen hier sind Dokumentation und Konfiguration; ausgerollt wird von Murat manuell mit `stack/deploy.sh`.
- App-Code liegt in `mbay-ODW/vibez-nachweise`; hier werden nur feste Image-Versionen referenziert (nie `latest`).
- Sprache: Deutsch, klar und knapp; Fakten zu Anbietern (Cloudflare, Atlas, Hetzner) mit Prüfdatum versehen.
- Änderungen an Architektur oder Dienstleistern → DSFA (`datenschutz/dsfa.md`) und TOM prüfen und ggf. Version erhöhen.
