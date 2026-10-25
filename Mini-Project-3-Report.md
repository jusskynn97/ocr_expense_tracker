# MINI-PROJECT SHORT TECHNICAL REPORT
**Course:** Cross-Platform Mobile App Development (VKU)
**Mini-Project Title:** Mini-Project 3 — OCR Expense Tracker
**Team / Student Name:** Bui Dang Trung Kien
**Submission Date:** 25/10/2026

---

## 1. GENERAL INFORMATION & DELIVERABLE LINKS

* **Team Members:**
  1. Bui Dang Trung Kien — Student ID: 32IT.B102 — Role: Fullstack Mobile Developer — Contribution: 100%
* **💻 GitHub Repository:** `https://github.com/jusskynn97/ocr_expense_tracker`
* **🎥 Video Demo (Optional):** `https://drive.google.com/drive/folders/1DmLJQg91T40fnzuiQOF4ShtW3nIMnxra?usp=sharing`
* **📱 Platform target:** Android (primary, verified with `flutter build apk`), iOS configuration included
* **🧱 Tech stack:** Flutter 3.44 / Dart 3.12, `camera`, `google_mlkit_text_recognition`, `sqflite`, `provider`, `image`, `intl`, `path_provider`
* **📴 Network requirement:** none — the app declares no `INTERNET` permission; all recognition and storage is on-device

**Project summary.** OCR Expense Tracker converts a paper receipt into a persisted transaction
without any cloud service. The user frames the receipt in a live camera viewfinder; the framed
region is cropped and cached, read by ML Kit's on-device text recogniser, and interpreted by a
custom heuristic regex engine that extracts the total amount, the date and the merchant name. An
interactive review screen lets the user correct every field before the record is written to a local
SQLite database. Spending is then visualised through an animated donut chart and a weekly bar chart
drawn directly on canvas with `CustomPainter`.

---

## 2. FEATURE IMPLEMENTATION CHECKLIST

| # | Required Feature | Status | Implementation Details & Acceptance Level |
|:---:|---|:---:|---|
| 1 | **Camera Capture & Image Cropping** — live viewfinder, flash toggle, focus tap, framing crop overlay | ✅ Complete | `ScannerPage` drives a `CameraController` whose lifecycle follows `WidgetsBindingObserver`, so the preview is released on `paused` and rebuilt on `resumed`. Flash cycles `off → auto → always`; a tap is converted into a camera focus point and confirmed by an animated `_FocusRing`. `ScanFrameOverlay` paints corner brackets plus a travelling scan beam over `NormalizedRect.receiptFrame` (left 0.06, top 0.27, width 0.88, height 0.46). Only pixels inside the frame are kept: `FileReceiptImageStore.persist()` bakes the EXIF orientation **before** copying the crop rectangle, so rotation never shifts the box. **Acceptance:** the saved thumbnail contains exactly the framed region, in the correct orientation, on a portrait-locked phone. |
| 2 | **On-Device Text Recognition & Regex Heuristics** — ML Kit OCR, regex for amount / date / merchant | ✅ Complete | `MlkitTextRecognizerService` wraps `google_mlkit_text_recognition` (Latin script) behind a domain contract and re-sorts blocks and lines by bounding-box coordinates before joining them, because the parser depends on reading order. `HeuristicReceiptParser` (≈440 lines, pure Dart) recognises `150,000 VND`, `150.000 đ`, `150 000` and `1.500.000₫`; dates as `DD/MM/YYYY`, `YYYY-MM-DD` and compact `DDMMYYYY`, including repair of future dates printed as `MM/DD`; and infers the merchant from the first non-noise lines. Date-like, time-like and phone-like digit runs are stripped before the amount search. **Acceptance:** on real Vietnamese receipts the amount, date and merchant are prefilled correctly in the review screen, with the parsed amount also offered as one-tap suggestion chips. |
| 3 | **Interactive Review Screen** — manual edits before saving | ✅ Complete | `ReviewPage` owns a `ScanSessionController` for its own lifetime and renders a three-state UI: shimmer skeleton + spinner while recognising, an editable form when parsing succeeds, and a retry / **manual entry** card when it fails. Fields: auto-formatting amount input with thousands separators, merchant, date picker with a "Today" shortcut, five gradient category chips, note, and a collapsible raw-OCR panel. A fixed bottom bar shows the live total and blocks saving until the amount is a positive number. **Acceptance:** every auto-filled field is editable, and saving a hand-corrected value persists the corrected value, not the parsed one. |
| 4 | **Local Database & Transaction Lifecycle** — sqflite/isar persistence, 5 categories, receipt thumbnail caching | ✅ Complete | `sqflite` database `ocr_expense_tracker.db` v1 with table `expenses` (amount, merchant, category, date, note, receipt_path, raw_text, created_at) and indexes on `date DESC` and `category`. `CategoryClassifier` assigns Food / Study / Travel / Gear / Entertainment from a de-accented Vietnamese keyword dictionary, weighted 3× for merchant hits and 1× for raw-text hits. Thumbnails are cached in the app documents directory under `receipts/`, downscaled to 1024 px and re-encoded as JPEG q82; discarding a scan deletes the cached file instead of leaking it. **Acceptance:** records survive a cold restart, and deleting a transaction removes both the row and its thumbnail. |
| 5 | **Custom Canvas Visualizations** — animated donut/pie + weekly bar chart via `CustomPainter`, no chart library | ✅ Complete | `CategoryDonutChart` and `WeeklyBarChart` are hand-painted. Slices expand from zero sweep along an emphasis curve and the selected slice gains a glow plus an animated centre label; bars grow on staggered `Interval`s over a dashed grid with rounded caps, today's column highlighted, and values revealed on tap. Both charts hit-test taps back to a slice/column and report the selection so the statistics page can show a detail panel. **Acceptance:** charts animate on first build and on data change, respond to taps, and add zero chart dependencies to `pubspec.yaml`. |
| 6 | **Polished UI & Smooth Animation** (extra requirement) | ✅ Complete | A single dark design system (`#070A13` background, `#6C7CFF` primary, `#22D3A8` money accent) with four radii and four durations, plus shared curves `easeOutCubic` and `Cubic(0.22, 1, 0.36, 1)`. Every tappable surface scales to ≈0.96 via `AppTapScale`; lists reveal through `StaggeredEntry` with per-index `Interval`s; `SuccessCheck` draws its tick from path metrics; screens transition with custom `slideUpRoute` / `fadeScaleRoute`. |

---

## 3. TECHNICAL ARCHITECTURE & PROJECT STRUCTURE

### 3.1 Layering and the dependency rule

The project follows Clean Architecture with three layers. Dependencies point inwards only —
`presentation → domain ← data` — and the `domain` layer imports nothing from Flutter or from any
plugin, so the parsing and summary rules are testable in plain Dart.

```
lib/
├── core/                     # Framework-aware helpers shared by the layers above
│   ├── navigation/           # slideUpRoute, fadeScaleRoute
│   ├── theme/                # AppColors, AppGradients, AppRadius, AppDurations, curves
│   └── utils/                # CurrencyFormatter, AppDateFormatter
├── domain/                   # PURE DART — no Flutter, no plugin imports
│   ├── entities/             # Expense, ExpenseCategory, ParsedReceipt,
│   │                         # NormalizedRect, SpendingSummary(+ calculator)
│   ├── repositories/         # ExpenseRepository                (contract)
│   ├── services/             # ReceiptParser, TextRecognizerService,
│   │                         # ReceiptImageStore, CategoryClassifier
│   └── usecases/             # GetExpenses, CreateExpense, UpdateExpense,
│                             # DeleteExpense, ScanReceipt
├── data/                     # Implementations of the domain contracts
│   ├── datasources/          # ExpenseLocalDataSource (sqflite)
│   ├── models/               # ExpenseModel + table / index DDL
│   ├── repositories/         # ExpenseRepositoryImpl
│   └── services/             # MlkitTextRecognizerService,
│                             # HeuristicReceiptParser, FileReceiptImageStore
└── presentation/
    ├── providers/            # ExpenseProvider, ScanSessionController
    ├── widgets/              # glass kit, CustomPainter charts, scan overlay
    └── pages/                # HomeShellPage, DashboardPage, StatsPage,
                              # ScannerPage, ReviewPage
```

`main.dart` is the single **composition root**. Every concrete class — data source, repository,
three services, five use cases — is constructed once in the app state and injected through
`MultiProvider`. Making the root stateful was deliberate: building the object graph inside
`build()` would silently re-create the ML Kit recogniser and the sqflite connection on any rebuild.
`_recognizer.dispose()` and `_localDataSource.close()` release the native resources.

### 3.2 State management flow

`provider` with two `ChangeNotifier`s, each with a single responsibility.

* **`ExpenseProvider`** owns the transaction list and every derived aggregate: all-time, month and
  week summaries, the previous-month comparison, today's total, and the day-grouped row model the
  dashboard renders. Screens never compute money themselves; they read an already-computed value.
* **`ScanSessionController`** is created per scan session by `ReviewPage` and models the pipeline as
  an explicit state machine:

```
start()
  cropping      → FileReceiptImageStore.persist(sourcePath, crop)
  recognizing   → MlkitTextRecognizerService → HeuristicReceiptParser
  ready         → prefilled editable form + CategoryClassifier suggestion
  failed        → retry / manual-entry card
save(draft)     → CreateExpenseUseCase → ExpenseRepositoryImpl → sqflite
                → ExpenseProvider.load() → dashboard + statistics refresh
discard()       → ReceiptImageStore.remove(cachedReceipt)
```

Because the stage is an enum rather than a set of booleans, the review screen cannot render a
half-loaded form: the skeleton, the form and the error card are three mutually exclusive branches.

### 3.3 Exception handling strategy

* Failures are typed, never stringly-typed at the boundaries. `CreateExpenseUseCase` throws
  `InvalidExpenseException` for a non-positive amount; `FileReceiptImageStore` throws
  `ReceiptImageException` when the crop or encode step fails.
* The scan pipeline catches everything at one place — `ScanSessionController.start()` — and converts
  it into `ScanStage.failed` plus an `errorMessage`. The UI therefore degrades into a retry and
  manual-entry path instead of a dead end or a red screen.
* A device with no camera, or a denied camera permission, surfaces as a retry screen in
  `ScannerPage` rather than a crash.
* `_safeNotify()` guards against notifying after disposal, which matters because the async pipeline
  can outlive the page if the user backs out mid-recognition.
* Presentation-level resilience: skeleton placeholders while loading, `EmptyState` when there is no
  data, and `errorBuilder` fallbacks on every `Image.file` so a deleted thumbnail degrades to a
  placeholder icon.

### 3.4 Persistence design

The `expenses` table stores `date` and `created_at` as epoch milliseconds (integer) rather than text,
which makes range queries such as "this month" and "this week" simple integer comparisons, and it
keeps the two indexes (`idx_expenses_date`, `idx_expenses_category`) effective. The database factory
is injectable, so tests can run against `sqflite_common_ffi` in memory instead of a device file. The
image store keeps only a relative path in the row, so the database stays portable and the thumbnails
can be relocated or purged independently.

---

## 4. EMPIRICAL EVIDENCE & SCREENSHOTS

The screenshots below must be captured from a real device — emulator camera feeds are synthetic and
are not readable by ML Kit, so verification on hardware is mandatory. Each figure lists the exact
elements a marker should be able to confirm.

| Figure | Screen | What must be visible to count as evidence |
|---|---|---|
| Fig. 4.1 | Dashboard | Monthly total card, quick stats, day-grouped transaction list with category icons, bottom bar with the raised scan button |
| Fig. 4.2 | Scanner | Live viewfinder with corner brackets over the receipt, flash indicator, and the shutter button |
| Fig. 4.3 | Review (after OCR) | Cropped receipt thumbnail with the confidence badge, plus prefilled amount / merchant / date / category and the amount-candidate chips |
| Fig. 4.4 | Statistics | Animated category donut with its legend, weekly bar chart with a selected column, and the selected-day detail panel |

![Fig. 4.1 — Dashboard](https://github.com/jusskynn97/ocr_expense_tracker/blob/main/01-dashboard.png)

![Fig. 4.2 — Scanner with framing overlay](https://github.com/jusskynn97/ocr_expense_tracker/blob/main/02-scanner.png)

![Fig. 4.3 — Review screen prefilled by OCR](https://github.com/jusskynn97/ocr_expense_tracker/blob/main/03-review.png)

![Fig. 4.4 — Statistics with donut and weekly bar chart](https://github.com/jusskynn97/ocr_expense_tracker/blob/main/04-stats.png)

**Reproduction steps for the marker**

1. `flutter pub get` then `flutter run` on a physical Android device; grant the camera permission.
2. Tap the raised scan button, make sure the `TOTAL` line falls inside the bracket frame, press the
   shutter. A skeleton appears while recognition runs.
3. Confirm the amount, date and merchant are prefilled; edit one field by hand (e.g. change the
   amount to `99.000`), pick a category, and save. The success tick plays and both screens unwind.
4. Open the Statistics tab and confirm the new transaction moved the donut slice and the current
   weekday bar, and that both animated rather than jumping.
5. Kill the app completely and reopen it: the transaction is still listed, which proves persistence.
6. Delete the transaction from the dashboard detail sheet and confirm its thumbnail no longer
   exists on disk.

**Verification status at submission time.** `flutter analyze` reports **0 errors and 0 warnings**
(9 informational `prefer_initializing_formals` hints only — Dart forbids named parameters starting
with an underscore, so those private `_dependency` fields cannot use initialising formals).
`flutter build apk --debug` completes and produces `build/app/outputs/flutter-apk/app-debug.apk`.
A formal on-device latency benchmark for ML Kit inference is not yet recorded; the design goal is
sub-100 ms, and because there is no network round-trip the only latency in the pipeline is on-device
inference plus the JPEG crop/encode step, both of which are already hidden behind the skeleton UI.

---

## 5. TECHNICAL CHALLENGES & RESOLUTIONS

### Challenge 1 — The crop frame must map to the same pixels the user saw

**Problem.** The overlay is drawn over the *preview* widget, which is letterboxed by `AspectRatio`
and additionally rotated on Android, while the crop itself is applied to the *captured photo* at full
sensor resolution. Naively applying `NormalizedRect` to the file produced crops that were shifted and
scaled — the frame on screen and the saved thumbnail disagreed, which is fatal for a cropping
feature.

**Resolution.** Two separate coordinate spaces were introduced and kept apart deliberately.

* The overlay now receives a pixel-space `Rect`, computed by `_fitCenter()`, which replicates the
  preview's aspect-ratio fit inside the available box. The overlay therefore paints exactly where the
  preview pixels are, not where the widget box is.
* The crop is stored as a `NormalizedRect` in 0..1 of the *original* photo, which is resolution
  independent.
* `FileReceiptImageStore.persist()` calls `bakeOrientation()` **before** `copyCrop()`. The ordering is
  the actual fix: if the EXIF rotation is baked after cropping, a 90° rotation moves the selected
  region to a different part of the image entirely. Baking first means the crop rectangle is applied
  to already-upright pixels.

This is also why the scanner exposes three distinct flash states instead of a boolean, and why the
frame is a shared domain constant (`NormalizedRect.receiptFrame`): the scanner, the overlay and the
image store must all refer to the same rectangle.

### Challenge 2 — Regex alone kept picking the wrong number

**Problem.** A first pass that simply took the largest number on the receipt failed on real
Vietnamese bills. Phone numbers (`0912345678`), dates (`18/07/2025`), times (`18:45`) and line-item
quantities were frequently larger or more prominent than the total. Worse, matching the keyword
`TỔNG` never fired even when the receipt literally printed `TỔNG CỘNG`, because ML Kit returns
diacritics inconsistently and the keyword list was compared against un-normalised text.

**Resolution.** The parser was rebuilt around scoring instead of "largest number".

* **Normalise, then match.** All text is de-accented (`TỔNG CỘNG` → `tong cong`) and lowercased
  before any keyword comparison, so the dictionary holds accent-free variants and cannot be defeated
  by OCR diacritic noise.
* **Strip the decoys first.** Date-like, time-like and phone-like digit runs are removed from the
  line before any amount token is considered, so they can never be selected. Year-shaped numbers
  (1900–2100) are additionally ignored in date context.
* **Score lines, not numbers.** `_totalKeywords` is a weighted table
  (`tong cong` 130, `tong thanh toan` 115, `thanh toan` 100, `total` 92, `tong` 55, `tam tinh` 30)
  and each candidate is adjusted by currency markers and line position, so `TỔNG CỘNG` beats a larger
  line-item figure. A hard `_negativeKeywords` list (`tien khach dua`, `tien thua`, `giam gia`,
  `voucher`, `change due`, `tich diem`) disqualifies a line outright, and a soft list (`vat`, `thue`,
  `don gia`, `so luong`, `price`) demotes it.
* **Repair instead of reject.** A future date is re-read with day and month swapped when that yields a
  valid past date, which recovers receipts printed in US order.
* **Be honest about uncertainty.** The parser returns every plausible candidate plus a confidence
  score (0.6 keyword-driven / 0.42 bare amount, +0.22 date, +0.18 merchant). The review screen shows
  the candidates as chips — the design accepts that heuristics are imperfect and turns the residue
  into a one-tap correction rather than a silent wrong answer.

### Challenge 3 — Canvas hit-testing and staggered animation

**Problem.** Painting the charts was straightforward; making them *feel* right was not. Two issues
appeared. First, a tapped donut had to resolve back to a slice, but a slice owns a start sweep, an
end sweep and a radial band, so a naive bounds check either double-selected or missed entirely.
Second, an early attempt at staggering the bars used
`CurvedAnimation(parent: AlwaysStoppedAnimation(animation), curve: Interval(...)).value`, which
silently returns the value at `t = 0` — every bar stayed at zero height and the chart rendered empty.

**Resolution.**

* **Hit-testing in polar space.** The tap offset is converted to a vector from the centre, its angle
  computed with `atan2(dy, dx)`, normalised into `[-π/2, 3π/2)`, and matched against each slice's
  cumulative sweep; the radius is checked against the inner and outer band so taps in the hole are
  ignored. Bar charts are simpler: the tap `x` selects a column index, which the page receives
  through a callback and renders in a detail panel.
* **Transform, don't wrap.** The staggering now uses
  `Interval(start, end, curve: kAppEmphasisCurve).transform(animation)` — a direct transform of the
  controller value — which is what actually produces a per-bar offset. Bars therefore leave the
  baseline in sequence and land on their real values together.
* **Animate data, not just paint.** Both painters take an `animation` value and recompute geometry
  every frame on `repaint`, so changing the month or the selected slice re-animates from the current
  state instead of snapping to the new one.

Together these three resolutions are what the "smooth, good-looking UI" requirement actually reduced
to in code: keep the coordinate systems honest, keep the heuristics explainable, and drive every
visual change from a real animation value rather than an instantaneous repaint.
