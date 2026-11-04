# Marocmarkt

Marocmarkt ist eine mehrsprachige Kleinanzeigen-Webseite für Marokko. Das Frontend verwendet HTML, CSS und JavaScript; Konten, Anzeigen, Favoriten, Meldungen, Nachrichten und Bilder werden über Supabase gespeichert.

## Projektstruktur

- `index.html`, `style.css`, `script.js`: Website
- `supabase/schema.sql`: Datenbankschema, RLS-Regeln und Bildspeicher
- `supabase-config.js`: öffentliche Supabase-Projektkonfiguration
- `assets/`: lokale Bilder und Icons

## Supabase einrichten

1. Erstelle ein Supabase-Projekt.
2. Öffne den SQL Editor im Supabase-Dashboard und führe den Inhalt von `supabase/schema.sql` aus.
3. Aktiviere unter **Authentication → Providers** die E-Mail-Anmeldung. Trage unter den Auth-URL-Einstellungen deine lokale URL und später deine Produktionsdomain als Redirect-URLs ein, damit E-Mail-Bestätigung und Passwortzurücksetzung zur Website zurückführen.
4. Kopiere Projekt-URL und den öffentlichen **anon/publishable key** aus den API-Einstellungen in `supabase-config.js`:

   ```js
   window.MAROCMARKT_SUPABASE = {
     url: 'https://DEIN-PROJEKT.supabase.co',
     anonKey: 'DEIN_OEFFENTLICHER_ANON_ODER_PUBLISHABLE_KEY'
   };
   ```

   Der anon/publishable key ist für die Verwendung im Browser bestimmt; der Datenzugriff wird durch Row Level Security begrenzt. **Niemals** den `service_role`-Key in diese Datei oder in das Frontend eintragen.

5. Starte die Website über einen lokalen HTTP-Server:

   ```bash
   python3 -m http.server 8080
   ```

   Öffne danach `http://localhost:8080/`.

### Moderationskonto

Registriere zunächst dein Konto und bestätige gegebenenfalls die E-Mail-Adresse. Ermittle anschließend die Benutzer-ID unter **Authentication → Users** und führe im SQL Editor diesen Befehl mit deiner ID aus:

```sql
update public.profiles
set is_admin = true
where id = 'DEINE-BENUTZER-UUID';
```

Das Moderations-Dashboard ist nur für dieses Konto sichtbar. Die Benutzerrolle wird serverseitig durch RLS geprüft und kann nicht über das Browser-Frontend geändert werden.

## Funktionen

- Französisch und Arabisch
- Suche, Stadt-/Kategorie-Filter und Sortierung
- E-Mail-Registrierung, Anmeldung und Abmeldung
- Anzeigen dauerhaft speichern, bearbeiten und löschen
- Mehrere Bilder pro Anzeige (JPG, PNG oder WebP; maximal 10 Bilder zu je 5 MB)
- Kontoansicht für eigene Anzeigen, Favoriten und Nachrichten
- Private Nachrichten zwischen Käufer und Verkäufer
- Meldungen und Admin-Moderation

Ohne Supabase-Konfiguration zeigt die Seite Demo-Anzeigen. Konten und Backend-Funktionen sind dann nicht verfügbar.
