```
then `flutter build apk --release --flavor offline -t lib/main_offline.dart`. Without `key.properties`, release builds fall back to the debug key (fine for testing, not for publishing).

### Group mesh connectivity (colab flavor)
Teammates on the same Wi-Fi or phone hotspot find each other automatically. Over mobile data, the host's QR carries its public endpoint (STUN); if a carrier NAT blocks the return path, the host taps **Scan a teammate's QR** on the joiner's phone to open it. All mesh packets are AES-256-GCM encrypted with the session key from the QR.

---

## 🤖 Headless Automation API (Tasker / Automation)

Control the application headlessly via Android Broadcast Intents:

| Action Intent | Intent Extras | Description |
|---|---|---|
| `org.opensource.tracker.START_ACTIVITY` | `duration_mins: int` (or `target_duration: int` seconds), `safety_buffer: double` (%), `activity_type: string` | Starts background tracking (ignored if a session is already active or paused) |
| `org.opensource.tracker.STOP_ACTIVITY` | None | Stops tracking and marks the session completed |
| `org.opensource.tracker.GET_CURRENT_STATS` | None | Replies with an `org.opensource.tracker.STATS_REPLY` broadcast: `is_running`, `session_id`, `elapsed_seconds`, `distance_km`, `points_logged`, `target_duration`, `safety_buffer` |

> Android 12+ only allows starting the tracking service from the background when TurnBack is exempt from battery optimisation (the app asks for this exemption).

---

## 👤 Author & Repository

- **Creator & Maintainer:** Sujay Seeram ([@seeramsujay](https://github.com/seeramsujay))
- **Repository:** [https://github.com/seeramsujay/activity-mapper](https://github.com/seeramsujay/activity-mapper)
- **Email:** [sujayat2007@gmail.com](mailto:sujayat2007@gmail.com)

---

## 📄 License & Privacy

This project is open-source under the GNU Affero General Public License v3.0 (see `LICENSE`). It operates **100% locally and offline** without tracking, ads, analytics, or external servers. All data remains exclusively on your device.
