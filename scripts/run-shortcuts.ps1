# ==============================================================================
# Quick Start Scripts - Copy to Service Root
# ==============================================================================

# run-local.ps1
$env:APP_ENV="local"
go run ./cmd/server/main.go

# run-dev.ps1
$env:APP_ENV="dev"
go run ./cmd/server/main.go

# run-staging.ps1
$env:APP_ENV="staging"
go run ./cmd/server/main.go

# run-prod.ps1
$env:APP_ENV="production"
go run ./cmd/server/main.go
