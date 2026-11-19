# WarpEngine Local installer for Windows (PowerShell 5.1+, Windows Terminal for the colours).
#
#   irm https://git.teletypegames.org/engines/warp-engine-local/raw/branch/master/install.ps1 | iex
#   & ([scriptblock]::Create((irm …/install.ps1))) -Port 7471 -Admin on
#
# The same answers and options as install.sh: -Port, -SyncTarget, -Admin on|off, -Builders,
# -Version, -Image, -Data, -Yes, -Status, -Uninstall, -Purge.
param(
  [int]$Port = 0,
  [string]$SyncTarget = "",
  [string]$Admin = "",
  [string]$Builders = "",
  [string]$Version = "",
  [string]$Image = "",
  [string]$Data = (Join-Path $HOME ".warpengine"),
  [switch]$Yes,
  [switch]$Status,
  [switch]$Uninstall,
  [switch]$Purge
)

$ErrorActionPreference = "Stop"
$InstallerVersion = "1.0.1"
$Registry = "git.teletypegames.org/build/warp-engine-local"
$Container = "warp-engine-local"
$Label = "org.teletypegames.warp-engine.local=1"
$DefaultPort = 7470
$DefaultSyncTarget = "https://orbit.teletypegames.org"
$Width = 62

$e = [char]27
$fancy = -not $env:NO_COLOR -and $Host.UI.SupportsVirtualTerminal
function C($code) { if ($fancy) { "$e[$($code)m" } else { "" } }
$R = C 0; $B = C 1; $Cy = C 96; $Ye = C 93; $Gr = C 92; $Re = C 91; $Wh = C 97; $Bl = C 94; $Ma = C 95

function BoxTop($title) {
  $t = "[ $title ]"
  Write-Host ("  $Cy" + [char]0x250C + [char]0x2500 + "$Ye$B$t$R$Cy" + ([string][char]0x2500 * ($Width - $t.Length - 1)) + [char]0x2510 + $R)
}
function BoxLine($text, $colored = $null) {
  if ($text.Length -gt $Width - 2) { $text = $text.Substring(0, $Width - 5) + "..."; $colored = $null }
  if (-not $colored) { $colored = $text }
  Write-Host ("  $Cy" + [char]0x2502 + "$R $colored" + (" " * ($Width - $text.Length - 2)) + " $Cy" + [char]0x2502 + $R)
}
function BoxBottom { Write-Host ("  $Cy" + [char]0x2514 + ([string][char]0x2500 * $Width) + [char]0x2518 + $R) }
function StatusLine($label, $state) {
  $tag = @{ OK = "[ OK ]"; FAIL = "[FAIL]"; SKIP = "[SKIP]" }[$state]
  $col = @{ OK = $Gr; FAIL = $Re; SKIP = $Ye }[$state]
  $dots = "." * [Math]::Max(2, $Width - $label.Length - 10)
  BoxLine "$label $dots $tag" "$label $dots $col$B$tag$R"
}
function Fail($message, $hint = "") {
  BoxLine $message "$Re$message$R"
  if ($hint) { BoxLine $hint }
  BoxBottom
  exit 1
}
function Ask() { Write-Host -NoNewline "  $Ye$B>$R "; return [Console]::ReadLine() }

function Banner {
  $bar = [string][char]0x2591 + [char]0x2592 + [char]0x2593 + ([string][char]0x2588 * 58) + [char]0x2593 + [char]0x2592 + [char]0x2591
  Write-Host ""
  Write-Host "  $Bl$bar$R"
  $lines = @(
    @($Cy, "  ██╗    ██╗ █████╗ ██████╗ ██████╗"),
    @($Cy, "  ██║    ██║██╔══██╗██╔══██╗██╔══██╗"),
    @($Cy, "  ██║ █╗ ██║███████║██████╔╝██████╔╝"),
    @($Bl, "  ██║███╗██║██╔══██║██╔══██╗██╔═══╝"),
    @($Bl, "  ╚███╔███╔╝██║  ██║██║  ██║██║"),
    @($Bl, "   ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝"),
    @($Ma, "  ███████╗███╗   ██╗ ██████╗ ██╗███╗   ██╗███████╗"),
    @($Ma, "  ██╔════╝████╗  ██║██╔════╝ ██║████╗  ██║██╔════╝"),
    @($Ma, "  █████╗  ██╔██╗ ██║██║  ███╗██║██╔██╗ ██║█████╗"),
    @($Ma, "  ██╔══╝  ██║╚██╗██║██║   ██║██║██║╚██╗██║██╔══╝"),
    @($Re, "  ███████╗██║ ╚████║╚██████╔╝██║██║ ╚████║███████╗"),
    @($Re, "  ╚══════╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝╚═╝  ╚═══╝╚══════╝")
  )
  foreach ($l in $lines) { Write-Host "  $($l[0])$($l[1])$R"; if ($fancy) { Start-Sleep -Milliseconds 30 } }
  Write-Host "  $Bl$bar$R"
  Write-Host "   $Ye${B}L O C A L$R   ·  a WarpEngine on your machine  ·  installer $InstallerVersion"
  Write-Host ""
}

$configFile = Join-Path $Data "config.json"
$saved = if (Test-Path $configFile) { Get-Content $configFile -Raw | ConvertFrom-Json } else { $null }
function ContainerExists { docker container inspect $Container *> $null; return $LASTEXITCODE -eq 0 }
$interactive = -not $Yes -and [Environment]::UserInteractive -and -not [Console]::IsInputRedirected

if ($Status) {
  Banner; BoxTop "STATUS"
  if (ContainerExists) { BoxLine ("container ........ " + (docker container inspect -f "{{.State.Status}}" $Container)) }
  else { BoxLine "container ........ not installed" }
  if ($saved) { BoxLine "port ............. $($saved.port)"; BoxLine "sync target ...... $($saved.syncTarget)"; BoxLine "admin ............ $($saved.admin)" }
  BoxLine "data ............. $Data"; BoxBottom; exit 0
}

if ($Uninstall) {
  Banner; BoxTop "UNINSTALL"
  if (ContainerExists) { docker rm -f $Container | Out-Null; StatusLine "container removed" OK } else { StatusLine "no container" SKIP }
  docker ps -aq --filter "label=$Label" | ForEach-Object { docker rm -f $_ | Out-Null }
  if ($Purge) { Remove-Item -Recurse -Force $Data -ErrorAction SilentlyContinue; StatusLine "data folder removed" OK }
  else { BoxLine "the data stays in $Data (-Purge removes it)" }
  BoxBottom; exit 0
}

Banner
if ($Port -eq 0) { $Port = if ($saved) { [int]$saved.port } else { $DefaultPort } }
$url = "http://127.0.0.1:$Port"

BoxTop "SYSTEM CHECK"
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Fail "docker was not found" "Install Docker Desktop first." }
StatusLine "docker" OK
docker info *> $null
if ($LASTEXITCODE -ne 0) { Fail "the docker daemon does not answer" "Start Docker Desktop and run this again." }
StatusLine "docker daemon" OK
if (ContainerExists) { StatusLine "port $Port (ours, will be replaced)" OK }
else {
  $taken = $false
  try { $c = New-Object Net.Sockets.TcpClient; $c.Connect("127.0.0.1", $Port); $taken = $true; $c.Close() } catch { }
  if ($taken) { Fail "port $Port is taken by something else" "Choose another one: -Port 7471" }
  StatusLine "port $Port" OK
}
BoxBottom; Write-Host ""

if (-not $SyncTarget) {
  $default = if ($saved -and $saved.syncTarget) { $saved.syncTarget } else { $DefaultSyncTarget }
  if ($interactive) {
    BoxTop "SYNC TARGET"
    BoxLine "Where should your releases go?"
    BoxLine "[Enter] $default" "$Ye[Enter]$R $Wh$default$R"
    BoxLine "or type an address, [-] none" "or type an address, $Ye[-]$R none"
    BoxBottom
    $reply = Ask; Write-Host ""
    $SyncTarget = if ($reply) { $reply } else { $default }
  } else { $SyncTarget = $default }
}
if ($SyncTarget -eq "-") { $SyncTarget = "none" }

if (-not $Admin) {
  $default = if ($saved -and $saved.admin) { "on" } else { "off" }
  if ($interactive) {
    BoxTop "ADMIN WEB UI"
    BoxLine "A web admin at /admin? Headless is the default:"
    BoxLine "the editor and the API are all you need."
    BoxLine "[Y] yes  [N] no (now $default)" "$Ye[Y]$R yes  $Ye[N]$R no (now $default)"
    BoxBottom
    $reply = Ask; Write-Host ""
    $Admin = if ($reply -match "^[yY]") { "on" } elseif ($reply -match "^[nN]") { "off" } else { $default }
  } else { $Admin = $default }
}
$adminFlag = if ($Admin -eq "on") { "1" } else { "0" }
if (-not $Image) { $Image = if ($Version) { "${Registry}:$Version" } else { "${Registry}:$InstallerVersion" } }

BoxTop "INSTALL"
New-Item -ItemType Directory -Force -Path $Data | Out-Null
@{ port = $Port; syncTarget = $SyncTarget; admin = ($Admin -eq "on"); image = $Image; installer = $InstallerVersion } |
  ConvertTo-Json | Set-Content -Path $configFile
StatusLine "data folder" OK
docker pull -q $Image | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "the image could not be pulled: $Image" }
StatusLine "image pulled" OK
if (ContainerExists) { docker rm -f $Container | Out-Null; StatusLine "old container replaced" OK }
docker run -d --name $Container --restart unless-stopped --label $Label `
  -e "PORT=$Port" -e "WARP_SYNC_TARGET=$SyncTarget" -e "WARP_ADMIN=$adminFlag" `
  -p "127.0.0.1:${Port}:$Port" -v "${Data}:/data" $Image | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "the container did not start" }
StatusLine "container started" OK
$ready = $false
for ($i = 0; $i -lt 120 -and -not $ready; $i++) {
  try { Invoke-RestMethod "$url/.well-known/warp-engine" -TimeoutSec 2 | Out-Null; $ready = $true } catch { Start-Sleep 1 }
}
if (-not $ready) { Fail "the engine did not answer in two minutes" "docker logs $Container tells why" }
StatusLine "engine answers" OK
BoxBottom; Write-Host ""

$platforms = (Invoke-RestMethod "$url/build/platforms").platforms | Where-Object { $_.ci.builder }
if (-not $Builders) {
  if ($interactive) {
    BoxTop "BUILDER IMAGES"
    BoxLine "Pull the builder images now? They are large"
    BoxLine "(Godot, Bevy: several GB). Pipelines pull them anyway."
    BoxLine "[N] none (default)  [A] all" "$Ye[N]$R none (default)  $Ye[A]$R all"
    BoxLine ("or a list: " + (($platforms | ForEach-Object name) -join " "))
    BoxBottom
    $reply = Ask; Write-Host ""
    $Builders = if (-not $reply -or $reply -match "^[nN]") { "none" } elseif ($reply -match "^[aA]") { "all" } else { $reply }
  } else { $Builders = "none" }
}
if ($Builders -ne "none") {
  BoxTop "BUILDER IMAGES"
  $wanted = $Builders -split "\s+"
  foreach ($p in $platforms) {
    if ($Builders -ne "all" -and $wanted -notcontains $p.name) { continue }
    docker pull -q $p.ci.builder | Out-Null
    if ($LASTEXITCODE -eq 0) { StatusLine $p.name OK } else { StatusLine $p.name FAIL }
  }
  BoxBottom; Write-Host ""
}

$info = Invoke-RestMethod "$url/.well-known/warp-engine"
BoxTop "READY"
BoxLine "engine ........... $url" "engine ........... $Wh$url$R"
BoxLine "version .......... $($info.version)"
BoxLine "sync target ...... $SyncTarget"
BoxLine "token ............ $(Join-Path $Data 'local-token')"
$adminFile = Join-Path $Data "admin.json"
if ($Admin -eq "on" -and (Test-Path $adminFile)) {
  $a = Get-Content $adminFile -Raw | ConvertFrom-Json
  BoxLine "admin ............ $url/admin" "admin ............ $Wh$url/admin$R"
  BoxLine "                   $($a.email) / $($a.password)"
} else { BoxLine "admin ............ off (-Admin on turns it on)" }
BoxLine ""
BoxLine "Open VS Code: the WarpEngine Toolbox finds this engine" "${Gr}Open VS Code:$R the WarpEngine Toolbox finds this engine"
BoxLine "by itself. Run this again any time to change the answers."
BoxBottom
Write-Host ""
