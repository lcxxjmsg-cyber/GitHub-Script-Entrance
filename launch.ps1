<#
    GitHub Script Entrance - one-line admin launcher (launch.ps1)

    Self-elevates to Administrator, fetches/locates a target script, and runs it.
    Invoke in one line via a scriptblock:

        & ([scriptblock]::Create((irm 'https://gh-proxy.com/https://raw.githubusercontent.com/lcxxjmsg-cyber/GitHub-Script-Entrance/main/launch.ps1'))) -r '<target>'

    -r (target) may be:
      * a github.com page URL   -> https://github.com/user/repo/blob/main/foo.ps1 (auto-converted to raw)
      * a raw / any full URL    -> https://raw.githubusercontent.com/... or https://example.com/foo.ps1
      * a local file path       -> C:\tools\foo.ps1  (absolute path only)

    Supported target types: .ps1 / .bat / .cmd

    Execution:
      * .ps1      -> runs IN MEMORY by default (no temp file). Pass -d to run
                     from a temp file instead (needed if the script relies on
                     $PSScriptRoot / files next to itself).
      * .bat/.cmd -> always downloaded to a temp file and run via cmd.exe, then
                     the temp file is deleted.

    Parameters (short names; PowerShell also accepts unambiguous prefixes):
      -r  Run         target to run (required)
      -a  ScriptArgs  arguments forwarded to the target (array)
      -d  Disk        force .ps1 to run from a temp file instead of memory
      -n  NoElevate   skip self-elevation

    In-memory .ps1 caveat: it has NO $PSScriptRoot / $MyInvocation.MyCommand.Path
    (there is no file on disk). Use -d for scripts that need those.

    github.com / raw.githubusercontent URLs are fetched through GitHub proxy
    mirrors with automatic fallback (bypasses ISP blocking); any other URL is
    downloaded directly.

    NOTE: keep this file ASCII-only so "irm | iex" never mangles it.
#>
param(
    [Parameter(Mandatory = $true)]
    [Alias('r')]  [string]   $Run,             # target: URL | github page URL | local path
    [Alias('a')]  [string[]] $ScriptArgs = @(),# arguments forwarded to the target
    [Alias('d')]  [switch]   $Disk,            # force .ps1 to a temp file (default: memory)
    [Alias('n')]  [switch]   $NoElevate        # skip self-elevation
)

# ---- force TLS 1.2 (required by GitHub) ----
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

$SelfUrl = "https://gh-proxy.com/https://raw.githubusercontent.com/lcxxjmsg-cyber/GitHub-Script-Entrance/main/launch.ps1"

# ---- github.com web URL -> raw.githubusercontent URL ----
function ConvertTo-RawUrl([string]$url) {
    $m = [regex]::Match($url, '^https?://github\.com/(?<repo>[^/]+/[^/]+)/(?:blob|raw)/(?<branch>[^/]+)/(?<path>.+)$')
    if ($m.Success) {
        return "https://raw.githubusercontent.com/$($m.Groups['repo'].Value)/$($m.Groups['branch'].Value)/$($m.Groups['path'].Value)"
    }
    return $url
}

# ---- normalize the target ----
$isUrl = $Run -match '^https?://'
if ($isUrl) {
    $Run = ConvertTo-RawUrl $Run       # github page URL -> raw (if applicable)
} else {
    # local file: absolute path only
    if (-not [System.IO.Path]::IsPathRooted($Run)) {
        Write-Host "[ERROR] Local target must be an absolute path, e.g. C:\tools\x.ps1" -ForegroundColor Red; return
    }
    if (-not (Test-Path -LiteralPath $Run)) {
        Write-Host "[ERROR] Local file not found: $Run" -ForegroundColor Red; return
    }
    $Run = (Resolve-Path -LiteralPath $Run).Path
}

# ---- self-elevate: relaunch as admin, passing the same params ----
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $NoElevate) {
    Write-Host "[*] Requesting administrator privileges..." -ForegroundColor Yellow
    $argList = ''
    if ($ScriptArgs.Count -gt 0) {
        $escaped = $ScriptArgs | ForEach-Object { "'" + ($_ -replace "'","''") + "'" }
        $argList = ' -a ' + ($escaped -join ',')
    }
    if ($Disk) { $argList += ' -d' }
    $inner = "& ([scriptblock]::Create((irm '$SelfUrl'))) -r '$($Run -replace "'","''")'$argList"
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList @(
            '-NoProfile','-ExecutionPolicy','Bypass','-Command', $inner
        )
    } catch {
        Write-Host "[ERROR] Elevation cancelled or failed." -ForegroundColor Red
    }
    return
}

# ================= mirrors =================
# GitHub proxies first (real-time passthrough, always latest, bypass ISP block);
# jsDelivr as fallback; raw last. Non-github URLs are used as-is.
function Get-MirrorUrls([string]$url) {
    $m = [regex]::Match($url, '^https?://raw\.githubusercontent\.com/(?<repo>[^/]+/[^/]+)/(?<branch>[^/]+)/(?<path>.+)$')
    if (-not $m.Success) { return @($url) }
    $r = $m.Groups['repo'].Value; $b = $m.Groups['branch'].Value; $p = $m.Groups['path'].Value
    return @(
        "https://gh-proxy.com/https://raw.githubusercontent.com/$r/$b/$p",
        "https://ghproxy.net/https://raw.githubusercontent.com/$r/$b/$p",
        "https://ghfast.top/https://raw.githubusercontent.com/$r/$b/$p",
        "https://cdn.jsdelivr.net/gh/$r@$b/$p",
        "https://fastly.jsdelivr.net/gh/$r@$b/$p",
        "https://raw.githubusercontent.com/$r/$b/$p"
    )
}

function Download-Bytes([string]$url) {
    foreach ($u in (Get-MirrorUrls $url)) {
        $wc = $null
        try {
            $wc = New-Object System.Net.WebClient
            $data = $wc.DownloadData($u)
            if ($data -and $data.Length -gt 0) { return ,$data }
        } catch {
        } finally { if ($wc) { $wc.Dispose() } }
    }
    throw "All mirrors failed for: $url"
}

function Bytes-ToText([byte[]]$bytes) {
    $s = [System.Text.Encoding]::UTF8.GetString($bytes)
    if ($s.Length -gt 0 -and $s[0] -eq [char]0xFEFF) { $s = $s.Substring(1) }
    return $s
}

$isLocal = -not ($Run -match '^https?://')
$ext = [System.IO.Path]::GetExtension((($Run -split '\?')[0])).ToLowerInvariant()
if (-not $ext) { $ext = '.ps1' }

$tempFiles = @()
function New-TempFrom([byte[]]$bytes, [string]$extension) {
    $tmp = Join-Path $env:TEMP ('launch_' + [Guid]::NewGuid().ToString('N').Substring(0,8) + $extension)
    [System.IO.File]::WriteAllBytes($tmp, $bytes)
    $script:tempFiles += $tmp
    return $tmp
}

try {
    switch ($ext) {
        '.ps1' {
            if ($Disk) {
                # run from a temp file (keeps $PSScriptRoot working)
                if ($isLocal) { $path = $Run }
                else { $path = New-TempFrom (Download-Bytes $Run) '.ps1' }
                Write-Host "[*] Running .ps1 (disk)" -ForegroundColor Cyan
                & $path @ScriptArgs
            } else {
                # run in memory (no temp file; no $PSScriptRoot)
                if ($isLocal) { $text = Bytes-ToText ([System.IO.File]::ReadAllBytes($Run)) }
                else { $text = Bytes-ToText (Download-Bytes $Run) }
                Write-Host "[*] Running .ps1 (memory)" -ForegroundColor Cyan
                & ([scriptblock]::Create($text)) @ScriptArgs
            }
        }
        { $_ -in '.bat','.cmd' } {
            # batch always runs from a temp file, then is deleted
            if ($isLocal) { $path = $Run }
            else { $path = New-TempFrom (Download-Bytes $Run) $ext }
            Write-Host "[*] Running $ext (disk)" -ForegroundColor Cyan
            & cmd.exe /c $path @ScriptArgs
        }
        default {
            Write-Host "[ERROR] Unsupported target type: $ext (only .ps1/.bat/.cmd)" -ForegroundColor Red
        }
    }
}
catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    foreach ($f in $tempFiles) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
}
