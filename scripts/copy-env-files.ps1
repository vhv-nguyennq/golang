# ==============================================================================
# Copy .env.example to .env.local (Windows Compatible)
# ==============================================================================

Write-Host "Copying .env.example files to .env.local..." -ForegroundColor Cyan

# Find all .env.example files and copy them to .env.local if not exists
Get-ChildItem -Path . -Filter ".env.example" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    $envExample = $_.FullName
    $envLocal = Join-Path $_.Directory.FullName ".env.local"

    if (-not (Test-Path $envLocal)) {
        Copy-Item -Path $envExample -Destination $envLocal
        Write-Host "Created: $envLocal" -ForegroundColor Green
    } else {
        Write-Host "Skipped (exists): $envLocal" -ForegroundColor Yellow
    }
}

Write-Host "Environment files setup completed." -ForegroundColor Green
