# 🔄 Auto-Retry Feature

## Overview

Aplikasi sekarang dilengkapi dengan **automatic retry logic** untuk mengatasi network errors yang sering terjadi saat testing dengan ngrok.

## Features

### ✅ Smart Retry Logic

- **Max Retries**: 2 kali retry otomatis
- **Progressive Delay**: 2 detik (attempt 1), 4 detik (attempt 2)
- **Handled Errors**:
  - Connection closed before full header received
  - Connection reset by peer
  - Connection refused
  - Socket exceptions

### 🎯 When Retry Happens

Retry akan otomatis berjalan jika terjadi:

1. **Network Timeout** - Koneksi ngrok terputus
2. **Connection Closed** - Server close connection sebelum response lengkap
3. **Socket Errors** - Low-level network errors

### 📊 Visual Feedback

Saat retry terjadi, Anda akan melihat log:

```
Testing POST /predict?fmt=compact...
⚠️ Connection error, will retry: HttpException: Connection closed before...
↻ Retry attempt 1/2...
✓ POST /predict?fmt=compact passed (11955.0ms)
```

### ❌ If All Retries Fail

Jika setelah 2 retry masih gagal:

```
✗ POST /predict?fmt=compact failed after 2 attempts (HTTP 0): ...
```

Test case akan ditandai:

- **Status**: ❌ FAIL
- **Actual Result**: "Connection Error (failed after 2 retries)"
- **Notes**: Detail error lengkap

## Error Detection

Aplikasi mendeteksi connection errors dari keywords:

- `Connection closed`
- `Connection reset`
- `Connection refused`
- `SocketException`

## Benefits

✅ **Resilient Testing** - Tests tidak langsung fail karena network glitch  
✅ **Better Success Rate** - Ngrok yang unstable tidak langsung menyebabkan test failure  
✅ **Transparent** - User bisa lihat berapa kali retry dilakukan  
✅ **Smart Delay** - Progressive delay mencegah network congestion

## Implementation Details

### Code Structure

```dart
Map<String, dynamic>? resp;
Stopwatch? sw;
int retryCount = 0;
const maxRetries = 2;
bool success = false;

// Retry logic
while (retryCount <= maxRetries && !success) {
  try {
    if (retryCount > 0) {
      _log('  ↻ Retry attempt $retryCount/$maxRetries...');
      await Future.delayed(Duration(seconds: retryCount * 2));
    }

    sw = Stopwatch()..start();
    resp = await api.predictMultipart(...);
    sw.stop();
    success = true;
  } catch (e) {
    retryCount++;
    if (retryCount > maxRetries) {
      rethrow;
    }
    _log('  ⚠️ Connection error, will retry...');
  }
}
```

### Progressive Delay

- **Attempt 0** (first try): No delay
- **Attempt 1** (1st retry): 2 seconds delay
- **Attempt 2** (2nd retry): 4 seconds delay

This gives the network/ngrok time to recover.

## Tips for Users

### 🔧 If You Keep Getting Connection Errors:

1. **Check ngrok status**

   ```bash
   # In terminal where ngrok is running
   # Look for "session expired" or "tunnel closed"
   ```

2. **Restart ngrok**

   ```bash
   ngrok http 8000
   # Update .env with new URL
   ```

3. **Check server is running**

   ```bash
   # Make sure your API server is still up
   curl http://localhost:8000/healthz
   ```

4. **Check internet connection**

   - Mobile data might be unstable
   - Try switching to WiFi or vice versa

5. **Reduce load**
   - Test one format at a time instead of all
   - Use smaller images
   - Close other apps using network

### 📱 Best Practices

- ✅ Run tests when you have stable internet
- ✅ Keep ngrok running throughout all tests
- ✅ Monitor logs for retry patterns
- ✅ If many retries happen, pause and check network
- ❌ Don't run tests during video calls/streaming
- ❌ Don't switch networks mid-test

## Example Scenarios

### Scenario 1: Success After 1 Retry

```
Testing POST /predict?fmt=compact...
⚠️ Connection error, will retry: HttpException: Connection closed...
↻ Retry attempt 1/2...
[ApiClient] Uploading file: image.jpg
✓ POST /predict?fmt=compact passed (12150.0ms)
```

**Result**: Test PASS ✅

### Scenario 2: Fail After All Retries

```
Testing POST /predict?fmt=json...
⚠️ Connection error, will retry: HttpException: Connection closed...
↻ Retry attempt 1/2...
⚠️ Connection error, will retry: SocketException: Connection reset...
↻ Retry attempt 2/2...
✗ POST /predict?fmt=json failed after 2 attempts (HTTP 0): ...
```

**Result**: Test FAIL ❌ with retry info

### Scenario 3: Success First Try

```
Testing POST /predict?fmt=png...
[ApiClient] Uploading file: image.jpg
✓ POST /predict?fmt=png passed (11905.0ms)
```

**Result**: No retry needed, test PASS ✅

## Future Improvements

Potential enhancements:

- [ ] Configurable max retries
- [ ] Exponential backoff with jitter
- [ ] Circuit breaker pattern
- [ ] Retry only on specific HTTP status codes
- [ ] Metrics for retry success rate

---

**This feature significantly improves test reliability when using ngrok tunnels!** 🎉
