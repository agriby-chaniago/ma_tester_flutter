# 🧪 Test Case Details Feature Guide

## Overview

Sekarang aplikasi Flutter menampilkan **detail lengkap per test case** dengan verification steps yang sesuai dengan BLACKBOX_TEST_REPORT.md.

## Features

### ✅ Detail Per Test Case

Setiap test case sekarang memiliki:

- **Test Details**: Endpoint, Method, Priority, Category, HTTP Status
- **Verification Steps**: Langkah-langkah verifikasi dengan expected & actual results
- **Actual Results**: Data hasil testing yang dikumpulkan otomatis
- **Notes**: Catatan tambahan (jika ada error)
- **Status Badge**: PASS/FAIL/PENDING dengan warna visual

### 📋 Verification Steps

Setiap test case memiliki steps yang detail, contoh untuk TC-001 (Health Check):

1. Send GET request to `/` → Expected: HTTP 200 OK
2. Verify `status` field → Expected: Value: "ok"
3. Verify `ready` field → Expected: Value: true
4. Verify `api_version` field → Expected: Value: "2.0.0"
5. Verify `device` field → Expected: Contains device info
6. Verify `x-request-id` header → Expected: UUID format present

### 🎯 Test Cases Coverage

Aplikasi sudah menyediakan template untuk 9 test cases:

- **TC-001**: Health Check - GET /
- **TC-002**: Model Info - GET /model_info
- **TC-003**: Metrics Basic - GET /metrics_basic
- **TC-004**: Predict PNG Format - POST /predict?fmt=png
- **TC-005**: Predict Proba Format - POST /predict?fmt=proba (dengan "0-255 probability values")
- **TC-006**: Predict Compact Format - POST /predict?fmt=compact
- **TC-007**: Predict JSON Full Format - POST /predict?fmt=json
- **TC-008**: Batch Prediction Compact - POST /predict_batch?fmt=compact
- **TC-009**: Batch Prediction Stats - POST /predict_batch?fmt=stats

## How to Use

### 1. Run API Test

1. Buka aplikasi Flutter
2. Pastikan sudah di tab **"API Test"** (tab pertama)
3. Tekan tombol **"Run All Tests"**
4. Tunggu semua test berjalan (progress bar akan bergerak 0-100%)

### 2. View Test Report

Setelah test selesai, akan muncul halaman **"Test Report"** dengan:

- **Summary Cards**: Jumlah test PASS dan FAIL
- **List Test Cases**: Semua test case dengan:
  - Status icon (✅ hijau untuk PASS, ❌ merah untuk FAIL)
  - Nama test case lengkap
  - Method dan endpoint
  - Badge untuk Priority, Category, dan HTTP Status
  - Jumlah verification steps

### 3. View Detailed Verification Steps

**Klik pada salah satu test case** untuk melihat:

#### Header Card

- Test ID (TC-001, TC-002, dst.)
- Test name lengkap
- Status badge besar (PASS/FAIL/PENDING)

#### Test Details Card

- Endpoint: GET/POST dengan path
- Priority: High/Medium/Low
- Category: Functional/Negative Testing
- HTTP Status: 200, 404, dst. (dengan warna hijau/merah)

#### Verification Steps Card

Setiap step ditampilkan dengan:

- **Step Number**: 1, 2, 3, dst. dalam circle badge
- **Action**: Apa yang dilakukan (e.g., "Send GET request to `/`")
- **Expected Result**: Hasil yang diharapkan
- **Actual Result**: Hasil aktual dari testing (auto-filled)
- **Status Indicator**:
  - ✅ Hijau = verified & passed
  - 🟠 Orange = has actual result but needs manual verification
  - ⬜ Abu-abu = no actual result yet

#### Actual Results Card (if available)

Menampilkan semua field hasil testing:

```
status: "ok"
ready: true
api_version: "2.0.0"
device: "cuda"
x-request-id: "UUID present"
```

#### Notes Card

Catatan tambahan, terutama jika ada error atau kegagalan test.

## Example: TC-005 (Probability Values)

Untuk test case yang Anda tanyakan sebelumnya (**"0-255 probability values"**):

**TC-005: Single Prediction - Probability Map PNG**

**Verification Steps:**

1. Prepare valid fundus image → Expected: File < 8MB
2. Send POST to `/predict?fmt=proba` → Expected: HTTP 200 OK
3. Verify Content-Type header → Expected: "image/png"
4. **Verify PNG is grayscale** → **Expected: 0-255 probability values** ✨
5. Verify `x-output-type` header → Expected: "probability_u8"

Ketika test berjalan, kolom "Actual Result" akan terisi otomatis dengan:

- HTTP 200 (jika berhasil)
- Content-Type: image/png
- PNG Valid: Grayscale 0-255 ✅
- x-output-type: probability_u8

## Files Structure

```
lib/
├── models/
│   └── test_case_detail.dart          # Model untuk DetailedTestCase & TestCaseVerification
├── pages/
│   ├── test_runner_page.dart          # Main test runner dengan _detailedTestCases
│   └── test_case_detail_page.dart     # Page untuk menampilkan detail per test case
```

### Key Classes

#### `DetailedTestCase`

```dart
class DetailedTestCase {
  final String caseId;                    // TC-001, TC-002, dst.
  final String name;                      // Full test name
  final String endpoint;                  // /predict, /model_info, dst.
  final String method;                    // GET, POST
  final String priority;                  // High, Medium, Low
  final String category;                  // Functional, Negative Testing
  final List<TestCaseVerification> verifications;  // Steps

  int? actualStatusCode;                  // Filled after test runs
  Map<String, dynamic>? actualResults;    // Filled after test runs
  String? overallStatus;                  // PASS/FAIL/PENDING
  String? notes;                          // Additional notes
}
```

#### `TestCaseVerification`

```dart
class TestCaseVerification {
  final String step;            // "1", "2", "3"
  final String action;          // "Send GET request to `/`"
  final String expectedResult;  // "HTTP 200 OK"
  String? actualResult;         // Auto-filled: "HTTP 200"
  bool? isVerified;             // Auto-determined: true/false
}
```

#### `TestCaseTemplates`

Provides static methods untuk semua test case templates:

- `tc001HealthCheck()`
- `tc002ModelInfo()`
- `tc003MetricsBasic()`
- `tc004PredictPng()`
- `tc005PredictProba()` ← **Yang memiliki "0-255 probability values"**
- `tc006PredictCompact()`
- `tc007PredictJson()`
- `tc008BatchCompact()`
- `tc009BatchStats()`

## Auto-Fill Logic

Saat test dijalankan, aplikasi otomatis mengisi:

1. **HTTP Status Code** → Step 1 atau 2 yang mengandung "HTTP"
2. **API Response Fields** → Matched dengan verification steps
3. **Verification Status** → ✅ jika actual = expected

Method yang bertanggung jawab:

```dart
void _updateDetailedTestCase(String caseId, {
  required int statusCode,
  required bool passed,
  Map<String, dynamic>? actualResults,
  String? notes,
});

void _autoFillVerifications(DetailedTestCase testCase, Map<String, dynamic> results);
```

## Benefits

✅ **Lengkap** - Semua detail yang dibutuhkan untuk mengisi BLACKBOX_TEST_REPORT.md
✅ **Visual** - Status dengan warna, badge, dan icon yang jelas
✅ **Interaktif** - Tap untuk melihat detail lengkap per test case
✅ **Auto-filled** - Hasil testing otomatis diisi saat test dijalankan
✅ **Traceable** - Setiap verification step terlacak dengan jelas
✅ **Report-ready** - Data bisa langsung digunakan untuk mengisi laporan

## Next Steps

Untuk mengisi BLACKBOX_TEST_REPORT.md:

1. Run test di aplikasi Flutter
2. Tap pada setiap test case untuk melihat detail
3. Catat **Actual Result** dari setiap verification step
4. Copy data ke tabel "Actual Result" di laporan
5. Isi kolom "Status" (✅ Pass / ❌ Fail) berdasarkan hasil
6. Tambahkan Notes jika diperlukan

## Screenshots Flow

```
[Run All Tests Button]
         ↓
[Progress Bar: 0% → 100%]
         ↓
[Test Report Summary]
├─ 9 Passed (hijau)
└─ 0 Failed (merah)
         ↓
[List of Test Cases]
├─ TC-001: Health Check ✅ → [TAP]
├─ TC-002: Model Info ✅ → [TAP]
├─ TC-003: Metrics Basic ✅ → [TAP]
├─ TC-004: Predict PNG ✅ → [TAP]
├─ TC-005: Predict Proba ✅ → [TAP] ← **Has "0-255 probability values"**
├─ TC-006: Predict Compact ✅ → [TAP]
├─ TC-007: Predict JSON ✅ → [TAP]
├─ TC-008: Batch Compact ✅ → [TAP]
└─ TC-009: Batch Stats ✅ → [TAP]
         ↓
[Test Case Detail Page]
├─ Header Card (Status)
├─ Test Details Card (Endpoint, Priority, Category)
├─ Verification Steps Card
│  ├─ Step 1: ✅ [Expected vs Actual]
│  ├─ Step 2: ✅ [Expected vs Actual]
│  ├─ Step 3: ✅ [Expected vs Actual]
│  └─ ...
├─ Actual Results Card (Raw data)
└─ Notes Card
```

---

**Sekarang aplikasi sudah menampilkan semua yang dibutuhkan untuk mengisi BLACKBOX_TEST_REPORT.md!** 🎉
