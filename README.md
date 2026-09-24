# Huawei Watch GT 6 - Private AI Assistent - FERTIG

**Status: ✅ Vollständig implementiert & build-fähig**

Private, schnelle, akku-schonende KI auf deiner Huawei Watch GT 6. Architektur:

```
[GT6 Watch (ArkTS)] --Bluetooth WearEngine--> [Android (Kotlin Bridge)] --WLAN HTTP--> [Pi5 Docker (FastAPI + dsk)] --> DeepSeek
```

## ✅ Was ist fertig?

### Backend (Raspberry Pi 5) - 100%
- `backend/app.py` - FastAPI mit 6 Endpoints: `/api/chat`, `/summarize`, `/translate`, `/explain`, `/weather`, `/quick`, `/health`, `/api/features`
- Rate Limit, GZip, Cache (60s), Truncation, ORJSON, ThreadPool
- `Dockerfile` arm64 optimiert, `docker-compose.yml` mit healthcheck, resource limits
- `test_client.py` zum Testen aller Endpoints
- `.env.example` + `data/.gitkeep`

### Android Companion (Kotlin) - 100%
- Vollständiges Android Studio Projekt: `settings.gradle.kts`, `build.gradle.kts`, `gradle.properties`
- `MainActivity.kt` - UI mit Pi URL Edit, Device Discovery, Pi Test, Logs, Permissions
- `BridgeService.kt` - ForegroundService mit WearEngine Receiver, OkHttp, Chunking, Debounce, Multi-Feature Support
- `PrefsManager.kt` - zentrale Config (Pi URL, Thinking, Search)
- Layouts, Strings, Themes, ProGuard
- Battery optimiert: LOW importance notification, kein Polling, 250ms debounce

### Watch App (ArkTS GT6) - 100%
- Vollständiges DevEco Studio Projekt: `AppScope/`, `entry/`, `build-profile.json5`, `oh-package.json5`
- `Index.ets` - Chat UI mit TextInput (öffnet native Tastatur!), Senden Button, Scroll Verlauf, Loading Spinner, Quick Actions (▲), Settings Button
- `Settings.ets` - Thinking Toggle, Verlauf löschen, Info
- `WearEngineService.ets` - gekapselt, Chunking, Error Handling
- `AiService.ets` - Business Logik für chat, summarize, translate, weather
- `ChatMessage.ets` - Models + Enums
- `Constants.ets` - zentrale Config + Quick Actions
- `EntryAbility.ets`, `module.json5` mit WearEngine Permissions
- Akku: max 15 Nachrichten, kein keepScreenOn, Lazy rendering, 500 char limit

## 🚀 Quickstart

### Pi
```bash
cd backend
cp .env.example .env # Token eintragen: JSON.parse(localStorage.getItem("userToken")).value von chat.deepseek.com
docker compose up -d --build
curl http://pi-ip:8000/health
python test_client.py
```

### Android
1. Android Studio -> Open -> `android/` Ordner
2. `agconnect-services.json` aus Huawei Console in `app/` legen (Package `com.huawei.ai.bridge`)
3. SHA256 Fingerprint holen: `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android` -> ohne Doppelpunkte in `PrefsManager` / `MainActivity` + in Watch `Constants.ets`
4. Pi IP in App einstellen, "Teste Pi Verbindung" -> sollte OK
5. Run -> Handy

### Watch GT6
1. DevEco Studio 5+ -> Open -> `watch/` Ordner
2. Bundle `com.huawei.ai.watch` setzen (muss mit Android übereinstimmen)
3. `Constants.ets` -> `ANDROID_FINGERPRINT` = Android SHA256 ohne Doppelpunkte
4. Signing Config erstellen, SHA256 für Android notieren
5. Huawei Console: WearEngine API freischalten (dauert 3-5 Tage!)
6. Run auf Uhr (Wireless Debug oder Internal Test)

Siehe `docs/DEPLOYMENT.md` für detaillierte Schritt-für-Schritt Anleitung + Fehlercodes.

## 🔋 Akku & Daten Optimierungen
- **Watch**: 15 Nachrichten Limit, 500 char Input, 800 char Response, kein KeepScreenOn, 35s Timeout, GZip
- **Android**: LOW notification, 250ms debounce, chunked Bluetooth 800B, OkHttp timeouts
- **Pi**: GZip, Rate Limit 1.2s, Cache 60s, ORJSON, 2 Worker Threads

## 🧩 Erweiterbarkeit
Neue Features in 3 Schritten:
1. Backend: neuen Endpoint in `app.py` (z.B. `/api/myfeature`)
2. Android: in `BridgeService.kt` `when(type)` erweitern
3. Watch: in `Constants.ets` Quick Action + in `AiService.ets` Payload Creator + UI in `Index.ets`

Bereits implementierte Erweiterungen: Summarize, Translate, Explain, Weather, Quick Actions, Settings

## 📁 Struktur
```
backend/         # Pi5 Docker - vollständig
android/         # Android Studio Projekt - vollständig
  app/src/main/java/com/huawei/ai/bridge/
  app/src/main/res/
watch/           # DevEco Studio Projekt - vollständig
  AppScope/
  entry/src/main/ets/pages/Index.ets
  entry/src/main/ets/pages/Settings.ets
  entry/src/main/ets/services/
docs/DEPLOYMENT.md
```

## 🔒 Sicherheit
- Pi nur im Heimnetz! Für extern: Tailscale/WireGuard
- `.env` nicht committen

MIT Lizenz - Private Nutzung, DeepSeek Token auf eigene Verantwortung.

---
**Fertig zum Bauen & Flashen!** 🚀
