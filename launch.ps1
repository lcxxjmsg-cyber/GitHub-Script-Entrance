<#
    GitHub Script Entrance - universal admin launcher (launch.ps1)

    A tiny "shell" that: self-elevates to Administrator, fetches/locates a
    target script, and runs it. Designed to be invoked in one line via irm | iex
    with parameters passed through a scriptblock:

        & ([scriptblock]::Create((irm 'https://gh-proxy.com/https://raw.githubusercontent.com/lcxxjmsg-cyber/GitHub-Script-Entrance/main/launch.ps1'))) -Run '<target>'

    The -Run target may be:
      * a github.com page URL   -> https://github.com/user/repo/blob/main/foo.ps1 (auto-converted to raw)
      * a raw / any full URL    -> https://raw.githubusercontent.com/... or https://example.com/foo.ps1
      * a repo-relative path    -> client/setup.ps1   (resolved against -Repo/-Branch)
      * a local file path       -> C:\tools\foo.ps1  or  .\foo.ps1

    Supported target types: .ps1 (run in-process), .bat/.cmd (run via cmd.exe),
    .exe (run directly), .msi (run via msiexec). Extra args after -ScriptArgs are
    forwarded to the target.

    github.com / raw.githubusercontent URLs (and repo-relative paths) are fetched
    through GitHub proxy mirrors with automatic fallback (bypasses ISP blocking);
    any other URL is downloaded directly.

    NOTE: keep this file ASCII-only so "irm | iex" never mangles it, regardless
    of the mirror's charset.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]   $Run,                 # target: URL | repo-relative | local path
    [string]   $Repo    = 'lcxxjmsg-cyber/GitHub-Script-Entrance',
    [string]   $Branch  = 'main',
    [string[]] $ScriptArgs = @(),    # arguments forwarded to the target
    [switch]   $NoElevate            # skip self-elevation (already admin / not needed)
)

# ---- force TLS 1.2 (required by GitHub) ----
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

# ---- normalize a github.com web URL into a raw.githubusercontent URL ----
# So you can paste the easy-to-remember page URL instead of the raw one:
#   https://github.com/USER/REPO/blob/BRANCH/PATH  -> raw.githubusercontent.com/USER/REPO/BRANCH/PATH
#   https://github.com/USER/REPO/raw/BRANCH/PATH   -> (same)
# Already-raw URLs and non-github URLs are returned unchanged.
function ConvertTo-RawUrl([string]$url) {
    $m = [regex]::Match($url, '^https?://github\.com/(?<repo>[^/]+/[^/]+)/(?:blob|raw)/(?<branch>[^/]+)/(?<path>.+)$')
    if ($m.Success) {
        return "https://raw.githubusercontent.com/$($m.Groups['repo'].Value)/$($m.Groups['branch'].Value)/$($m.Groups['path'].Value)"
    }
    return $url
}

$SelfUrl = "https://gh-proxy.com/https://raw.githubusercontent.com/$Repo/$Branch/launch.ps1"

# ---- normalize the target ----
$isUrl = $Run -match '^https?://'
if ($isUrl) {
    $Run = ConvertTo-RawUrl $Run      # github.com page URL -> raw URL (if applicable)
} else {
    # local path: absolutize BEFORE elevation (CWD changes after relaunch)
    $maybeLocal = $null
    try { $maybeLocal = (Resolve-Path -LiteralPath $Run -ErrorAction Stop).Path } catch {}
    if ($maybeLocal) { $Run = $maybeLocal }   # real local file -> absolutize
    # otherwise treat it as a repo-relative path (resolved later)
}

# ---- self-elevate: relaunch this shell as admin, passing the same params ----
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $NoElevate) {
    Write-Host "[*] Requesting administrator privileges..." -ForegroundColor Yellow
    # Rebuild the one-liner for the elevated child. Local files are already
    # absolute, so they still resolve after the working directory changes.
    $argList = ''
    if ($ScriptArgs.Count -gt 0) {
        $escaped = $ScriptArgs | ForEach-Object { "'" + ($_ -replace "'","''") + "'" }
        $argList = ' -ScriptArgs ' + ($escaped -join ',')
    }
    $inner = "& ([scriptblock]::Create((irm '$SelfUrl'))) -Run '$($Run -replace "'","''")' -Repo '$Repo' -Branch '$Branch'$argList"
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
# jsDelivr as fallback for small files; raw last.
function Get-MirrorUrls([string]$url) {
    # Only rewrite raw.githubusercontent URLs into proxy variants; other hosts
    # are used as-is.
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

# ---- resolve the target into: a runnable local path (download if remote) ----
$tempFiles = @()
function Resolve-Target {
    # 1) already a local file
    if (-not ($Run -match '^https?://')) {
        if (Test-Path -LiteralPath $Run) { return (Resolve-Path -LiteralPath $Run).Path }
        # 2) repo-relative -> build a raw URL and fall through to download
        $script:Run = "https://raw.githubusercontent.com/$Repo/$Branch/$($Run.TrimStart('/'))"
    }
    # 3) remote: download to a temp file, keep original extension
    $ext = [System.IO.Path]::GetExtension(($Run -split '\?')[0])
    if (-not $ext) { $ext = '.ps1' }
    $tmp = Join-Path $env:TEMP ('launch_' + [Guid]::NewGuid().ToString('N').Substring(0,8) + $ext)
    [System.IO.File]::WriteAllBytes($tmp, (Download-Bytes $Run))
    $script:tempFiles += $tmp
    return $tmp
}

try {
    $target = Resolve-Target
    $ext = [System.IO.Path]::GetExtension($target).ToLowerInvariant()
    Write-Host "[*] Running: $target" -ForegroundColor Cyan

    switch ($ext) {
        '.ps1' {
            # Call operator runs in the same window (interactive Read-Host works)
            # and forwards the argument array element-by-element (no re-splitting).
            & $target @ScriptArgs
        }
        '.msi' {
            $pa = @('/i', $target) + $ScriptArgs
            Start-Process msiexec.exe -ArgumentList $pa -Wait
        }
        '.exe' {
            if ($ScriptArgs.Count -gt 0) { & $target @ScriptArgs }
            else { & $target }
        }
        { $_ -in '.bat','.cmd' } {
            # Batch scripts must run through cmd.exe from a real file on disk.
            & cmd.exe /c $target @ScriptArgs
        }
        default {
            Write-Host "[ERROR] Unsupported target type: $ext (only .ps1/.bat/.cmd/.exe/.msi)" -ForegroundColor Red
        }
    }
}
catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    foreach ($f in $tempFiles) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
}
