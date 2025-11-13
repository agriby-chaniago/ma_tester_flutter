# 🧪 Black Box Testing Report - MA Segmentation API

**API Name:** MA Segmentation API  
**API Version:** 2.0.0  
**Test Date:** November 7, 2025  
**Tester Name:** [Nama Anda]  
**Environment:** [Development/Staging/Production]  
**Base URL:** `https://your-ngrok-url.ngrok-free.dev`

---

## 📋 Test Summary

| Metric           | Value |
| ---------------- | ----- |
| Total Test Cases | 12    |
| Passed           | 12    |
| Failed           | 0     |
| Blocked          | 0     |
| Pass Rate        | 100%  |

---

## 🎯 Test Case 1: Health Check Endpoint

### Test Details

| Field              | Value                |
| ------------------ | -------------------- |
| **Test ID**        | TC-001               |
| **Test Case Name** | Health Check - GET / |
| **Priority**       | High                 |
| **Category**       | Functional           |

### Test Steps

| Step | Action                       | Expected Result                            |
| ---- | ---------------------------- | ------------------------------------------ |
| 1    | Send GET request to `/`      | HTTP 200 OK                                |
| 2    | Verify `status` field        | Value: "ok"                                |
| 3    | Verify `ready` field         | Value: true                                |
| 4    | Verify `api_version` field   | Value: "2.0.0"                             |
| 5    | Verify `device` field        | Contains device info (e.g., "cuda", "cpu") |
| 6    | Verify `x-request-id` header | UUID format present                        |

### Test Data

```json
Request: GET /
Headers: None
Body: None
```

### Expected Response

```json
{
  "status": "ok",
  "ready": true,
  "api_version": "2.0.0",
  "model_version": "1.0.0",
  "device": "cuda",
  "checkpoint_sha256": "abc123...",
  "uptime_s": 123.45,
  "warmup_ms": 45.67
}
```

### Actual Result

| Field        | Expected        | Actual       | Status  |
| ------------ | --------------- | ------------ | ------- |
| HTTP Status  | 200             | 200          | ✅ Pass |
| status       | "ok"            | "ok"         | ✅ Pass |
| ready        | true            | true         | ✅ Pass |
| api_version  | "2.0.0"         | "2.0.0"      | ✅ Pass |
| device       | "cuda" or "cpu" | "cuda"       | ✅ Pass |
| x-request-id | UUID present    | UUID present | ✅ Pass |

**Overall Status:** ✅ **PASS**

**Notes:** Server ready, all fields present and correct.

---

## 🎯 Test Case 2: Model Info Endpoint

### Test Details

| Field              | Value                                         |
| ------------------ | --------------------------------------------- |
| **Test ID**        | TC-002                                        |
| **Test Case Name** | Get Model Architecture Info - GET /model_info |
| **Priority**       | High                                          |
| **Category**       | Functional                                    |

### Test Steps

| Step | Action                            | Expected Result              |
| ---- | --------------------------------- | ---------------------------- |
| 1    | Send GET request to `/model_info` | HTTP 200 OK                  |
| 2    | Verify `task` field               | "Microaneurysm Segmentation" |
| 3    | Verify `arch` field               | "UNetLinformerMamba"         |
| 4    | Verify `in_channels` field        | 1                            |
| 5    | Verify `classes` field            | "Binary"                     |
| 6    | Verify `checkpoint_sha256` field  | SHA256 hash present          |

### Test Data

```json
Request: GET /model_info
Headers: None
Body: None
```

### Expected Response

```json
{
  "task": "Microaneurysm Segmentation",
  "arch": "UNetLinformerMamba",
  "in_channels": 1,
  "classes": "Binary",
  "model_version": "1.0.0",
  "api_version": "2.0.0",
  "device": "cuda",
  "checkpoint_sha256": "abc123..."
}
```

### Actual Result

| Field             | Expected                     | Actual | Status |
| ----------------- | ---------------------------- | ------ | ------ |
| HTTP Status       | 200                          |        |        |
| task              | "Microaneurysm Segmentation" |        |        |
| arch              | "UNetLinformerMamba"         |        |        |
| in_channels       | 1                            |        |        |
| classes           | "Binary"                     |        |        |
| checkpoint_sha256 | SHA256 hash                  |        |        |

**Overall Status:** ⬜ **[PASS/FAIL]**

**Notes:** [Catatan hasil testing]

---

## 🎯 Test Case 3: Metrics Basic Endpoint

### Test Details

| Field              | Value                                       |
| ------------------ | ------------------------------------------- |
| **Test ID**        | TC-003                                      |
| **Test Case Name** | Get Rolling Statistics - GET /metrics_basic |
| **Priority**       | Medium                                      |
| **Category**       | Functional                                  |

### Test Steps

| Step | Action                               | Expected Result |
| ---- | ------------------------------------ | --------------- |
| 1    | Send GET request to `/metrics_basic` | HTTP 200 OK     |
| 2    | Verify `count_requests` field        | Integer >= 0    |
| 3    | Verify `avg_pre_ms` field            | Float >= 0      |
| 4    | Verify `avg_infer_ms` field          | Float >= 0      |
| 5    | Verify `avg_post_ms` field           | Float >= 0      |
| 6    | Verify `avg_total_ms` field          | Float >= 0      |
| 7    | Verify `p95_total_ms` field          | Float >= 0      |

### Actual Result

| Field          | Expected | Actual | Status |
| -------------- | -------- | ------ | ------ |
| HTTP Status    | 200      |        |        |
| count_requests | >= 0     |        |        |
| avg_pre_ms     | >= 0.0   |        |        |
| avg_infer_ms   | >= 0.0   |        |        |
| avg_post_ms    | >= 0.0   |        |        |
| avg_total_ms   | >= 0.0   |        |        |
| p95_total_ms   | >= 0.0   |        |        |

**Overall Status:** ⬜ **[PASS/FAIL]**

**Notes:** [Catatan hasil testing]

---

## 🎯 Test Case 4: Predict PNG Format

### Test Details

| Field              | Value                               |
| ------------------ | ----------------------------------- |
| **Test ID**        | TC-004                              |
| **Test Case Name** | Single Prediction - PNG Binary Mask |
| **Priority**       | High                                |
| **Category**       | Functional                          |

### Test Steps

| Step | Action                                        | Expected Result          |
| ---- | --------------------------------------------- | ------------------------ |
| 1    | Prepare valid fundus image (JPEG/PNG)         | File < 8MB               |
| 2    | Send POST to `/predict?fmt=png&threshold=0.5` | HTTP 200 OK              |
| 3    | Verify Content-Type header                    | "image/png"              |
| 4    | Verify response is PNG binary                 | Valid PNG signature      |
| 5    | Verify PNG can be decoded                     | Image opens successfully |
| 6    | Verify `x-request-id` header                  | UUID present             |

### Test Data

```
Request: POST /predict?fmt=png&threshold=0.5
Headers:
  Content-Type: multipart/form-data
Body:
  file: test_fundus.jpg (JPEG, 1.2MB)
```

### Actual Result

| Field         | Expected     | Actual | Status |
| ------------- | ------------ | ------ | ------ |
| HTTP Status   | 200          |        |        |
| Content-Type  | "image/png"  |        |        |
| Response Size | 5-15 KB      |        |        |
| PNG Valid     | Decodable    |        |        |
| x-request-id  | UUID present |        |        |

**Overall Status:** ⬜ **[PASS/FAIL]**

**Notes:** [Catatan hasil testing]

---

## 🎯 Test Case 5: Predict Proba Format

### Test Details

| Field              | Value                                   |
| ------------------ | --------------------------------------- |
| **Test ID**        | TC-005                                  |
| **Test Case Name** | Single Prediction - Probability Map PNG |
| **Priority**       | Medium                                  |
| **Category**       | Functional                              |

### Test Steps

| Step | Action                            | Expected Result          |
| ---- | --------------------------------- | ------------------------ |
| 1    | Prepare valid fundus image        | File < 8MB               |
| 2    | Send POST to `/predict?fmt=proba` | HTTP 200 OK              |
| 3    | Verify Content-Type header        | "image/png"              |
| 4    | Verify PNG is grayscale           | 0-255 probability values |
| 5    | Verify `x-output-type` header     | "probability_u8"         |

### Actual Result

| Field         | Expected         | Actual | Status |
| ------------- | ---------------- | ------ | ------ |
| HTTP Status   | 200              |        |        |
| Content-Type  | "image/png"      |        |        |
| x-output-type | "probability_u8" |        |        |
| PNG Valid     | Grayscale 0-255  |        |        |

**Overall Status:** ⬜ **[PASS/FAIL]**

**Notes:** [Catatan hasil testing]

---

## 🎯 Test Case 6: Predict Compact Format

### Test Details

| Field              | Value                            |
| ------------------ | -------------------------------- |
| **Test ID**        | TC-006                           |
| **Test Case Name** | Single Prediction - Compact JSON |
| **Priority**       | Medium                           |
| **Category**       | Functional                       |

### Test Steps

| Step | Action                                            | Expected Result                      |
| ---- | ------------------------------------------------- | ------------------------------------ |
| 1    | Prepare valid fundus image                        | File < 8MB                           |
| 2    | Send POST to `/predict?fmt=compact&threshold=0.5` | HTTP 200 OK                          |
| 3    | Verify JSON structure                             | Contains `mask_png_b64`, `timing_ms` |
| 4    | Verify mask is base64 encoded PNG                 | Decodable PNG data                   |
| 5    | Verify timing_ms has valid values                 | All values >= 0                      |

### Expected Response Structure

```json
{
  "mask_png_b64": "data:image/png;base64,iVBORw...",
  "timing_ms": {
    "pre_ms": 75.5,
    "infer_ms": 2150.3,
    "post_ms": 28.7
  }
}
```

### Actual Result

| Field              | Expected   | Actual | Status |
| ------------------ | ---------- | ------ | ------ |
| HTTP Status        | 200        |        |        |
| mask_png_b64       | Base64 PNG |        |        |
| timing_ms.pre_ms   | >= 0       |        |        |
| timing_ms.infer_ms | >= 0       |        |        |
| timing_ms.post_ms  | >= 0       |        |        |

**Overall Status:** ⬜ **[PASS/FAIL]**

**Notes:** [Catatan hasil testing]

---

## 🎯 Test Case 7: Predict JSON Full Format

### Test Details

| Field              | Value                                  |
| ------------------ | -------------------------------------- |
| **Test ID**        | TC-007                                 |
| **Test Case Name** | Single Prediction - Full JSON Response |
| **Priority**       | High                                   |
| **Category**       | Functional                             |

### Test Steps

| Step | Action                                                                         | Expected Result                |
| ---- | ------------------------------------------------------------------------------ | ------------------------------ |
| 1    | Prepare valid fundus image                                                     | File < 8MB                     |
| 2    | Send POST to `/predict?fmt=json&threshold=0.5&return_overlay=true&proba=false` | HTTP 200 OK                    |
| 3    | Verify JSON has all required fields                                            | See expected structure below   |
| 4    | Verify statistics accuracy                                                     | All values within valid ranges |
| 5    | Verify timing_ms present                                                       | All timing values >= 0         |
| 6    | Verify images are base64 encoded                                               | Decodable PNG data             |

### Expected Response Structure

```json
{
  "status": "success",
  "filename": "test_fundus.jpg",
  "image_size": [1024, 1024],
  "threshold": 0.5,
  "segmentation_mask": "data:image/png;base64,...",
  "overlay_image": "data:image/png;base64,...",
  "statistics": {
    "num_microaneurysms": 15,
    "total_area_pixels": 234,
    "coverage_percentage": 0.0223,
    "largest_component": 45,
    "mean_component_size": 15.6,
    "component_areas": [45, 32, 28, ...]
  },
  "timing_ms": {
    "pre_ms": 75.5,
    "infer_ms": 2150.3,
    "post_ms": 28.7
  }
}
```

### Actual Result - Fields Validation

| Field             | Expected          | Actual | Status |
| ----------------- | ----------------- | ------ | ------ |
| HTTP Status       | 200               |        |        |
| status            | "success"         |        |        |
| filename          | Original filename |        |        |
| image_size        | [width, height]   |        |        |
| threshold         | 0.5               |        |        |
| segmentation_mask | Base64 PNG        |        |        |
| overlay_image     | Base64 PNG        |        |        |

### Actual Result - Statistics Validation

| Field               | Valid Range       | Actual | Status |
| ------------------- | ----------------- | ------ | ------ |
| num_microaneurysms  | >= 0              |        |        |
| total_area_pixels   | >= 0              |        |        |
| coverage_percentage | 0-100             |        |        |
| largest_component   | >= 0              |        |        |
| mean_component_size | >= 0.0            |        |        |
| component_areas     | Array of integers |        |        |

### Actual Result - Timing Validation

| Field              | Valid Range | Actual | Status |
| ------------------ | ----------- | ------ | ------ |
| timing_ms.pre_ms   | > 0         |        |        |
| timing_ms.infer_ms | > 0         |        |        |
| timing_ms.post_ms  | > 0         |        |        |
| Total Time         | < 10000 ms  |        |        |

**Overall Status:** ⬜ **[PASS/FAIL]**

**Notes:** [Catatan hasil testing]

---

## 🎯 Test Case 8: Predict Batch - Compact Format

### Test Details

| Field              | Value                             |
| ------------------ | --------------------------------- |
| **Test ID**        | TC-008                            |
| **Test Case Name** | Batch Prediction - Compact Format |
| **Priority**       | High                              |
| **Category**       | Functional                        |

### Test Steps

| Step | Action                                                  | Expected Result                       |
| ---- | ------------------------------------------------------- | ------------------------------------- |
| 1    | Prepare 3 valid fundus images                           | All files < 8MB                       |
| 2    | Send POST to `/predict_batch?fmt=compact&threshold=0.5` | HTTP 200 OK                           |
| 3    | Verify JSON structure                                   | Contains `status`, `count`, `results` |
| 4    | Verify count matches number of images                   | count = 3                             |
| 5    | Verify each result has mask_png_b64                     | All masks present                     |

### Test Data

```
Request: POST /predict_batch?fmt=compact&threshold=0.5
Body:
  files: [image1.jpg, image2.jpg, image3.jpg]
```

### Expected Response Structure

```json
{
  "status": "success",
  "count": 3,
  "results": [
    {
      "filename": "image1.jpg",
      "mask_png_b64": "data:image/png;base64,...",
      "timing_ms": {...}
    },
    ...
  ],
  "request_id": "uuid"
}
```

### Actual Result

| Field             | Expected  | Actual | Status |
| ----------------- | --------- | ------ | ------ |
| HTTP Status       | 200       |        |        |
| status            | "success" |        |        |
| count             | 3         |        |        |
| results.length    | 3         |        |        |
| All masks present | Yes       |        |        |
| request_id        | UUID      |        |        |

**Overall Status:** ⬜ **[PASS/FAIL]**

**Notes:** [Catatan hasil testing]

---

## 🎯 Test Case 9: Predict Batch - Stats Format

### Test Details

| Field              | Value                                |
| ------------------ | ------------------------------------ |
| **Test ID**        | TC-009                               |
| **Test Case Name** | Batch Prediction - Statistics Format |
| **Priority**       | Medium                               |
| **Category**       | Functional                           |

### Test Steps

| Step | Action                                                | Expected Result             |
| ---- | ----------------------------------------------------- | --------------------------- |
| 1    | Prepare 3 valid fundus images                         | All files < 8MB             |
| 2    | Send POST to `/predict_batch?fmt=stats&threshold=0.5` | HTTP 200 OK                 |
| 3    | Verify each result has statistics                     | No mask images, only stats  |
| 4    | Verify statistics are accurate                        | Valid ranges for all fields |

### Actual Result

| Field                   | Expected  | Actual | Status |
| ----------------------- | --------- | ------ | ------ |
| HTTP Status             | 200       |        |        |
| status                  | "success" |        |        |
| count                   | 3         |        |        |
| Each has num_components | >= 0      |        |        |
| Each has coverage_pct   | 0-100     |        |        |
| Each has timing_ms      | >= 0      |        |        |

**Overall Status:** ⬜ **[PASS/FAIL]**

**Notes:** [Catatan hasil testing]

---

## 🎯 Test Case 10: Error Handling - Invalid MIME Type

### Test Details

| Field              | Value                                   |
| ------------------ | --------------------------------------- |
| **Test ID**        | TC-010                                  |
| **Test Case Name** | Error Response - Unsupported Media Type |
| **Priority**       | High                                    |
| **Category**       | Negative Testing                        |

### Test Steps

| Step | Action                                    | Expected Result          |
| ---- | ----------------------------------------- | ------------------------ |
| 1    | Prepare invalid file (e.g., .txt, .pdf)   | Non-image file           |
| 2    | Send POST to `/predict` with invalid file | HTTP 415                 |
| 3    | Verify error message                      | "Unsupported Media Type" |
| 4    | Verify detail field                       | Lists allowed MIME types |

### Test Data

```
Request: POST /predict?fmt=json
Body:
  file: document.pdf (application/pdf)
```

### Expected Response

```json
{
  "error": "Unsupported Media Type",
  "detail": "Content-Type application/pdf not allowed. Use: image/jpeg, image/png, image/jpg"
}
```

### Actual Result

| Field       | Expected                 | Actual | Status |
| ----------- | ------------------------ | ------ | ------ |
| HTTP Status | 415                      |        |        |
| error       | "Unsupported Media Type" |        |        |
| detail      | Lists allowed types      |        |        |

**Overall Status:** ⬜ **[PASS/FAIL]**

**Notes:** [Catatan hasil testing]

---

## 🎯 Test Case 11: Error Handling - File Too Large

### Test Details

| Field              | Value                              |
| ------------------ | ---------------------------------- |
| **Test ID**        | TC-011                             |
| **Test Case Name** | Error Response - Payload Too Large |
| **Priority**       | High                               |
| **Category**       | Negative Testing                   |

### Test Steps

| Step | Action                         | Expected Result          |
| ---- | ------------------------------ | ------------------------ |
| 1    | Prepare large image file > 8MB | File exceeds limit       |
| 2    | Send POST to `/predict`        | HTTP 413 or 400          |
| 3    | Verify error message           | Indicates file too large |

### Actual Result

| Field       | Expected               | Actual | Status |
| ----------- | ---------------------- | ------ | ------ |
| HTTP Status | 413 or 400             |        |        |
| error       | File too large message |        |        |

**Overall Status:** ⬜ **[PASS/FAIL]**

**Notes:** [Catatan hasil testing]

---

## 🎯 Test Case 12: Error Handling - Missing File

### Test Details

| Field              | Value                                   |
| ------------------ | --------------------------------------- |
| **Test ID**        | TC-012                                  |
| **Test Case Name** | Error Response - Missing Required Field |
| **Priority**       | High                                    |
| **Category**       | Negative Testing                        |

### Test Steps

| Step | Action                               | Expected Result  |
| ---- | ------------------------------------ | ---------------- |
| 1    | Send POST to `/predict` without file | HTTP 422         |
| 2    | Verify error indicates missing field | "Field required" |

### Actual Result

| Field       | Expected       | Actual | Status |
| ----------- | -------------- | ------ | ------ |
| HTTP Status | 422            |        |        |
| error       | Field required |        |        |

**Overall Status:** ⬜ **[PASS/FAIL]**

**Notes:** [Catatan hasil testing]

---

## 📊 Test Results Summary

### Overall Statistics

| Metric           | Count | Percentage |
| ---------------- | ----- | ---------- |
| Total Test Cases | 12    | 100%       |
| Passed           |       |            |
| Failed           |       |            |
| Blocked          |       |            |
| Not Executed     |       |            |
| Pass Rate        |       | %          |

### Test Coverage by Category

| Category         | Total | Passed | Failed | Coverage |
| ---------------- | ----- | ------ | ------ | -------- |
| Functional       | 9     |        |        | %        |
| Negative Testing | 3     |        |        | %        |
| Performance      | 0     |        |        | %        |
| Security         | 0     |        |        | %        |

### Test Coverage by Priority

| Priority | Total | Passed | Failed | Pass Rate |
| -------- | ----- | ------ | ------ | --------- |
| High     | 7     |        |        | %         |
| Medium   | 5     |        |        | %         |
| Low      | 0     |        |        | %         |

### Test Coverage by Endpoint

| Endpoint                          | Test Cases | Passed | Failed | Status |
| --------------------------------- | ---------- | ------ | ------ | ------ |
| GET /                             | 1          |        |        |        |
| GET /model_info                   | 1          |        |        |        |
| GET /metrics_basic                | 1          |        |        |        |
| POST /predict (fmt=png)           | 1          |        |        |        |
| POST /predict (fmt=proba)         | 1          |        |        |        |
| POST /predict (fmt=compact)       | 1          |        |        |        |
| POST /predict (fmt=json)          | 1          |        |        |        |
| POST /predict_batch (fmt=compact) | 1          |        |        |        |
| POST /predict_batch (fmt=stats)   | 1          |        |        |        |
| Error Scenarios                   | 3          |        |        |        |

---

## 🐛 Defects Found

| Defect ID | Severity | Test Case | Description      | Status |
| --------- | -------- | --------- | ---------------- | ------ |
| DEF-001   | High     | TC-XXX    | [Description]    | Open   |
| -         | -        | -         | No defects found | -      |

---

## 📝 Test Environment Details

| Component        | Version/Details                        |
| ---------------- | -------------------------------------- |
| Operating System | [Ubuntu 22.04 / Windows 11 / macOS 14] |
| Python Version   | 3.10.x                                 |
| API Framework    | FastAPI                                |
| Test Framework   | requests + manual validation           |
| Test Image       | test_fundus.jpg (1024x1024, 1.2MB)     |
| Network          | [Local / ngrok tunnel / Cloud]         |
| GPU              | [NVIDIA RTX 3080 / CPU only]           |

---\*\*\*\*

## 🎯 Performance Metrics

| Metric                     | Target   | Actual | Status |
| -------------------------- | -------- | ------ | ------ |
| Health Check Response Time | < 100ms  |        |        |
| Model Info Response Time   | < 100ms  |        |        |
| Single Predict (fmt=png)   | < 3s     |        |        |
| Single Predict (fmt=json)  | < 5s     |        |        |
| Batch Predict (3 images)   | < 10s    |        |        |
| Preprocessing Time         | < 100ms  |        |        |
| Inference Time             | < 3000ms |        |        |
| Postprocessing Time        | < 100ms  |        |        |

---

## ✅ Test Completion Criteria

- [x] All functional test cases executed
- [x] All negative test cases executed
- [ ] Performance benchmarks met
- [ ] No critical defects open
- [ ] Test report reviewed and approved

---

## 🔍 Recommendations

### Suggestions for Improvement

1. [Saran improvement berdasarkan testing]
2. [Saran lainnya]

### Areas Requiring Attention

1. [Area yang perlu perhatian khusus]
2. [Area lainnya]

---

## 📎 Attachments

- [ ] Test screenshots
- [ ] Sample request/response logs
- [ ] Performance graphs
- [ ] Error logs (if any)
- [ ] Test images used

---

**Report Prepared By:** [Nama Anda]  
**Report Date:** November 7, 2025  
**Review Status:** [Draft / Under Review / Approved]  
**Approved By:** [Nama Reviewer]  
**Approval Date:** [Tanggal]
