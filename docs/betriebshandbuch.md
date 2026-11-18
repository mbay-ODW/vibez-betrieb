# Betriebshandbuch – Echtbetrieb

Abläufe für den laufenden Betrieb. Befehle laufen auf `vibez-prod` (`ssh -p 5022 murat@<server>`) im Verzeichnis `/opt/vibez`.

## Inhalt

- [Update der App](#update-der-app)
- [Zurück auf die vorige Version](#zurück-auf-die-vorige-version)
- [Monatliche Wartung](#monatliche-wartung)
- [Wiederherstellung](#wiederherstellung)
- [Störungen](#störungen)
- [Sicherheitsvorfälle und Datenpannen](#sicherheitsvorfälle-und-datenpannen)
- [Benutzer in der App](#benutzer-in-der-app)
- [Wartungsprotokoll](#wartungsprotokoll)
- [Ende der Betreuung / Übergabe](#ende-der-betreuung--übergabe)

## Stacks und Portainer

Aufbau wie auf Murats Server (Entscheidung Murat, 18.11.2026): **ein Portainer-Stack je Dienst**, alle als Git-Stacks aus
`mbay-ODW/vibez-betrieb` (`stacks/<name>/compose.yml`, Portainer prüft alle 5 Minuten auf Änderungen und rollt dann neu aus).

| Stack | Container | Netze |
|---|---|---|
| `cloudflared` | vibez-cloudflared | `tunnel` |
| `traefik` | vibez-traefik, vibez-authelia, vibez-redis | `tunnel`, `fe-admin`, `fe-vibez`, `fe-vibez-testing`, `link-ldap` (Authelia), intern |
| `ldap` | vibez-lldap | `fe-admin` (Oberfläche), `link-ldap` (LDAP 3890) |
| `portainer` | vibez-portainer – **nicht** in Portainer selbst, sondern `sudo docker compose -p portainer -f /opt/vibez/repo/stacks/portainer/compose.yml up -d` | `fe-admin`, ausgehend (GitHub, Registry) |
| `dozzle` | vibez-dozzle + Socket-Proxy (nur lesend) | `fe-admin`, intern |
| `uptime` | vibez-uptime | `fe-admin`, ausgehend |
| `vibez-nachweise-prod` | vibez-app, vibez-usersync | `fe-vibez`, `link-ldap`, ausgehend (Atlas) |
| `vibez-nachweise-testing` | vibez-testing-app, vibez-testing-usersync | `fe-vibez-testing`, `link-ldap`, ausgehend (Atlas Test) |

- Die Netze `tunnel` (172.31.0.0/24), `fe-admin`, `fe-vibez`, `fe-vibez-testing`, `link-ldap` sind einmalig von Hand
  angelegt (`docker network create [--internal] …`); alle außer `tunnel` sind intern.
- **Geheimnisse** liegen nur unter `/srv/vibez/secrets/<stack>/` (Dateien 400/600, root bzw. Container-Benutzer) und
  werden per `env_file:` bzw. Bind-Mount mit absolutem Pfad eingebunden; Portainer sieht `/srv/vibez/secrets` nur lesend.
  **Keine Werte als Stack-Variablen in Portainer eintragen.** Einzige Stack-Variable: `VN_VERSION` (Version mit Digest)
  in den beiden App-Stacks.
- Konfigurationsdateien (Traefik, Authelia, cloudflared, LLDAP-Bootstrap) liegen unter `config/` und werden aus
  `/opt/vibez/repo` eingebunden; `host/autodeploy.sh` hält das Repo per `git pull` aktuell.
- In Portainer gespeichert: der Git-Lesezugang (Fine-grained Token, nur `vibez-betrieb`, Contents read) und der
  Registry-Zugang `ghcr.io` (nur `read:packages`). Für Skripte gibt es einen Portainer-API-Schlüssel
  (`/srv/vibez/secrets/portainer/api_token`).
- Änderungen an Compose oder Konfiguration: im Repo ändern, committen, pushen – Portainer und der Timer übernehmen sie.

## Update der App

1. Im App-Repo: Änderung fertig, `VERSION` und `CHANGELOG.md` erhöht, CI grün → Image `ghcr.io/mbay-odw/vibez-nachweise:<version>`.
2. Vorher in der **Demo** prüfen (vibez.bay-ram.de, erfundene Daten).
3. **Automatisch (Standard seit 18.11.2026):** Nach dem Merge auf `main` holt der Server die neue Nummer spätestens nach
   5 Minuten selbst (`vibez-autodeploy.timer` → `host/autodeploy.sh` → `host/deploy.sh --auto prod <version>` → Portainer-API): Digest festschreiben,
   Backup, Neustart, Health-Check, bei Fehler Rücksprung auf die vorige Version. Protokoll:
   `journalctl -t vibez-autodeploy -t vibez-deploy`. Vorher auf `testing` prüfen (`nachweise-testing.vibez-odenwald.de`).
   **Von Hand** (z. B. wenn der Timer aus ist):

   ```bash
   sudo /opt/vibez/host/deploy.sh prod 0.3.1      # zeigt den Digest, fragt nach, Backup davor, Health-Check danach
   sudo /opt/vibez/host/deploy.sh testing testing # Testumgebung auf den aktuellen Stand von :testing
   ```

   Automatik anhalten: `sudo systemctl stop vibez-autodeploy.timer` (wieder an: `start`).

4. Datenbank-Migrationen laufen beim Start der App automatisch (`settings.schema`). Im CHANGELOG steht, ob eine Version
   eine Migration enthält.
5. Eintrag im [Wartungsprotokoll](#wartungsprotokoll).

Ausrollen am besten außerhalb der Arbeitszeiten der Pädagog:innen (abends). Ein Update dauert unter einer Minute.

## Zurück auf die vorige Version

- **Ohne Migration** (laut CHANGELOG): `sudo /opt/vibez/host/deploy.sh prod <vorige-version>` (vorher `vibez-autodeploy.timer` stoppen, sonst rollt er die neueste Nummer wieder aus).
- **Mit Migration**: Ein Zurückgehen ist nicht ohne Weiteres möglich, weil die Daten schon umgebaut sind. Dann entweder den
  Fehler mit einer neuen Version beheben (bevorzugt) oder App stoppen, Datenbank auf den Stand vor dem Update
  zurücksetzen (Atlas Point-in-Time / Snapshot) und die vorige Version starten. Alles, was zwischendurch erfasst wurde,
  geht dabei verloren.

## Monatliche Wartung

Am ersten Arbeitstag des Monats (ca. 30 Minuten):

- [ ] Restore-Test des Vormonats gelaufen: `journalctl -t vibez-backup --since "-35 days" | grep restore-test`
- [ ] Atlas: Speicherbelegung (Flex: Grenze laut Preisblatt), keine offenen Alerts, Zugriffsliste unverändert (`host/atlas-zugriffsliste.sh`)
- [ ] Neue Versionen von Traefik, Authelia, LLDAP, cloudflared, Portainer, Dozzle, Uptime Kuma, restic, mongo-Tools prüfen
      (Release Notes, v. a. Sicherheit) → Version in `stacks/<name>/compose.yml` anheben, committen, pushen (Portainer
      rollt nach spätestens 5 Minuten neu aus; Portainer selbst per `docker compose`)
- [ ] Betriebssystem: `sudo apt list --upgradable` (Sicherheitsupdates laufen automatisch); Neustart nötig? `needrestart -b`
- [ ] Cloudflare: Security-Events auf Auffälligkeiten ansehen (z. B. gehäufte Blocks auf `/login`); **Audit-Log** der Zone
      `vibez-odenwald.de` prüfen: jede Änderung muss zu einem Eintrag im Wartungsprotokoll passen (DSFA T12)
- [ ] App: Änderungsprotokoll (Einstellungen → Änderungsprotokoll) auf ungewöhnliche Anmeldungen ansehen
- [ ] Mitarbeitende: Wer hat VIBEZ verlassen? Zugänge in der App deaktivieren
- [ ] Wartungsprotokoll-Eintrag

## Wiederherstellung

| Lage | Vorgehen |
|---|---|
| Einzelne Fehleingabe | In der App korrigieren. Das Änderungsprotokoll zeigt alte und neue Werte. |
| Datenbank versehentlich verändert/gelöscht | **Atlas** → Cluster → Backup → *Restore* auf einen Zeitpunkt vor dem Fehler (Point-in-Time bzw. letzter Snapshot), als neuen Cluster wiederherstellen, prüfen, dann umschalten oder Daten gezielt zurückkopieren. |
| Atlas-Konto/Projekt nicht verfügbar | Zweite Sicherung: `sudo host/restore.sh` (Stände anzeigen) → `sudo host/restore.sh <id> --datei` → in einen neuen Atlas-Cluster oder eine lokale MongoDB einspielen (Befehl gibt das Skript aus) → `MONGODB_URI` anpassen → `sudo stack/deploy.sh`. Danach die Archivdatei mit `shred -u` löschen. |
| Server defekt/kompromittiert | Neuen Server nach [deployment.md](deployment.md) Schritt 2 + 5 aufsetzen. Die Daten liegen in Atlas und gehen dabei nicht verloren. Neue IP in die Atlas-Zugriffsliste eintragen (`atlas-zugriffsliste.sh setzen`), alte entfernen. Tunnel-Zugangsdaten neu erzeugen bei Verdacht auf Kompromittierung. |

## Störungen

| Symptom | Prüfen | Abhilfe |
|---|---|---|
| Seite lädt nicht, Cloudflare-Fehler 1033/530 | `docker ps`, `docker logs vibez-cloudflared --tail 50` | Tunnel neu starten: `sudo docker restart vibez-cloudflared` |
| Cloudflare-Fehler 502/504 | `docker logs vibez-traefik`, `docker logs vibez-app --tail 100` | App neu starten; bei Atlas-Fehlern siehe nächste Zeile |
| App-Log: `ServerSelectionTimeoutError` | Atlas-Status, Zugriffsliste (`atlas-zugriffsliste.sh`), hat sich die Server-IP geändert? | IP eintragen; Atlas-Störung abwarten (status.mongodb.com) |
| Fehler 403 von Cloudflare bei Nutzer:innen | Cloudflare → Security Events: welche Regel? | Geo (Urlaub) / Bot-Regel prüfen, ggf. befristete Ausnahme |
| „Zu viele Versuche“ beim Anmelden | App-Bremse (10 Minuten) | Abwarten oder Passwort durch die Verwaltung neu setzen lassen |
| Backup-Monitor rot | `journalctl -u vibez-backup -n 50` | Storage Box erreichbar? restic-Sperre: `restic unlock` |

## Sicherheitsvorfälle und Datenpannen

**Sofort** (Murat):

1. Lage sichern: betroffenen Zugang in der App deaktivieren; bei Verdacht auf Server-Kompromittierung Tunnel stoppen
   (`sudo docker stop vibez-cloudflared`). Die App ist dann offline, die Daten in Atlas bleiben unverändert.
2. Passwörter/Schlüssel rotieren: betroffene App-Konten, ggf. Atlas-Zertifikate (neu erzeugen; bei Verdacht X.509-Benutzer neu anlegen), `VN_SECRET_KEY` (meldet alle
   ab), Tunnel-Zugangsdaten.
3. Beweise sichern: Traefik-Zugriffsprotokoll, App-Änderungsprotokoll, Cloudflare-Security-Events, Atlas-Access-History.
4. **VIBEZ sofort informieren.** VIBEZ ist Verantwortliche und entscheidet über die Meldung.

**VIBEZ** (Verantwortliche):

- Meldung an die Aufsichtsbehörde (HBDI) **innerhalb von 72 Stunden** nach Bekanntwerden, sofern ein Risiko für
  Betroffene nicht ausgeschlossen ist (Art. 33 DSGVO).
- Benachrichtigung der Betroffenen bei hohem Risiko (Art. 34 DSGVO). Bei Sozialdaten ist das in der Regel der Fall.
- Information der betroffenen Jugendämter gemäß Leistungsvereinbarung.
- Dokumentation des Vorfalls (auch wenn nicht meldepflichtig).

**Verlorenes oder gestohlenes Diensthandy:** Die Verwaltung deaktiviert den Zugang unter *Mitarbeitende*. Die
Sitzung ist damit sofort ungültig, weil die App bei jeder Anfrage prüft. Danach wird ein neues Passwort vergeben.

## Benutzer in der App

- Neue Mitarbeitende legt die Verwaltung unter *Mitarbeitende* an (Startpasswort persönlich übergeben, nicht per Mail).
- Austritt: Zugang **am letzten Arbeitstag** deaktivieren. Die Einträge bleiben erhalten.
- Verwaltungsrolle nur für Personen, die prüfen und abrechnen.

## Wartungsprotokoll

Jede Wartung mit Zugriff auf Server oder Datenbank wird festgehalten, damit VIBEZ als Verantwortliche nachvollziehen kann,
wer wann was getan hat. Ablage: `wartung/JJJJ.md` in diesem Repo **ohne Personendaten**, also nur technische Angaben.

```markdown
| Datum | Wer | Was | Datenbankzugriff | Bemerkung |
|---|---|---|---|---|
| 2026-12-01 | Murat | Update 0.2.4 → 0.2.5, Traefik v3.7.17 → v3.7.18 | nein | |
```

## Ende der Betreuung / Übergabe

Atlas und Hetzner Storage Box gehören VIBEZ. Server (netcup), Cloudflare-Zone und Domain `vibez-odenwald.de` laufen
dauerhaft auf Murat. Erst bei einem Ende der Betreuung bzw. Wechsel des IT-Dienstleisters:

1. Übertragen, was auf Murat läuft:
   - **Domain** `vibez-odenwald.de`: Inhaberwechsel bei febas auf VIBEZ (oder Transfer zum Registrar von VIBEZ).
   - **Cloudflare**: Konto für VIBEZ anlegen, Zone dort neu hinzufügen, Einstellungen und Regeln nach
     [cloudflare.md](cloudflare.md) übernehmen, neuen Tunnel erzeugen. **Vorher den DS-Eintrag beim Registrar löschen**
     und mindestens 2 Tage warten (TTL), dann Nameserver umstellen, in der neuen Zone DNSSEC einschalten, neuen
     DS-Eintrag setzen, alte Zone löschen. Sonst ist die Domain während des Umzugs nicht erreichbar.
   - **Server**: Übertragung des netcup-Produkts an VIBEZ, falls netcup das anbietet, sonst neuen VPS auf VIBEZ bestellen,
     nach [deployment.md](deployment.md) aufbauen und den alten Server löschen (Daten liegen in Atlas, nicht auf dem Server).
   Neue:n Dienstleister:in in Hetzner und Atlas einladen, Murat entfernen.
2. SSH: Murats Schlüssel entfernen, Schlüssel der neuen Betreuung eintragen.
3. Neue SSH-Schlüssel, Murats Schlüssel entfernen; `RESTIC_PASSWORD` behalten (liegt bei VIBEZ).
4. Dieses Repo an VIBEZ übertragen bzw. forken; Container-Image ggf. in eine VIBEZ-Registry spiegeln.
5. Murat bestätigt schriftlich die Löschung aller bei ihm verbliebenen Kopien (AV-Vertrag).
