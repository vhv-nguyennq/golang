# Integration test: Gateway-core + Authentication service
# Run from repo root. Ensure gateway-core (8080) and authentication (50051 gRPC) are running.

$gatewayHealth = "http://localhost:8080/health"
$gatewayLogin  = "http://localhost:8080/api/authentication/v1/auth/login"
$loginBody     = '{"identifier":"test@example.com","password":"testpass","tenantId":"00000000-0000-0000-0000-000000000001"}'

Write-Host "1. GET $gatewayHealth"
try {
    $r = Invoke-WebRequest -Uri $gatewayHealth -UseBasicParsing
    Write-Host "   Status: $($r.StatusCode) | Content: $($r.Content)"
} catch {
    Write-Host "   Error: $($_.Exception.Message)"
}

Write-Host "`n2. POST $gatewayLogin"
try {
    $r = Invoke-WebRequest -Uri $gatewayLogin -Method POST -ContentType "application/json" -Body $loginBody -UseBasicParsing
    Write-Host "   Status: $($r.StatusCode) | Content: $($r.Content)"
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    $body = $_.ErrorDetails.Message
    Write-Host "   Status: $code | Body: $body"
}
