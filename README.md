# Karpuz Oyunu - Flutter

## GitHub Actions ile AAB Build

### 1. Keystore Oluştur (bir kez)
```bash
keytool -genkey -v -keystore keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias karpuz
```

### 2. GitHub Secrets Ekle
Settings → Secrets → Actions → New repository secret:

| Secret | Değer |
|--------|-------|
| `KEYSTORE_BASE64` | `base64 keystore.jks` komutu çıktısı |
| `STORE_PASSWORD` | Keystore şifresi |
| `KEY_PASSWORD` | Key şifresi |
| `KEY_ALIAS` | `karpuz` |

### 3. AdMob ID Güncelle
- `lib/main.dart` → `kAdAppId` ve `kInterstitialId`
- `android/app/src/main/AndroidManifest.xml` → `APPLICATION_ID`

### 4. Push → AAB İndir
```bash
git add . && git commit -m "build" && git push
```
Actions sekmesinden AAB'yi indir → Play Console'a yükle.
