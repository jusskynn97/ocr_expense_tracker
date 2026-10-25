# OCR Expense Tracker

A Flutter expense tracker that turns a paper receipt into a saved transaction in a few seconds — **entirely on-device**. Point the camera at a receipt, the framed region is cropped and read by ML Kit, a heuristic regex engine pulls out the total, the date and the merchant, and you confirm or correct the result before it is written to a local SQLite database.

No backend, no cloud OCR bill, no network permission.

---

## Demo

| GitHub Repository | Live Demo / APK |
|---|---|
| `https://github.com/<username>/ocr_expense_tracker` | `https://github.com/<username>/ocr_expense_tracker/releases` |

> Replace the placeholders above with your own repository and APK links before submitting.

---

## Features

### 1. Camera capture & image cropping
- Live camera viewfinder built on `camera` with `WidgetsBindingObserver` lifecycle handling, so the preview is released when the app is backgrounded and re-initialised on resume.
- Three-state flash toggle (`off → auto → always`) and tap-to-focus: the tap offset is converted into a camera focus point and confirmed with an animated focus ring.
- A framing crop overlay draws corner brackets over `NormalizedRect.receiptFrame`, plus a travelling scan beam while the shutter is animating.
- Only the framed region is persisted. `FileReceiptImageStore` bakes the EXIF orientation first and *then* copies the crop rectangle, so device rotation can never shift the crop box.

### 2. On-device OCR & regex heuristics
- `google_mlkit_text_recognition` (Latin script) runs offline in well under a second on mid-range hardware — zero cloud cost.
- Recognised blocks and lines are re-sorted by their bounding-box coordinates before being joined, because the parser depends on reading order to find the `TOTAL` line.
- `HeuristicReceiptParser` recognises Vietnamese amounts in every format people actually print: `150,000 VND`, `150.000 đ`, `150 000`, `1.500.000₫`.
- Dates are extracted from `DD/MM/YYYY`, `YYYY-MM-DD` and compact `DDMMYYYY`, and future dates are repaired (receipts printed as `MM/DD` are flipped when that yields a valid past date).
- Date-like, time-like and phone-like digit runs are stripped before the amount search, so `0912345678` or `18:45` can never be mistaken for the total.
- Optional marker matching is lossy-proofed by de-accenting the text, so `TỔNG CỘNG` and `tong cong` score identically.
- The parser returns an amount *candidate list* with a confidence score. The review screen surfaces the candidates as one-tap chips.

### 3. Local database & transaction lifecycle
- `sqflite` database `ocr_expense_tracker.db` (v1) with the `expenses` table and indexes on `date DESC` and `category`.
- Five categories — Food, Study, Travel, Gear, Entertainment — assigned automatically by `CategoryClassifier`, a de-accented keyword dictionary weighted 3× for merchant hits and 1× for raw-text hits.
- Every receipt thumbnail is cached in the application documents directory under `receipts/`, downscaled to 1024 px wide and re-encoded as JPEG quality 82. The DB stores only the relative path.
- Discarding a scan deletes the cached image instead of leaking it.
- Full CRUD lifecycle: create, read, update, delete, with `InvalidExpenseException` guarding non-positive amounts.

### 4. Custom canvas visualisations
- Animated category donut and weekly bar charts drawn **directly on canvas with `CustomPainter`** — no chart package.
- The donut expands each slice from zero sweep with an emphasis curve; the selected slice gains a glow and an animated centre label.
- The weekly bar chart grows bars on a staggered `Interval`, paints a dashed grid, rounds the bar caps, highlights today, and reveals values on tap.
- Both charts report the tapped slice/column back so the statistics page can show a detail panel.

---

## Architecture

Clean Architecture in three layers. The `domain` layer is pure Dart — no Flutter, no plugins — so the business rules stay testable and portable.

```
lib/
├── core/                          # Cross-cutting, framework-aware helpers
│   ├── navigation/page_transitions.dart
│   ├── theme/app_theme.dart        # colours, gradients, radii, durations, curves
│   └── utils/                      # currency + date formatters
│
├── domain/                        # Pure Dart. No Flutter, no plugin imports.
│   ├── entities/                  # Expense, ExpenseCategory, ParsedReceipt,
│   │                              # NormalizedRect, SpendingSummary
│   ├── repositories/              # ExpenseRepository (contract)
│   ├── services/                  # ReceiptParser, TextRecognizerService,
│   │                              # ReceiptImageStore, CategoryClassifier
│   └── usecases/                  # create / get / update / delete / scanReceipt
│
├── data/                          # Implementations of the domain contracts
│   ├── datasources/               # sqflite ExpenseLocalDataSource
│   ├── models/                    # ExpenseModel + table & index DDL
│   ├── repositories/              # ExpenseRepositoryImpl
│   └── services/                  # MlkitTextRecognizerService,
│                                  # HeuristicReceiptParser, FileReceiptImageStore
│
└── presentation/
    ├── providers/                 # ExpenseProvider, ScanSessionController
    ├── widgets/                   # glass kit, CustomPainter charts, overlays
    └── pages/                     # home shell, dashboard, stats, scanner, review
```

Dependencies point inwards only: `presentation → domain ← data`. `main.dart` is the single
composition root where every concrete class is constructed and injected; nothing else calls a
constructor of a plugin-backed service.

### Data flow of a scan

```
ScannerPage ──takePicture──▶ ReviewPage
                                 │  owns a ScanSessionController
                                 ▼
              cropping   → FileReceiptImageStore.persist(crop)
              recognizing→ MlkitTextRecognizerService → HeuristicReceiptParser
              ready      → prefilled editable form (+ CategoryClassifier suggestion)
                                 │  user edits, taps Save
                                 ▼
              CreateExpenseUseCase → ExpenseRepositoryImpl → sqflite
                                 │
                                 ▼
              ExpenseProvider.load() → dashboard + stats refresh
```

### State management
`provider` with `ChangeNotifier`. Two notifiers only:
- `ExpenseProvider` — the transaction list plus every derived aggregate (all-time / month / week
  summaries, month-over-month change, today's total, day-grouped rows).
- `ScanSessionController` — one instance per scan session, owning the
  `cropping → recognizing → ready/failed` state machine, the draft save and the cache cleanup on
  discard.

### Error handling
- Every use case that can fail returns a typed failure or throws a named exception
  (`InvalidExpenseException`, `ReceiptImageException`).
- `ScanSessionController` catches pipeline errors and moves to `ScanStage.failed`, which the review
  screen renders as a retry / manual-entry card rather than a dead end.
- A device with no camera or a denied permission shows a retry screen instead of crashing.
- `HomeShellPage`/`StatsPage` degrade to skeletons and empty states rather than blank screens.

---

## Tech stack

| Concern | Package | Version |
|---|---|---|
| UI toolkit | Flutter (Dart SDK) | `^3.12.2` |
| Camera | `camera` | `^0.12.1` |
| On-device OCR | `google_mlkit_text_recognition` | `^0.17.1` |
| Local database | `sqflite` | `^2.4.5` |
| Image crop / encode | `image` | `^4.12.0` |
| App storage paths | `path_provider`, `path` | `^2.1.6`, `^1.9.1` |
| State management | `provider` | `^6.1.5+1` |
| Date & currency formatting | `intl` | `^0.20.3` |
| Lints | `flutter_lints` | `^6.0.0` |

Charts, animations and overlays are implemented with the Flutter SDK only
(`CustomPainter`, `AnimationController`, `TweenAnimationBuilder`, `AnimatedSwitcher`).

---

## Getting started

### Prerequisites
- Flutter 3.44+ (Dart 3.12+)
- Android SDK with `minSdk` 24 or newer (the Flutter default already satisfies ML Kit)
- A physical Android device is strongly recommended — emulator camera feeds are synthetic and
  usually unreadable by ML Kit

### Install & run

```bash
flutter pub get
flutter run
```

Grant the camera permission when prompted. Tap the raised scan button in the middle of the bottom
bar, frame the receipt so the `TOTAL` line sits inside the brackets, and press the shutter.

### Build a release APK

```bash
flutter build apk --release
```

The artifact is written to `build/app/outputs/flutter-apk/app-release.apk`.

### Platform configuration already included
- **Android** — `CAMERA` permission, optional `camera` / `camera.autofocus` features.
  No `INTERNET` permission is required or requested, which is a useful proof that recognition is
  fully offline.
- **iOS** — `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription`.
- **Android `gradle.properties`** — `kotlin.incremental=false`, which works around the
  `Could not close incremental caches` Kotlin compiler failure observed on Windows.

---

## Design system

A single dark palette and motion vocabulary keeps the UI coherent:

| Token | Value |
|---|---|
| Background | `#070A13` |
| Primary | `#6C7CFF` |
| Accent (money) | `#22D3A8` |
| Radii | `12 / 18 / 26 / 34` |
| Durations | `180 / 320 / 620 / 900 ms` |
| Curves | `easeOutCubic`, `Cubic(0.22, 1, 0.36, 1)` |

Interaction feedback is consistently an `AnimatedScale` press (≈0.96), list reveals use
`StaggeredEntry` with per-index `Interval`s, and every chart animates its data rather than
snapping to the final frame.

---

## Known limitations

- The regex parser targets Vietnamese receipts. Adding a locale means extending the keyword
  dictionaries in `HeuristicReceiptParser` and `CategoryClassifier`.
- Receipts with a folded or badly lit `TOTAL` line will fall back to the "manual entry" path.
- `flutter analyze` reports 9 informational `prefer_initializing_formals` hints from `flutter_lints`.
  They are unavoidable: Dart forbids named parameters that start with an underscore, so the private
  `_dependency` fields cannot be initialised through formals.
- Screenshots in the accompanying report are not committed; capture them from a real device.

---

## License

Submitted as coursework for *Cross-Platform Mobile App Development* (VKU). No license is granted
for reuse.
