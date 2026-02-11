#!/bin/bash

# ReelMaker-AI Backend Verification Script
# Tests the newly implemented endpoints for outputs and re-rendering

BASE_URL="http://localhost:4000"
echo "==================================="
echo "ReelMaker-AI Backend Tests"
echo "==================================="
echo ""

# 1. Test Health Check
echo "1. Testing Health Check..."
curl -s "$BASE_URL/health" | jq '.' 2>/dev/null || curl -s "$BASE_URL/health"
echo ""
echo ""

# 2. Test Root Endpoint (check new outputs endpoint listed)
echo "2. Testing Root Endpoint..."
curl -s "$BASE_URL/" | jq '.endpoints' 2>/dev/null || curl -s "$BASE_URL/"
echo ""
echo ""

# 3. Check Database Schema
echo "3. Checking Database Schema..."
echo "-- Checking for output_videos table --"
sqlite3 reelmaker.db ".schema output_videos" 2>/dev/null || echo "Database not found or table doesn't exist"
echo ""

echo "-- Checking projects table for new columns --"
sqlite3 reelmaker.db "PRAGMA table_info(projects);" 2>/dev/null | grep -E "settings_json|version" || echo "Columns not found"
echo ""
echo ""

# Instructions for authenticated endpoints
echo "==================================="
echo "To test authenticated endpoints:"
echo "==================================="
echo ""
echo "# 1. Login/Register to get token"
echo "curl -X POST $BASE_URL/api/auth/login \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"email\":\"test@test.com\",\"password\":\"password\"}'"
echo ""
echo "# 2. Set token"
echo "TOKEN=\"your_token_here\" "
echo ""
echo "# 3. Test get project outputs"
echo "curl -H \"Authorization: Bearer \$TOKEN\" \\"
echo "  $BASE_URL/api/projects/PROJECT_ID/outputs"
echo ""
echo "# 4. Test re-render"
echo "curl -X POST -H \"Authorization: Bearer \$TOKEN\" \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"settings\":{\"segment_seconds\":45}}' \\"
echo "  $BASE_URL/api/projects/PROJECT_ID/re-render"
echo ""
echo "# 5. Test register output"
echo "curl -X POST -H \"Authorization: Bearer \$TOKEN\" \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"projectId\":\"...\",\"jobId\":\"...\",\"chunkIndex\":0,\"filename\":\"test_001.mp4\"}' \\"
echo "  $BASE_URL/api/outputs"
echo ""

echo "==================================="
echo "Tests Complete"
echo "==================================="
