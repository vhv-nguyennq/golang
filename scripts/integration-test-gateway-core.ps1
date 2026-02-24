# Integration test: Gateway-core + Core service APIs
# Run from repo root. Ensure gateway-core (8080) and core gRPC (50054) are running.

$base = "http://localhost:8080"

$tests = @(
    @{
        Name = "Gateway health"
        Method = "GET"
        Url   = "$base/health"
        Body  = $null
    },
    @{
        Name = "Core: List user-registrations"
        Method = "GET"
        Url   = "$base/api/core/v1/user-registrations"
        Body  = $null
    },
    @{
        Name = "Core: List user-registration-logs"
        Method = "GET"
        Url   = "$base/api/core/v1/user-registration-logs"
        Body  = $null
    },
    @{
        Name = "Core: List user-mfa-methods"
        Method = "GET"
        Url   = "$base/api/core/v1/user-mfa-methods"
        Body  = $null
    }
)

foreach ($t in $tests) {
    Write-Host "`n--- $($t.Name) ---"
    Write-Host "$($t.Method) $($t.Url)"
    try {
        $params = @{
            Uri             = $t.Url
            Method          = $t.Method
            UseBasicParsing = $true
        }
        if ($t.Body) {
            $params["ContentType"] = "application/json"
            $params["Body"] = $t.Body
        }
        $r = Invoke-WebRequest @params
        Write-Host "   Status: $($r.StatusCode)"
        if ($r.Content.Length -lt 500) { Write-Host "   Body: $($r.Content)" } else { Write-Host "   Body: (truncated) $($r.Content.Substring(0,200))..." }
    } catch {
        $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { "N/A" }
        $body = $_.ErrorDetails.Message
        Write-Host "   Status: $code | Body: $body"
    }
}

Write-Host "`nDone. 200/404/401 from core endpoints = gateway proxy OK."
