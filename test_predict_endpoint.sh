#!/bin/bash

# 🔍 Quick Predict Endpoint Diagnostic Script
# Run this to test your server and identify the 500 error cause

echo "🔍 Testing MA Segmentation API Predict Endpoint"
echo "================================================"
echo ""

# Get API URL from .env or ask user
if [ -f .env ]; then
    source .env
    API_URL="$API_BASE"
else
    read -p "Enter your API base URL (e.g., https://abc123.ngrok-free.dev): " API_URL
fi

# Remove trailing slash
API_URL="${API_URL%/}"

echo "Testing API: $API_URL"
echo ""

# Step 1: Check server health
echo "1️⃣ Checking server health..."
HEALTH_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" "$API_URL/healthz")
HTTP_CODE=$(echo "$HEALTH_RESPONSE" | grep "HTTP_CODE" | cut -d: -f2)
HEALTH_BODY=$(echo "$HEALTH_RESPONSE" | grep -v "HTTP_CODE")

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Health check passed (200)"
    echo "Response: $HEALTH_BODY"
    
    # Check if model is loaded
    if echo "$HEALTH_BODY" | grep -q '"model_loaded": true'; then
        echo "✅ Model is loaded"
    elif echo "$HEALTH_BODY" | grep -q '"model_loaded": false'; then
        echo "❌ Model NOT loaded - this will cause 500 errors!"
        echo "   Fix: Re-run the model loading cell in your notebook"
        exit 1
    fi
else
    echo "❌ Health check failed (HTTP $HTTP_CODE)"
    echo "   Server may not be running"
    exit 1
fi

echo ""

# Step 2: Check if test image exists
echo "2️⃣ Checking for test image..."
if [ ! -f "test_image.jpg" ] && [ ! -f "test_image.png" ]; then
    echo "⚠️  No test image found in current directory"
    echo "   Please provide a test image as 'test_image.jpg' or 'test_image.png'"
    echo ""
    read -p "Enter path to a test image: " TEST_IMAGE
    if [ ! -f "$TEST_IMAGE" ]; then
        echo "❌ Image not found: $TEST_IMAGE"
        exit 1
    fi
else
    if [ -f "test_image.jpg" ]; then
        TEST_IMAGE="test_image.jpg"
    else
        TEST_IMAGE="test_image.png"
    fi
    echo "✅ Using test image: $TEST_IMAGE"
fi

# Check image size
IMAGE_SIZE=$(du -h "$TEST_IMAGE" | cut -f1)
echo "   Image size: $IMAGE_SIZE"

echo ""

# Step 3: Test predict with PNG format (simplest)
echo "3️⃣ Testing predict endpoint (fmt=png, simplest format)..."
PREDICT_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
    -X POST "$API_URL/predict?fmt=png&threshold=0.5" \
    -F "file=@$TEST_IMAGE" \
    -o /tmp/test_mask.png 2>&1)

HTTP_CODE=$(echo "$PREDICT_RESPONSE" | grep "HTTP_CODE" | cut -d: -f2)

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Predict (PNG) passed (200)"
    echo "   Mask saved to: /tmp/test_mask.png"
    PNG_SIZE=$(du -h /tmp/test_mask.png | cut -f1)
    echo "   Mask size: $PNG_SIZE"
elif [ "$HTTP_CODE" = "500" ]; then
    echo "❌ Predict failed with 500 Internal Server Error"
    echo ""
    echo "🔍 This is a SERVER-SIDE error. Common causes:"
    echo "   1. Model not loaded properly"
    echo "   2. Image format not supported"
    echo "   3. Server code error during inference"
    echo "   4. Memory/GPU error"
    echo ""
    echo "   Check your notebook server logs for the exact error"
    exit 1
else
    echo "❌ Predict failed (HTTP $HTTP_CODE)"
    echo "$PREDICT_RESPONSE"
    exit 1
fi

echo ""

# Step 4: Test predict with JSON format (full response)
echo "4️⃣ Testing predict endpoint (fmt=json, full response)..."
JSON_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
    -X POST "$API_URL/predict?fmt=json&threshold=0.5&return_overlay=false&proba=false" \
    -F "file=@$TEST_IMAGE")

HTTP_CODE=$(echo "$JSON_RESPONSE" | grep "HTTP_CODE" | cut -d: -f2)
JSON_BODY=$(echo "$JSON_RESPONSE" | grep -v "HTTP_CODE")

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Predict (JSON) passed (200)"
    
    # Extract key metrics
    if command -v jq &> /dev/null; then
        echo ""
        echo "📊 Response summary:"
        echo "$JSON_BODY" | jq '{
            timing_ms,
            statistics: .statistics,
            has_mask: (.segmentation_mask != null),
            has_overlay: (.overlay_image != null)
        }'
    else
        echo "   (Install 'jq' to see formatted JSON response)"
        echo "   Response: ${JSON_BODY:0:200}..."
    fi
elif [ "$HTTP_CODE" = "500" ]; then
    echo "❌ Predict (JSON) failed with 500"
    echo "   But PNG format worked! This means:"
    echo "   - Model inference is working"
    echo "   - Problem is in JSON formatting/serialization"
    echo ""
    echo "   Try to extract error detail:"
    if command -v jq &> /dev/null; then
        echo "$JSON_BODY" | jq '.detail' 2>/dev/null || echo "$JSON_BODY"
    else
        echo "$JSON_BODY"
    fi
    exit 1
else
    echo "❌ Predict (JSON) failed (HTTP $HTTP_CODE)"
    echo "$JSON_BODY"
    exit 1
fi

echo ""
echo "================================================"
echo "✅ All tests passed!"
echo "   Your predict endpoint is working correctly"
echo ""
echo "If you're still getting 500 errors in Flutter:"
echo "1. Check the specific image being sent"
echo "2. Verify parameters match (fmt, threshold, etc.)"
echo "3. Check Flutter app logs for request details"
echo "4. Compare with curl request that works"
