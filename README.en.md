# RelayGo · AI API Relay & Key Manager

> **Your AI Relay, Ready to Go** — a smart mobile/desktop AI API relay and key manager.

RelayGo starts a lightweight OpenAI-compatible HTTP gateway on your device, unifies the management of API keys across multiple AI providers, and offers load balancing, automatic failover, protocol conversion, rate limiting, response caching, quota monitoring, and model-list syncing. Third-party AI apps only need to point their `base_url` to RelayGo to share this managed pool of highly-available keys.

> Licensed under **AGPL-3.0**. See [LICENSE](LICENSE) before use.

---

## ✨ Key Features

- **Multi-provider support** — OpenAI / Anthropic / Google / Azure / Custom, unified adapters
- **6 load-balancing strategies** — round-robin, weighted, priority, least-connections, response-time, smart
- **Automatic failover** — cooldown & auto-recovery on repeated failures; up to 3 key switches per request
- **Model-list syncing** — auto-fetch per provider, unified format, capability inference, scheduled sync
- **Response caching** — reuse idempotent 2xx responses, reduce cost
- **Multi-dimensional rate limiting** — per-IP / per-key / per-token, with adaptive TPM (AIMD)
- **Quota & alerts** — quota warnings, error-rate monitoring, reports, webhook notifications
- **Background keep-alive** — foreground service + boot autostart + battery-optimization whitelist
- **Secure key management** — AES-256 local encryption, batch test / import / export, auto-disable
- **Online updates** — GitHub Releases + in-app check

## 🧱 Tech Stack

| Item | Detail |
|---|---|
| Framework | Flutter 3.x (Dart 3.x) |
| Storage | Hive local encrypted storage |
| Crypto | `encrypt` (AES-256), `crypto` (SHA-256) |
| State | `provider` |
| Network | `http` (streaming SSE), `url_launcher` |
| Platforms | Android / iOS / Web / Linux / Windows / macOS |

## 📦 Quick Start

```bash
# 1. Install dependencies
flutter pub get

# 2. (Optional) Mirror config for mainland China
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

# 3. Run (Android device / desktop / web)
flutter run

# 4. Build Release APK
flutter build apk --release

# 5. Quality gates
flutter analyze && flutter test
```

## 🚀 Usage

1. Add API keys for each provider in "Key Management" (batch import supported).
2. Sync the model list and enable the models you need.
3. Configure the listening port (default `8788`) on your LAN, then set `base_url` in your AI app to `<host-ip>:<port>`.

## 📁 Structure

```
lib/
├── main.dart            # entry
├── app.dart             # global AppState (wires all services)
├── config/              # constants, theme, environment
├── database/            # Hive init & repositories
├── models/              # data models
├── services/            # proxy, sync, keys, rate-limit, cache, etc.
│   └── providers/       # provider adapters
├── screens/             # pages & dialogs
├── widgets/             # reusable widgets
├── utils/               # crypto, validation, formatting
└── l10n/                # i18n strings
test/                    # unit tests
```

## 🔒 Security

- Plaintext API keys are encrypted on creation and only decrypted temporarily during forwarding; never stored or logged in plaintext.
- The gateway is intended for LAN use; add access control for production scenarios.
- Comply with each AI provider's terms of service. This project is for learning and personal use.

## 🧩 Open Source & Credits

The core open-source dependencies and referenced projects used by RelayGo are listed in the in-app "Settings → Open Source License" page, and in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## 📄 License

[GNU Affero General Public License v3.0](LICENSE) (AGPL-3.0)

<sub>© 2026 RelayGo Authors</sub>