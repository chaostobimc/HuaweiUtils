# Deployment Anleitung - Private AI Assistent (GT6 + Android + Pi5)

## Übersicht
```
[GT6 Watch (ArkTS)] --Bluetooth WearEngine--> [Android Handy (Kotlin Bridge)] --WLAN HTTP--> [Pi5 Docker (FastAPI + dsk)] --Internet--> DeepSeek
```

Ziel: Wenig Akku, wenig Daten, schnell, erweiterbar.

---

## Teil 1: Backend auf Raspberry Pi 5

### 1.1 Voraussetzungen Pi
- Raspberry Pi 5 mit Raspberry Pi OS (64-bit Bookworm)
- Docker + docker-compose installiert:
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# neu einloggen!
sudo apt install docker-compose-plugin -y
```

### 1.2 Token holen
1. Auf PC: https://chat.deepseek.com einloggen
2. F12 -> Console:
```js
JSON.parse(localStorage.getItem("userToken")).value
```
3. Token kopieren (beginnt mit eyJ...)

### 1.3 Backend starten
```bash
cd backend
cp .env.example .env
nano .env # Token einfügen

# Optional: data Ordner für cookies.json (Cloudflare Bypass)
mkdir -p data

# Build & Start (arm64 optimiert)
docker compose up -d --build

# Logs prüfen
docker logs -f huawei-ai-bridge

# Healthcheck
curl http://localhost:8000/health
# Sollte: {"status":"ok","token_configured":true}

# Test Chat
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -d '{"prompt":"Hallo, wer bist du?"}'
```

### 1.4 Cloudflare Bypass (falls Fehler CLOUDFLARE)
DeepSeek hat Cloudflare Schutz. Falls `python -m dsk.bypass` nötig:
```bash
# Auf Pi im Container ausführen (braucht Browser)
docker exec -it huawei-ai-bridge python -m dsk.bypass
# Oder lokal auf PC mit gleichem Token und dann cookies.json nach backend/data kopieren
# Siehe: https://github.com/xtekky/deepseek4free#handling-cloudflare-challenges
```

### 1.5 Pi IP herausfinden
```bash
hostname -I
# z.B. 192.168.1.50 -> diese IP in Android App eintragen!
```

### 1.6 Autostart & Optimierung
- `restart: unless-stopped` in compose sorgt für Autostart nach Reboot
- Resource Limits: 1GB RAM, 2 CPUs (reicht)
- GZip Middleware spart WLAN Daten
- Rate Limit 1.5s schützt vor Akku-Drain durch Spam

---

## Teil 2: Android Companion App (Kotlin)

### 2.1 Projekt anlegen
1. Android Studio -> New Project -> Empty Activity
2. Package: `com.huawei.ai.bridge`
3. `build.gradle.kts` aus `android/build.gradle.kts` übernehmen
4. In `settings.gradle.kts` Huawei Repo hinzufügen:
```kotlin
dependencyResolutionManagement {
  repositories {
    google()
    mavenCentral()
    maven { url = uri("https://developer.huawei.com/repo/") }
  }
}
```

### 2.2 Huawei AGConnect & Signierung
1. https://developer.huawei.com -> Console -> My Projects -> Neues Projekt
2. App hinzufügen: Package `com.huawei.ai.bridge`
3. SHA256 Fingerprint holen:
```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
# SHA256 kopieren, Doppelpunkte entfernen!
```
4. `agconnect-services.json` herunterladen -> in `app/` legen
5. In `MainActivity.kt`:
   - `WATCH_PACKAGE_NAME = "com.huawei.ai.watch"` (muss mit Watch bundleName übereinstimmen)
   - `WATCH_FINGERPRINT = "<dein Watch SHA ohne Doppelpunkte>"`
   - `piBackendUrl = "http://<deine Pi IP>:8000"`

6. In Watch `Index.ets`:
   - `ANDROID_PACKAGE = "com.huawei.ai.bridge"`
   - `ANDROID_FINGERPRINT = "<dein Android SHA ohne Doppelpunkte>"`

**Wichtig: Fingerprints müssen gegenseitig eingetragen sein, sonst Fehler 206/207!**

### 2.3 Code einfügen
- `MainActivity.kt` -> `app/src/main/java/com/huawei/ai/bridge/MainActivity.kt`
- `BridgeService.kt` -> `app/src/main/java/com/huawei/ai/bridge/BridgeService.kt`
- `AndroidManifest.xml.snippet` Inhalte in `AndroidManifest.xml` mergen
- Layout: einfaches `activity_main.xml` mit:
  - TextView status
  - EditText für Pi IP
  - Button "Get Devices"

### 2.4 Permissions & Battery Optimierung
- Beim ersten Start fragt App nach WearEngine Permissions -> Zulassen
- Android fragt nach Akku-Optimierung ignorieren -> **NICHT ignorieren** für BridgeService? 
  - Besser: Einstellungen -> Apps -> AI Bridge -> Akku -> Uneingeschränkt (damit Service im Hintergrund bleibt)
  - Aber: Wir nutzen ForegroundService mit LOW importance, verbraucht minimal (<1% pro Tag laut Tests)

### 2.5 Installieren
```bash
./gradlew installDebug
# Oder via Android Studio Run
```

---

## Teil 3: Huawei Watch GT 6 App (ArkTS)

### 3.1 DevEco Studio Setup
1. DevEco Studio 5.0+ installieren (HarmonyOS NEXT SDK)
2. Neues Projekt: Wearable -> Empty Ability (ArkTS)
3. Bundle Name setzen: `com.huawei.ai.watch` (muss mit Android übereinstimmen!)
4. `entry/src/main/ets/pages/Index.ets` mit unserer Datei überschreiben
5. `WearEngineService.ets` und `Constants.ets` in entsprechende Ordner

### 3.2 module.json5 anpassen
- Siehe `watch/module.json5.snippet`
- Wichtig: `wearEngineRemoteAppNameList` muss Android Package enthalten
- `deviceTypes: ["wearable"]`
- Permissions: `DISTRIBUTED_DATASYNC`

### 3.3 Signierung (Kritisch für WearEngine!)
1. File -> Project Structure -> Signing Configs
2. Keystore erstellen (oder debug nutzen)
3. SHA256 Fingerprint kopieren:
   - Build -> Generate Keystore Fingerprint
   - SHA256 ohne Doppelpunkte = Fingerprint für Android App!
4. In Huawei Developer Console:
   - WearEngine API freischalten (dauert 3-5 Tage! Früh beantragen)
   - Unter "Wear Engine" -> App hinzufügen, Package + Fingerprint hinterlegen

### 3.4 Abhängigkeiten
In `oh-package.json5`:
```json
{
  "dependencies": {
    "@kit.WearEngine": "1.0.0"
  }
}
```

### 3.5 Auf Uhr flashen
1. Uhr via Bluetooth mit Handy koppeln (Huawei Health)
2. DevEco: Tools -> Device Manager -> Kein USB, sondern über "Remote Emulator"? 
   - Für GT6: **Wichtig** GT6 ist Lite Wearable, aber DevEco 5+ unterstützt seit HarmonyOS 4.3 auch GT Serie via **Wireless Debug**:
   - Uhr: Einstellungen -> Über -> Mehrmals auf Version tippen -> Entwickleroptionen -> Debug aktivieren
   - Huawei Health: Geräte -> Uhr -> Aktivieren von "App-Installation erlauben" (falls vorhanden)
   - Alternativ: Über DevEco "Signierte HAP" bauen und via Huawei Health "Watch App Gallery -> Internal Test" verteilen
3. Run -> Run 'entry'
4. Falls Fehler 201/206: Fingerprints prüfen!

### 3.6 UI Test
- Auf Uhr sollte App erscheinen
- Tippe in TextInput -> System Tastatur öffnet sich (GT6 hat kleine QWERTY)
- Senden -> Loading Spinner -> Android Logcat sollte "Received from watch" zeigen
- Antwort erscheint als grüne Bubble

---

## Teil 4: End-to-End Test & Debugging

### Reihenfolge:
1. Pi: `curl /health` OK?
2. Handy + Pi im selben WLAN? `ping <pi-ip>` vom Handy
3. Android Logcat:
```bash
adb logcat -s AIBridge-Main AIBridge-Service
```
4. Watch Log (DevEco -> Log):
```
[AI Watch] ...
```

### Häufige Fehler:
| Code | Ursache | Fix |
|------|---------|-----|
| 206 | Fingerprint falsch | SHA ohne Doppelpunkt, Packages prüfen |
| 207 | OK (eigentlich Erfolg) | Bei send ist 207 = Erfolg! |
| 201 | App nicht installiert | Beide Apps installiert? |
| Timeout | Pi IP falsch / Firewall | Pi Firewall `sudo ufw allow 8000` |
| CLOUDFLARE | DeepSeek blockt | `python -m dsk.bypass` ausführen |

---

## Teil 5: Erweiterbarkeit (Future Features)

Architektur ist modular:

- **Backend**: Neuen Endpunkt in `app.py` hinzufügen, z.B. `/api/translate`, `/api/weather`
  - Einfach neue Funktion + Route, Docker rebuild
- **Android**: In `BridgeService.kt` `when(type)` erweitern:
```kotlin
when(type) {
  "chat" -> callPiBackend(...)
  "weather" -> callWeatherApi(...)
}
```
- **Watch**: In `Index.ets` neues UI + `MessageType` Enum erweitern

Akku Tipps für Extensions:
- Sensoren nur on-demand abfragen, nicht dauerhaft
- Nutze `display` API um Screen nur bei Bedarf anzulassen
- Batch requests, cache Ergebnisse

---

## Sicherheit
- Pi nur im Heimnetz, nicht ins Internet exposen (sonst Auth hinzufügen!)
- Token niemals in Git committen -> `.env` ist in `.gitignore`
- Für Internet Zugriff: Tailscale/WireGuard VPN statt Port Forwarding

Viel Erfolg! 🚀
