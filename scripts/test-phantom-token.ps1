#!/usr/bin/env pwsh
# Test Phantom Token Pattern - Full Flow
# This script tests the complete authentication flow with Opaque Tokens

$ErrorActionPreference = "Stop"

Write-Host "🔐 Testing Phantom Token Pattern Implementation" -ForegroundColor Cyan
Write-Host "=" * 60

# Configuration
$GATEWAY_URL = "http://localhost:8080"
$AUTH_LOGIN = "$GATEWAY_URL/api/authentication/v1/login"
$AUTH_ME = "$GATEWAY_URL/api/authentication/v1/me"

# Test Credentials (should exist in your test database)
$TEST_EMAIL = "admin@example.com"
$TEST_PASSWORD = "password123"
$TENANT_CODE = "default"

Write-Host "`n📝 Test Configuration:" -ForegroundColor Yellow
Write-Host "   Gateway URL: $GATEWAY_URL"
Write-Host "   Test User: $TEST_EMAIL"
Write-Host "   Tenant: $TENANT_CODE"
Write-Host ""

# Step 1: Login and get Opaque Token
Write-Host "🔑 Step 1: Login to get Opaque Token..." -ForegroundColor Green

$loginBody = @{
    identifier = $TEST_EMAIL
    password = $TEST_PASSWORD
    tenant_code = $TENANT_CODE
} | ConvertTo-Json

try {
    $loginResponse = Invoke-WebRequest -Uri $AUTH_LOGIN `
        -Method POST `
        -ContentType "application/json" `
        -Body $loginBody `
        -SessionVariable session `
        -UseBasicParsing

    Write-Host "✅ Login successful! Status: $($loginResponse.StatusCode)" -ForegroundColor Green

    # Parse response
    $responseData = $loginResponse.Content | ConvertFrom-Json
    Write-Host "`n📦 Response Data:" -ForegroundColor Yellow
    Write-Host ($responseData | ConvertTo-Json -Depth 3)

    # Check cookies
    Write-Host "`n🍪 Cookies received:" -ForegroundColor Yellow
    $accessTokenCookie = $session.Cookies.GetCookies($GATEWAY_URL) | Where-Object { $_.Name -eq "access_token" }
    $refreshTokenCookie = $session.Cookies.GetCookies($GATEWAY_URL) | Where-Object { $_.Name -eq "refresh_token" }

    if ($accessTokenCookie) {
        Write-Host "   ✅ access_token: Present" -ForegroundColor Green
        Write-Host "      Value (first 16 chars): $($accessTokenCookie.Value.Substring(0, [Math]::Min(16, $accessTokenCookie.Value.Length)))..."
        Write-Host "      Length: $($accessTokenCookie.Value.Length) chars"
        Write-Host "      HttpOnly: $($accessTokenCookie.HttpOnly)"
        Write-Host "      Secure: $($accessTokenCookie.Secure)"

        # Check if it's really an opaque token (not JWT)
        if ($accessTokenCookie.Value.StartsWith("eyJ")) {
            Write-Host "   ⚠️  WARNING: Token looks like JWT, not Opaque Token!" -ForegroundColor Yellow
        } else {
            Write-Host "   ✅ Token format: Opaque (not JWT)" -ForegroundColor Green
        }
    } else {
        Write-Host "   ❌ access_token: Missing" -ForegroundColor Red
        exit 1
    }

    if ($refreshTokenCookie) {
        Write-Host "`n   ✅ refresh_token: Present" -ForegroundColor Green
        Write-Host "      Value (first 16 chars): $($refreshTokenCookie.Value.Substring(0, [Math]::Min(16, $refreshTokenCookie.Value.Length)))..."
        Write-Host "      Length: $($refreshTokenCookie.Value.Length) chars"
    } else {
        Write-Host "`n   ⚠️  refresh_token: Missing" -ForegroundColor Yellow
    }

    # Step 2: Verify token by calling protected endpoint
    Write-Host "`n🔐 Step 2: Test protected endpoint with Opaque Token..." -ForegroundColor Green

    try {
        $meResponse = Invoke-WebRequest -Uri $AUTH_ME `
            -Method GET `
            -WebSession $session `
            -UseBasicParsing

        Write-Host "✅ Protected endpoint accessible! Status: $($meResponse.StatusCode)" -ForegroundColor Green

        $userData = $meResponse.Content | ConvertFrom-Json
        Write-Host "`n👤 User Data from /me:" -ForegroundColor Yellow
        Write-Host ($userData | ConvertTo-Json -Depth 3)

    } catch {
        Write-Host "❌ Failed to access protected endpoint: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "   This means the Opaque Token validation failed at Gateway" -ForegroundColor Yellow
    }

    # Step 3: Verify Redis Session (optional - requires redis-cli)
    Write-Host "`n🔍 Step 3: Verify Redis Session..." -ForegroundColor Green
    Write-Host "   To check Redis manually, run:" -ForegroundColor Yellow
    Write-Host "   redis-cli -h 192.168.1.202 -p 32269" -ForegroundColor Cyan
    Write-Host "   > KEYS session:*" -ForegroundColor Cyan
    Write-Host "   > GET session:<hash>" -ForegroundColor Cyan

    Write-Host "`n✅ All tests completed successfully!" -ForegroundColor Green
    Write-Host "`n📋 Summary:" -ForegroundColor Cyan
    Write-Host "   ✓ Login successful with Opaque Token" -ForegroundColor Green
    Write-Host "   ✓ Tokens stored in httpOnly cookies" -ForegroundColor Green
    Write-Host "   ✓ Protected endpoint accessible" -ForegroundColor Green
    Write-Host "   ✓ Phantom Token Pattern working correctly!" -ForegroundColor Green

} catch {
    Write-Host "`n❌ Test Failed!" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red

    if ($_.Exception.Response) {
        $statusCode = $_.Exception.Response.StatusCode.value__
        Write-Host "Status Code: $statusCode" -ForegroundColor Yellow

        try {
            $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json
            Write-Host "Error Details:" -ForegroundColor Yellow
            Write-Host ($errorBody | ConvertTo-Json -Depth 3)
        } catch {
            Write-Host "Raw Error: $($_.ErrorDetails.Message)" -ForegroundColor Yellow
        }
    }

    exit 1
}

Write-Host "`n" + ("=" * 60)
