# Restore Windows localhost:8080 -> current WSL Sub2API
$ErrorActionPreference = 'Stop'
$wslIp = ((wsl.exe -d Ubuntu -- hostname -I).ToString().Trim() -split '\s+')[0]
if (-not $wslIp) { throw 'WSL IP not found' }
netsh interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=8080 2>$null | Out-Null
netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=8080 2>$null | Out-Null
netsh interface portproxy add v4tov4 listenaddress=127.0.0.1 listenport=8080 connectaddress=$wslIp connectport=8080
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=8080 connectaddress=$wslIp connectport=8080
try { Restart-Service iphlpsvc -Force -ErrorAction SilentlyContinue } catch {}
Start-Sleep -Seconds 1
Write-Host "WSL_IP=$wslIp"
netsh interface portproxy show all
try {
  $r = Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8080/health -TimeoutSec 5
  Write-Host "HEALTH=$($r.StatusCode) $($r.Content)"
} catch {
  Write-Host "HEALTH_FAIL=$($_.Exception.Message)"
  Write-Host "Direct WSL IP test..."
  try {
    $r2 = Invoke-WebRequest -UseBasicParsing "http://${wslIp}:8080/health" -TimeoutSec 5
    Write-Host "WSL_DIRECT_OK=$($r2.Content)"
  } catch {
    Write-Host "WSL_DIRECT_FAIL=$($_.Exception.Message)"
  }
}
