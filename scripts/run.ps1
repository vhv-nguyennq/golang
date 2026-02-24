# ==============================================================================
# PowerShell Script - Environment-aware Runner for Go Services
# Framework Version: 2.0
# Usage: .\run.ps1 -Env local|dev|staging|production
# ==============================================================================

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("local", "dev", "staging", "production")]
    [string]$Env = "local",
    
    [Parameter(Mandatory=$false)]
    [string]$Command = "run",
    
    [Parameter(Mandatory=$false)]
    [switch]$Debug = $false
)

# Color output functions
function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "→ $Message" -ForegroundColor Cyan
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠ $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════" -ForegroundColor Blue
    Write-Host "  $Message" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════" -ForegroundColor Blue
    Write-Host ""
}

# Check if .env file exists
function Test-EnvFile {
    param([string]$Environment)
    
    $envFile = ".env.$Environment"
    
    if (-not (Test-Path $envFile)) {
        Write-Error "Environment file not found: $envFile"
        Write-Info "Available environment files:"
        Get-ChildItem -Filter ".env.*" | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Yellow }
        exit 1
    }
    
    Write-Success "Environment file found: $envFile"
    return $envFile
}

# Load environment variables from file
function Import-EnvFile {
    param([string]$FilePath)
    
    if ($Debug) {
        Write-Info "Loading environment variables from: $FilePath"
    }
    
    Get-Content $FilePath | ForEach-Object {
        $line = $_.Trim()
        
        # Skip comments and empty lines
        if ($line -match '^#' -or $line -eq '') {
            return
        }
        
        # Parse KEY=VALUE
        if ($line -match '^([^=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            
            # Remove quotes if present
            $value = $value -replace '^["'']|["'']$', ''
            
            # Set environment variable
            [Environment]::SetEnvironmentVariable($key, $value, "Process")
            
            if ($Debug) {
                Write-Host "  $key = $value" -ForegroundColor DarkGray
            }
        }
    }
}

# Main execution
try {
    Write-Header "Go Service Runner (Environment: $Env)"
    
    # Check environment file
    $envFile = Test-EnvFile -Environment $Env
    
    # Load environment variables
    Import-EnvFile -FilePath $envFile
    
    # Set APP_ENV for the Go envloader
    $env:APP_ENV = $Env
    
    Write-Info "Setting APP_ENV=$Env"
    
    # Execute command based on parameter
    switch ($Command.ToLower()) {
        "run" {
            Write-Info "Starting Go service..."
            go run ./cmd/server/main.go
        }
        "build" {
            Write-Info "Building Go service..."
            $outputDir = "bin"
            if (-not (Test-Path $outputDir)) {
                New-Item -ItemType Directory -Path $outputDir | Out-Null
            }
            $binaryName = Split-Path -Leaf (Get-Location)
            go build -o "$outputDir/$binaryName.exe" ./cmd/server/main.go
            Write-Success "Build complete: $outputDir/$binaryName.exe"
        }
        "test" {
            Write-Info "Running tests..."
            go test -v -race ./...
        }
        "gen" {
            Write-Info "Generating code..."
            go generate ./...
            Write-Success "Code generation complete"
        }
        default {
            Write-Error "Unknown command: $Command"
            exit 1
        }
    }
    
} catch {
    Write-Error "Error: $($_.Exception.Message)"
    exit 1
}
