#!/usr/bin/env pwsh
# Quick Start Script for Testing Phantom Token Pattern
# Starts all required services in separate terminals

$ErrorActionPreference = "Stop"

Write-Host "🚀 Starting Services for Phantom Token Testing..." -ForegroundColor Cyan
Write-Host "=" * 60

$WORKSPACE_ROOT = "E:\vsystem-saas"

# Check if services are already running
function Test-ServiceRunning {
    param([int]$Port)
    try {
        $connection = Test-NetConnection -ComputerName localhost -Port $Port -WarningAction SilentlyContinue
        return $connection.TcpTestSucceeded
    } catch {
        return $false
    }
}

# Function to start service in new PowerShell terminal
function Start-ServiceInNewTerminal {
    param(
        [string]$Name,
        [string]$Path,
        [string]$Command,
        [int]$Port
    )

    if (Test-ServiceRunning -Port $Port) {
        Write-Host "✓ $Name already running on port $Port" -ForegroundColor Yellow
        return
    }

    Write-Host "▶ Starting $Name on port $Port..." -ForegroundColor Green

    $scriptBlock = @"
`$Host.UI.RawUI.WindowTitle = "$Name"
Set-Location "$Path"
`$env:APP_ENV = "local"
Write-Host "🚀 Starting $Name..." -ForegroundColor Cyan
$Command
"@

    Start-Process pwsh -ArgumentList "-NoExit", "-Command", $scriptBlock
    Start-Sleep -Seconds 2
}

# 1. Start Auth Service
Write-Host "`n1️⃣ Auth Service (Port 8081)..." -ForegroundColor Cyan
Start-ServiceInNewTerminal `
    -Name "Auth Service" `
    -Path "$WORKSPACE_ROOT\go\apps\auth" `
    -Command "go run cmd/main.go" `
    -Port 8081

# 2. Start Gateway
Write-Host "`n2️⃣ API Gateway (Port 8080)..." -ForegroundColor Cyan
Start-ServiceInNewTerminal `
    -Name "API Gateway" `
    -Path "$WORKSPACE_ROOT\go\apps\gateway" `
    -Command "go run cmd/main.go" `
    -Port 8080

# 3. Start Shell-App (React)
Write-Host "`n3️⃣ Shell-App React (Port 5173)..." -ForegroundColor Cyan
Start-ServiceInNewTerminal `
    -Name "Shell-App (React)" `
    -Path "$WORKSPACE_ROOT\reactjs\apps\shell-app" `
    -Command "pnpm dev" `
    -Port 5173

# Wait for services to be ready
Write-Host "`n⏳ Waiting for services to start..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# Health check
Write-Host "`n🏥 Health Check:" -ForegroundColor Cyan

$services = @(
    @{Name="Auth Service"; Url="http://localhost:8081/health"},
    @{Name="API Gateway"; Url="http://localhost:8080/health"},
    @{Name="Shell-App"; Url="http://localhost:5173"}
)

foreach ($service in $services) {
    try {
        $response = Invoke-WebRequest -Uri $service.Url -TimeoutSec 3 -UseBasicParsing -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200) {
            Write-Host "   ✅ $($service.Name) - OK" -ForegroundColor Green
        } else {
            Write-Host "   ⚠️  $($service.Name) - Status: $($response.StatusCode)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "   ❌ $($service.Name) - Not ready yet" -ForegroundColor Red
    }
}

Write-Host "`n✅ All services started!" -ForegroundColor Green
Write-Host "`n📋 Next Steps:" -ForegroundColor Cyan
Write-Host "   1. Open browser: http://localhost:5173/login" -ForegroundColor White
Write-Host "   2. Login with:" -ForegroundColor White
Write-Host "      - Email: admin@example.com" -ForegroundColor Yellow
Write-Host "      - Password: password123" -ForegroundColor Yellow
Write-Host "   3. Open DevTools (F12) → Application → Cookies" -ForegroundColor White
Write-Host "   4. Verify 'access_token' cookie is present (64 chars)" -ForegroundColor White
Write-Host "`n   OR run automated test:" -ForegroundColor Cyan
Write-Host "   .\scripts\test-phantom-token.ps1" -ForegroundColor Yellow

Write-Host "`n" + ("=" * 60)
Write-Host "Press Ctrl+C to stop watching. Services will continue in their terminals." -ForegroundColor Gray
