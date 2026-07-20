# grok-regkit 本地服务管理器 v4
# 更新记录（2026-07-18）：
# 1. 基于 v3，修复“Sub2API 容器 healthy，但 Windows 访问 127.0.0.1:8080 失败”的问题。
# 2. 启动/重启/状态检查时自动重建 netsh portproxy：127.0.0.1:8080 与 0.0.0.0:8080 -> 当前 WSL IP:8080。
# 3. 不停止/不删除 Sub2API 容器与数据；仅修复本机转发，避免用户误以为服务挂掉。
# 4. 状态输出增加 sub2api.wsl_ip / portproxy_target，便于确认转发是否指向当前 WSL。
#
# v3 更新记录（2026-07-17）：
# 1. 修复 Start-Process 返回启动器/父进程 PID，而实际监听端口属于子进程，导致 PID 文件与监听 PID 不一致的问题。
# 2. 服务健康检查通过后，把 8092/8010/8317/8318 的 PID 文件同步为真实监听 PID。
# 3. 停止服务时从监听 PID 向上追溯同一服务的匹配父进程并停止整棵进程树，防止 uvicorn/granian 守护父进程重新拉起 worker。
# 4. PID 文件失效时按端口回退，但只有命令行符合服务特征才停止；端口被无关进程占用时拒绝接管，避免误停。
# 5. WSL/Sub2API 仍只通过 compose 和已跟踪 keepalive 管理；Windows 8080 的 wslrelay 不按端口强制结束。
#
# v2 更新记录（2026-07-17）：
# 1. 保留 v1 的 8092/8010/8317/8318 管理能力，新增 Sub2API(8080) 管理与健康检查。
# 2. 修复 WSL 最后一个 Windows 会话退出后 Ubuntu 自动停止，导致 Docker/Sub2API 离线的问题：
#    启动隐藏的 WSL keepalive 进程并记录 PID，随后执行 docker compose up -d。
# 3. Stop/Restart 仅停止 Sub2API compose 服务和本管理器创建的 keepalive，不删除容器、数据库、日志或卷。
# 4. 状态输出增加 WSL keepalive PID、Ubuntu 运行状态及 Sub2API 健康状态，不输出任何密钥。
#
# v1 更新记录（2026-07-16）：
# 1. 统一管理 grok-regkit Web(8092)、兼容号池 grok2api(8010)、CLIProxyAPI(8317)、CPA Gateway(8318)。
# 2. 全部服务仅监听 127.0.0.1；启动、停止、状态检测均不输出密钥。
# 3. 使用 PID 文件、命令行校验和递归子进程停止，避免误停其他进程。
# 4. 提供用户登录自启动和桌面快捷方式安装。

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Start','Stop','Restart','Status','InstallAutoStart','RemoveAutoStart','InstallShortcuts')]
    [string]$Action = 'Status'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir = Join-Path $Root 'logs'
$RunDir = Join-Path $Root 'runtime'
$SecretsPath = Join-Path $RunDir 'runtime_secrets.json'
$RegkitRoot = 'C:\Users\zhang\grok-regkit'
$Grok2ApiRoot = Join-Path $Root 'grok2api1'
$CliProxyRoot = Join-Path $Root 'cliproxyapi1'
$GatewayRoot = Join-Path $Root 'cpa_gateway1'
$WslExe = Join-Path $env:SystemRoot 'System32\wsl.exe'
$WslDistro = 'Ubuntu'
$Sub2ApiDeploy = '/home/baoge/sub2api-deploy'
New-Item -ItemType Directory -Path $LogDir,$RunDir -Force | Out-Null

function Get-SecretsObject {
    if (-not (Test-Path -LiteralPath $SecretsPath)) { throw "Missing runtime secrets: $SecretsPath" }
    return Get-Content -LiteralPath $SecretsPath -Raw | ConvertFrom-Json
}

function Get-PortOwner([int]$Port) {
    $c = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return [int]$c.OwningProcess }
    return 0
}

function Get-ProcessInfo([int]$Id) {
    if ($Id -le 0) { return $null }
    return Get-CimInstance Win32_Process -Filter "ProcessId=$Id" -ErrorAction SilentlyContinue
}

function Test-ProcessPattern([int]$Id, [string]$ExpectedPattern) {
    $proc = Get-ProcessInfo -Id $Id
    if (-not $proc) { return $false }
    return ([string]$proc.CommandLine -match $ExpectedPattern)
}

function Get-ValidatedPortOwner([int]$Port, [string]$ExpectedPattern) {
    $id = Get-PortOwner -Port $Port
    if ($id -eq 0) { return 0 }
    $proc = Get-ProcessInfo -Id $id
    if (-not $proc) { return 0 }
    if ([string]$proc.CommandLine -notmatch $ExpectedPattern) {
        throw "Port $Port is owned by unrelated PID $id ($($proc.Name)); expected command pattern: $ExpectedPattern"
    }
    return $id
}

function Sync-PidFileFromPort([string]$Name, [int]$Port, [string]$ExpectedPattern) {
    $id = Get-ValidatedPortOwner -Port $Port -ExpectedPattern $ExpectedPattern
    if ($id -le 0) { throw "Cannot synchronize $Name PID: no listener on port $Port" }
    Write-PidFile -Name $Name -PidValue $id
    return $id
}

function Get-PidFileValue([string]$Name) {
    $pidPath = Join-Path $RunDir "$Name.pid"
    if (-not (Test-Path -LiteralPath $pidPath)) { return 0 }
    $id = 0
    [void][int]::TryParse((Get-Content -LiteralPath $pidPath -Raw).Trim(), [ref]$id)
    return $id
}

function Get-ServiceRootPid([int]$Id, [string]$ExpectedPattern) {
    if (-not (Test-ProcessPattern -Id $Id -ExpectedPattern $ExpectedPattern)) { return 0 }
    $rootId = $Id
    $seen = @{}
    while ($rootId -gt 0 -and -not $seen.ContainsKey($rootId)) {
        $seen[$rootId] = $true
        $proc = Get-ProcessInfo -Id $rootId
        if (-not $proc) { break }
        $parentId = [int]$proc.ParentProcessId
        if ($parentId -le 0 -or -not (Test-ProcessPattern -Id $parentId -ExpectedPattern $ExpectedPattern)) { break }
        $rootId = $parentId
    }
    return $rootId
}

function Wait-PortClosed([int]$Port, [int]$Seconds = 15) {
    $until = (Get-Date).AddSeconds($Seconds)
    do {
        if ((Get-PortOwner -Port $Port) -eq 0) { return $true }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $until)
    return $false
}

function Test-Http([string]$Uri, [hashtable]$Headers = @{}) {
    try {
        $r = Invoke-WebRequest -Uri $Uri -Headers $Headers -UseBasicParsing -TimeoutSec 4
        return [bool]($r.StatusCode -ge 200 -and $r.StatusCode -lt 500)
    } catch {
        return $false
    }
}

function Wait-Http([string]$Name, [string]$Uri, [hashtable]$Headers = @{}, [int]$Seconds = 60) {
    $until = (Get-Date).AddSeconds($Seconds)
    do {
        if (Test-Http -Uri $Uri -Headers $Headers) { return $true }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $until)
    Write-Warning "$Name health check timed out: $Uri"
    return $false
}

function Write-PidFile([string]$Name, [int]$PidValue) {
    Set-Content -LiteralPath (Join-Path $RunDir "$Name.pid") -Value $PidValue -Encoding ascii
}

function Start-TrackedProcess {
    param(
        [string]$Name,
        [string]$FilePath,
        [string[]]$ArgumentList,
        [string]$WorkingDirectory,
        [hashtable]$Environment = @{}
    )
    $old = @{}
    foreach ($k in $Environment.Keys) {
        $old[$k] = [Environment]::GetEnvironmentVariable($k, 'Process')
        [Environment]::SetEnvironmentVariable($k, [string]$Environment[$k], 'Process')
    }
    try {
        $stdout = Join-Path $LogDir "$Name.out.log"
        $stderr = Join-Path $LogDir "$Name.err.log"
        $p = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
        Write-PidFile -Name $Name -PidValue $p.Id
        return $p.Id
    } finally {
        foreach ($k in $Environment.Keys) {
            [Environment]::SetEnvironmentVariable($k, $old[$k], 'Process')
        }
    }
}

function Get-TrackedPid([string]$Name, [string]$ExpectedPattern) {
    $pidPath = Join-Path $RunDir "$Name.pid"
    if (-not (Test-Path -LiteralPath $pidPath)) { return 0 }
    $id = 0
    [void][int]::TryParse((Get-Content -LiteralPath $pidPath -Raw).Trim(), [ref]$id)
    if ($id -le 0) { return 0 }
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue
    if (-not $proc) { return 0 }
    if ([string]$proc.CommandLine -notmatch $ExpectedPattern) { return 0 }
    return $id
}

function Start-Sub2Api {
    if (-not (Test-Path -LiteralPath $WslExe)) { throw "WSL executable missing: $WslExe" }
    $keepalivePid = Get-TrackedPid -Name 'sub2api-wsl' -ExpectedPattern 'sub2api-keepalive'
    if ($keepalivePid -eq 0) {
        $stdout = Join-Path $LogDir 'sub2api-wsl.out.log'
        $stderr = Join-Path $LogDir 'sub2api-wsl.err.log'
        $arguments = "-d $WslDistro -- bash -lc `"exec -a sub2api-keepalive sleep infinity`""
        $p = Start-Process -FilePath $WslExe -ArgumentList $arguments -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
        Write-PidFile -Name 'sub2api-wsl' -PidValue $p.Id
    }

    $composeOut = Join-Path $LogDir 'sub2api-compose.out.log'
    $composeErr = Join-Path $LogDir 'sub2api-compose.err.log'
    $composeArgs = "-d $WslDistro -- bash -lc `"cd '$Sub2ApiDeploy' && docker compose up -d`""
    $deadline = (Get-Date).AddSeconds(90)
    $composeExitCode = -1
    do {
        $composeProcess = Start-Process -FilePath $WslExe -ArgumentList $composeArgs -RedirectStandardOutput $composeOut -RedirectStandardError $composeErr -WindowStyle Hidden -Wait -PassThru
        $composeExitCode = $composeProcess.ExitCode
        if ($composeExitCode -eq 0) { break }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    if ($composeExitCode -ne 0) { throw "Sub2API docker compose failed with exit code $composeExitCode; see $composeOut and $composeErr" }
}


function Get-WslIp {
    if (-not (Test-Path -LiteralPath $WslExe)) { return '' }
    try {
        $raw = & $WslExe -d $WslDistro -- hostname -I 2>$null
        if (-not $raw) { return '' }
        $ip = (($raw | Out-String).Trim() -split '\s+')[0]
        if ($ip -match '^\d+\.\d+\.\d+\.\d+$') { return $ip }
        return ''
    } catch {
        return ''
    }
}

function Get-PortProxyTarget([string]$ListenAddress, [int]$ListenPort) {
    $lines = netsh interface portproxy show v4tov4 2>$null
    if (-not $lines) { return '' }
    foreach ($line in $lines) {
        if ($line -match ("^\s*" + [regex]::Escape($ListenAddress) + "\s+" + $ListenPort + "\s+(\d+\.\d+\.\d+\.\d+)\s+(\d+)\s*$")) {
            return "$($Matches[1]):$($Matches[2])"
        }
    }
    return ''
}

function Repair-Sub2ApiLocalPortProxy {
    param([switch]$Force)
    $wslIp = Get-WslIp
    if (-not $wslIp) {
        Write-Warning 'Sub2API portproxy repair skipped: WSL IP not found'
        return [ordered]@{ ok = $false; wsl_ip = ''; target = ''; repaired = $false; reason = 'wsl_ip_missing' }
    }

    $desired = "${wslIp}:8080"
    $curLocal = Get-PortProxyTarget -ListenAddress '127.0.0.1' -ListenPort 8080
    $curAny = Get-PortProxyTarget -ListenAddress '0.0.0.0' -ListenPort 8080
    $healthy = Test-Http 'http://127.0.0.1:8080/health'
    $needsRepair = $Force -or (-not $healthy) -or ($curLocal -ne $desired) -or ($curAny -ne $desired)
    if (-not $needsRepair) {
        return [ordered]@{ ok = $true; wsl_ip = $wslIp; target = $desired; repaired = $false; reason = 'already_ok' }
    }

    netsh interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=8080 2>$null | Out-Null
    netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=8080 2>$null | Out-Null
    netsh interface portproxy add v4tov4 listenaddress=127.0.0.1 listenport=8080 connectaddress=$wslIp connectport=8080 | Out-Null
    netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=8080 connectaddress=$wslIp connectport=8080 | Out-Null
    try { Restart-Service iphlpsvc -Force -ErrorAction SilentlyContinue } catch {}
    Start-Sleep -Seconds 1

    $healthyAfter = Test-Http 'http://127.0.0.1:8080/health'
    if (-not $healthyAfter) {
        $direct = Test-Http "http://${wslIp}:8080/health"
        Write-Warning "Sub2API localhost:8080 still unhealthy after portproxy repair; direct WSL health=$direct"
        return [ordered]@{ ok = $false; wsl_ip = $wslIp; target = $desired; repaired = $true; reason = 'health_fail_after_repair'; direct_wsl_ok = $direct }
    }
    return [ordered]@{ ok = $true; wsl_ip = $wslIp; target = $desired; repaired = $true; reason = 'repaired' }
}

function Stop-Sub2Api {
    if (Test-Path -LiteralPath $WslExe) {
        try {
            $stopOut = Join-Path $LogDir 'sub2api-compose-stop.out.log'
            $stopErr = Join-Path $LogDir 'sub2api-compose-stop.err.log'
            $stopArgs = "-d $WslDistro -- bash -lc `"cd '$Sub2ApiDeploy' && docker compose stop`""
            $stopProcess = Start-Process -FilePath $WslExe -ArgumentList $stopArgs -RedirectStandardOutput $stopOut -RedirectStandardError $stopErr -WindowStyle Hidden -Wait -PassThru
            if ($stopProcess.ExitCode -ne 0) { Write-Warning "Sub2API compose stop returned exit code $($stopProcess.ExitCode); see $stopOut and $stopErr" }
        } catch {
            Write-Warning "Sub2API compose stop failed: $($_.Exception.Message)"
        }
    }
    Stop-ByPidFile 'sub2api-wsl' 'sub2api-keepalive'
}

function Start-All {
    $secrets = Get-SecretsObject
    Start-Sub2Api
    $proxyRepair = Repair-Sub2ApiLocalPortProxy
    if (-not $proxyRepair.ok) {
        Write-Warning ("Sub2API local portproxy not healthy: {0}" -f ($proxyRepair | ConvertTo-Json -Compress))
    }

    if ((Get-ValidatedPortOwner -Port 8092 -ExpectedPattern 'uvicorn|web\.server:app') -eq 0) {
        $python = Join-Path $RegkitRoot '.venv\Scripts\python.exe'
        if (-not (Test-Path -LiteralPath $python)) { throw "grok-regkit Python missing: $python" }
        Start-TrackedProcess -Name 'grok-regkit-web' -FilePath $python -ArgumentList @('-B','-m','uvicorn','web.server:app','--host','127.0.0.1','--port','8092','--workers','1') -WorkingDirectory $RegkitRoot | Out-Null
    }

    if ((Get-ValidatedPortOwner -Port 8010 -ExpectedPattern 'granian|app\.main:app') -eq 0) {
        $granian = Join-Path $Grok2ApiRoot '.venv\Scripts\granian.exe'
        if (-not (Test-Path -LiteralPath $granian)) { throw "grok2api environment missing: $granian" }
        Start-TrackedProcess -Name 'grok2api' -FilePath $granian -ArgumentList @('--interface','asgi','--host','127.0.0.1','--port','8010','--workers','1','app.main:app') -WorkingDirectory $Grok2ApiRoot | Out-Null
    }

    $cpaHeaders = @{ Authorization = "Bearer $($secrets.cliproxy_api_key)" }
    if ((Get-ValidatedPortOwner -Port 8317 -ExpectedPattern 'cli-proxy-api\.exe') -eq 0) {
        $exe = Join-Path $CliProxyRoot 'cli-proxy-api.exe'
        if (-not (Test-Path -LiteralPath $exe)) { throw "CLIProxyAPI executable missing: $exe" }
        Start-TrackedProcess -Name 'cliproxyapi' -FilePath $exe -ArgumentList @('-config',(Join-Path $CliProxyRoot 'config1.yaml')) -WorkingDirectory $CliProxyRoot | Out-Null
    }

    if ((Get-ValidatedPortOwner -Port 8318 -ExpectedPattern 'cpa_gateway1\.py') -eq 0) {
        $python = 'C:\Python312\python.exe'
        $gateway = Join-Path $GatewayRoot 'cpa_gateway1.py'
        $gatewayEnv = @{
            'CPA_GATEWAY_ROOT' = $GatewayRoot
            'CPA_GATEWAY_KEYS' = (Join-Path $GatewayRoot 'keys.json')
            'CPA_GATEWAY_HOST' = '127.0.0.1'
            'CPA_GATEWAY_PORT' = '8318'
            'CPA_UPSTREAM' = 'http://127.0.0.1:8317'
            'CPA_PUBLIC_BASE' = 'http://127.0.0.1:8318/v1'
            'CPA_DEFAULT_QUOTA' = '0'
            'PYTHONDONTWRITEBYTECODE' = '1'
        }
        Start-TrackedProcess -Name 'cpa-gateway' -FilePath $python -ArgumentList @('-B',$gateway,'serve') -WorkingDirectory $GatewayRoot -Environment $gatewayEnv | Out-Null
    }

    $checks = @(
        (Wait-Http 'grok-regkit-web' 'http://127.0.0.1:8092/health' @{} 60),
        (Wait-Http 'grok2api' 'http://127.0.0.1:8010/health' @{} 90),
        (Wait-Http 'cliproxyapi' 'http://127.0.0.1:8317/v1/models' $cpaHeaders 60),
        (Wait-Http 'cpa-gateway' 'http://127.0.0.1:8318/health' @{} 30),
        (Wait-Http 'sub2api' 'http://127.0.0.1:8080/health' @{} 120)
    )
    if ($checks -contains $false) { throw 'One or more local services failed health checks.' }

    [void](Sync-PidFileFromPort -Name 'grok-regkit-web' -Port 8092 -ExpectedPattern 'uvicorn|web\.server:app')
    [void](Sync-PidFileFromPort -Name 'grok2api' -Port 8010 -ExpectedPattern 'granian|app\.main:app')
    [void](Sync-PidFileFromPort -Name 'cliproxyapi' -Port 8317 -ExpectedPattern 'cli-proxy-api\.exe')
    [void](Sync-PidFileFromPort -Name 'cpa-gateway' -Port 8318 -ExpectedPattern 'cpa_gateway1\.py')
}

function Stop-Tree([int]$Id, [string]$ExpectedPattern) {
    if ($Id -le 0) { return }
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$Id" -ErrorAction SilentlyContinue
    if (-not $proc) { return }
    $cmd = [string]$proc.CommandLine
    if ($cmd -notmatch $ExpectedPattern) {
        Write-Warning "Skip PID $Id because its command line does not match $ExpectedPattern"
        return
    }
    $children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$Id" -ErrorAction SilentlyContinue
    foreach ($child in $children) { Stop-Tree -Id ([int]$child.ProcessId) -ExpectedPattern '.*' }
    Stop-Process -Id $Id -Force -ErrorAction SilentlyContinue
}

function Stop-ByPidFile([string]$Name, [string]$ExpectedPattern, [int]$Port = 0) {
    $pidPath = Join-Path $RunDir "$Name.pid"
    $id = Get-PidFileValue -Name $Name
    if (-not (Test-ProcessPattern -Id $id -ExpectedPattern $ExpectedPattern)) {
        $id = 0
    }
    if ($id -eq 0 -and $Port -gt 0) {
        $portOwner = Get-PortOwner -Port $Port
        if ($portOwner -gt 0 -and (Test-ProcessPattern -Id $portOwner -ExpectedPattern $ExpectedPattern)) {
            $id = $portOwner
        } elseif ($portOwner -gt 0) {
            $proc = Get-ProcessInfo -Id $portOwner
            Write-Warning "Skip $Name fallback on port $Port because PID $portOwner ($($proc.Name)) does not match $ExpectedPattern"
        }
    }
    if ($id -gt 0) {
        $rootId = Get-ServiceRootPid -Id $id -ExpectedPattern $ExpectedPattern
        if ($rootId -gt 0) {
            Stop-Tree -Id $rootId -ExpectedPattern $ExpectedPattern
        }
        if ($Port -gt 0 -and -not (Wait-PortClosed -Port $Port -Seconds 15)) {
            Write-Warning "$Name port $Port is still listening after stop request; no unrelated process was terminated."
        }
    }
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
}

function Stop-All {
    Stop-Sub2Api
    Stop-ByPidFile 'cpa-gateway' 'cpa_gateway1\.py' 8318
    Stop-ByPidFile 'cliproxyapi' 'cli-proxy-api\.exe' 8317
    Stop-ByPidFile 'grok2api' 'granian|app\.main:app' 8010
    Stop-ByPidFile 'grok-regkit-web' 'uvicorn|web\.server:app' 8092
}

function Get-StatusObject {
    $secrets = Get-SecretsObject
    $cpaHeaders = @{ Authorization = "Bearer $($secrets.cliproxy_api_key)" }
    $integration = $false
    try {
        $i = Invoke-RestMethod -Uri 'http://127.0.0.1:8092/api/integration' -TimeoutSec 5
        $integration = [bool]$i.g2a.ok
    } catch {}
    $proxyRepair = Repair-Sub2ApiLocalPortProxy
    $wslIp = [string]$proxyRepair.wsl_ip
    if (-not $wslIp) { $wslIp = Get-WslIp }
    $proxyTarget = Get-PortProxyTarget -ListenAddress '127.0.0.1' -ListenPort 8080
    return [ordered]@{
        ok = $true
        checked_at = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
        services = [ordered]@{
            grok_regkit_web = [ordered]@{ port = 8092; pid = (Get-PortOwner 8092); tracked_pid = (Get-PidFileValue 'grok-regkit-web'); healthy = (Test-Http 'http://127.0.0.1:8092/health') }
            grok2api = [ordered]@{ port = 8010; pid = (Get-PortOwner 8010); tracked_pid = (Get-PidFileValue 'grok2api'); healthy = (Test-Http 'http://127.0.0.1:8010/health'); regkit_integration = $integration }
            cliproxyapi = [ordered]@{ port = 8317; pid = (Get-PortOwner 8317); tracked_pid = (Get-PidFileValue 'cliproxyapi'); healthy = (Test-Http -Uri 'http://127.0.0.1:8317/v1/models' -Headers $cpaHeaders) }
            cpa_gateway = [ordered]@{ port = 8318; pid = (Get-PortOwner 8318); tracked_pid = (Get-PidFileValue 'cpa-gateway'); healthy = (Test-Http 'http://127.0.0.1:8318/health') }
            sub2api = [ordered]@{
                port = 8080
                pid = (Get-PortOwner 8080)
                healthy = (Test-Http 'http://127.0.0.1:8080/health')
                wsl_keepalive_pid = (Get-TrackedPid -Name 'sub2api-wsl' -ExpectedPattern 'sub2api-keepalive')
                wsl_ip = $wslIp
                portproxy_target = $proxyTarget
                portproxy_repair = $proxyRepair
            }
        }
    }
}

function Install-AutoStart {
    $startup = [Environment]::GetFolderPath('Startup')
    $shortcutPath = Join-Path $startup 'grok-regkit-local-services1.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" Start"
    $shortcut.WorkingDirectory = $Root
    $shortcut.WindowStyle = 7
    $shortcut.Description = 'Start grok-regkit local services'
    $shortcut.Save()
    return $shortcutPath
}

function Remove-AutoStart {
    $shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'grok-regkit-local-services1.lnk'
    if (Test-Path -LiteralPath $shortcutPath) { Remove-Item -LiteralPath $shortcutPath -Force }
}

function Install-Shortcuts {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $shell = New-Object -ComObject WScript.Shell
    $ui = $shell.CreateShortcut((Join-Path $desktop 'Grok注册工具本地控制台1.lnk'))
    $ui.TargetPath = "$env:SystemRoot\explorer.exe"
    $ui.Arguments = 'http://127.0.0.1:8092/'
    $ui.WorkingDirectory = $RegkitRoot
    $ui.Description = 'Open grok-regkit local Web console'
    $ui.Save()
    $admin = $shell.CreateShortcut((Join-Path $desktop 'Grok2API管理后台1.lnk'))
    $admin.TargetPath = "$env:SystemRoot\explorer.exe"
    $admin.Arguments = 'http://127.0.0.1:8010/admin/login'
    $admin.WorkingDirectory = $Grok2ApiRoot
    $admin.Description = 'Open local grok2api admin console'
    $admin.Save()
}

switch ($Action) {
    'Start' { Start-All; Get-StatusObject | ConvertTo-Json -Depth 5 }
    'Stop' { Stop-All; Get-StatusObject | ConvertTo-Json -Depth 5 }
    'Restart' { Stop-All; Start-Sleep -Seconds 2; Start-All; Get-StatusObject | ConvertTo-Json -Depth 5 }
    'Status' { Get-StatusObject | ConvertTo-Json -Depth 5 }
    'InstallAutoStart' { $p = Install-AutoStart; [ordered]@{ok=$true; shortcut=$p} | ConvertTo-Json }
    'RemoveAutoStart' { Remove-AutoStart; [ordered]@{ok=$true} | ConvertTo-Json }
    'InstallShortcuts' { Install-Shortcuts; [ordered]@{ok=$true} | ConvertTo-Json }
}


