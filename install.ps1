# WarpEngine Local installer for Windows (PowerShell 5.1+, Windows Terminal for the colours).
#
#   irm https://git.teletypegames.org/engines/warp-engine-local/raw/branch/master/install.ps1 | iex
#   & ([scriptblock]::Create((irm …/install.ps1))) -Port 7471 -Admin on
#
# The same answers and options as install.sh: -Port, -SyncTarget, -Admin on|off, -AdminBypass on|off, -Ci on|off, -Builders,
# -Version, -Image, -Data, -Yes, -Status, -Uninstall, -Purge.
param(
  [int]$Port = 0,
  [string]$SyncTarget = "",
  [string]$Admin = "",
  [string]$AdminBypass = "",
  [string]$Ci = "",
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
$InstallerVersion = "2.0.0"
$Registry = "git.teletypegames.org/build/warp-engine-local"
$Container = "warp-engine-local"
$Network = "warp-engine-local"
$LegacyPrefix = "warp-local"
$Label = "org.teletypegames.warp-engine.local=1"
$DefaultPort = 7470
$DefaultSyncTarget = "none"
$ExampleSyncTarget = "https://games.example.org"
$Width = 62

$e = [char]27
$fancy = -not $env:NO_COLOR -and $Host.UI.SupportsVirtualTerminal
function C($code) { if ($fancy) { "$e[$($code)m" } else { "" } }
$R = C 0; $B = C 1; $Dim = C 2; $Cy = C 96; $Ye = C 93; $Gr = C 92; $Re = C 91; $Wh = C 97; $Bl = C 94; $Ma = C 95

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

function MenuDraw($sel, [string[]]$labels) {
  for ($i = 0; $i -lt $labels.Count; $i++) {
    if ($i -eq $sel) { BoxLine "> $($labels[$i])" "$Ye$B>$R $Wh$B$($labels[$i])$R" } else { BoxLine "  $($labels[$i])" "  $($labels[$i])" }
  }
  BoxBottom
}

function MenuTyped($sel, [string[]]$labels) {
  for ($i = 0; $i -lt $labels.Count; $i++) { $mark = if ($i -eq $sel) { "*" } else { " " }; BoxLine "$mark $($i + 1)) $($labels[$i])" }
  BoxLine "(a number; Enter keeps the one marked *)"
  BoxBottom
  $reply = Ask
  $n = 0
  if ([int]::TryParse($reply, [ref]$n) -and $n -ge 1 -and $n -le $labels.Count) { return $n - 1 }
  return $sel
}

# Menu DEFAULT LABELS: a choice inside the open box; returns its index.
function Menu($sel, [string[]]$labels) {
  if (-not $fancy) { $sel = MenuTyped $sel $labels; Write-Host ""; return $sel }
  BoxLine "[Up/Down] move  [Enter] choose" "$Dim[Up/Down] move  [Enter] choose$R"
  BoxLine ""
  MenuDraw $sel $labels
  $top = [Console]::CursorTop - $labels.Count - 1
  [Console]::CursorVisible = $false
  try {
    while ($true) {
      $key = [Console]::ReadKey($true)
      if ($key.Key -eq "Enter") { break }
      if ($key.Key -eq "UpArrow" -or $key.KeyChar -eq "k") { $sel = ($sel + $labels.Count - 1) % $labels.Count }
      elseif ($key.Key -eq "DownArrow" -or $key.KeyChar -eq "j") { $sel = ($sel + 1) % $labels.Count }
      elseif ($key.KeyChar -match "^[1-9]$" -and [int]"$($key.KeyChar)" -le $labels.Count) { $sel = [int]"$($key.KeyChar)" - 1 }
      [Console]::SetCursorPosition(0, $top)
      MenuDraw $sel $labels
    }
  } finally { [Console]::CursorVisible = $true }
  Write-Host ""
  return $sel
}

function YesNo($default, $yes, $no) {
  if (-not $interactive) { return $default }
  $start = if ($default -eq "on") { 0 } else { 1 }
  if ((Menu $start @($yes, $no)) -eq 0) { return "on" } else { return "off" }
}

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
  if ($saved) { BoxLine "port ............. $($saved.port)"; BoxLine "sync target ...... $($saved.syncTarget)"; BoxLine "admin ............ $($saved.admin) (bypass: $($saved.adminBypass))"; BoxLine "local CI ......... $($saved.ci)" }
  BoxLine "data ............. $Data"; BoxBottom; exit 0
}

if ($Uninstall) {
  Banner; BoxTop "UNINSTALL"
  if (ContainerExists) { docker rm -f $Container | Out-Null; StatusLine "container removed" OK } else { StatusLine "no container" SKIP }
  $images = @(docker ps -a --filter "label=$Label" --format "{{.Image}}")
  docker ps -aq --filter "label=$Label" | ForEach-Object { docker rm -f $_ | Out-Null }
  if ($Purge) {
    Remove-Item -Recurse -Force $Data -ErrorAction SilentlyContinue; StatusLine "data folder removed" OK
    docker volume ls -q --filter "label=$Label" | ForEach-Object { docker volume rm $_ | Out-Null }
    foreach ($n in @($Network, $LegacyPrefix)) { docker network rm $n 2>$null | Out-Null }
    $images += @(docker images --format "{{.Repository}}:{{.Tag}}" $Registry)
    $removed = 0
    foreach ($i in ($images | Sort-Object -Unique)) { docker image rm $i 2>$null | Out-Null; if ($LASTEXITCODE -eq 0) { $removed++ } }
    StatusLine "$removed image(s) removed" OK
  }
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
  $SyncTarget = if ($saved -and $saved.syncTarget) { $saved.syncTarget } else { $DefaultSyncTarget }
  if ($interactive) {
    BoxTop "SYNC TARGET"
    BoxLine "Send your releases on to another WarpEngine instance?"
    if ($SyncTarget -eq "none") {
      if ((Menu 0 @("No: they stay on this machine", "Yes: type its address")) -eq 1) { $SyncTarget = "?" }
    } else {
      $choice = Menu 1 @("No: they stay on this machine", "Yes: $SyncTarget", "Another one: type its address")
      if ($choice -eq 0) { $SyncTarget = "none" } elseif ($choice -eq 2) { $SyncTarget = "?" }
    }
    if ($SyncTarget -eq "?") {
      BoxTop "SYNC TARGET"; BoxLine "Its address, e.g. $ExampleSyncTarget"; BoxBottom
      $SyncTarget = Ask; Write-Host ""
      if (-not $SyncTarget) { $SyncTarget = "none" }
    }
  }
}
if ($SyncTarget -eq "-") { $SyncTarget = "none" }

$answered = $saved -and ($saved.PSObject.Properties.Name -contains "adminBypass")
function SavedOnOff($value) { if (-not $answered) { return "on" } elseif ($value) { return "on" } else { return "off" } }

if (-not $Admin) {
  if ($interactive) { BoxTop "ADMIN WEB UI"; BoxLine "A web admin at /admin: the catalog, the releases, the"; BoxLine "sync peers, the tool sign-ins, in your browser." }
  $Admin = YesNo (SavedOnOff $saved.admin) "Yes: the admin web UI at /admin" "No: headless, the editor and the API are enough"
}
if ($Admin -ne "on") { $AdminBypass = "off" }
elseif (-not $AdminBypass) {
  if ($interactive) { BoxTop "ADMIN SIGN-IN"; BoxLine "Only this machine reaches the engine (127.0.0.1)."; BoxLine "Skip the password there?" }
  $AdminBypass = YesNo (SavedOnOff $saved.adminBypass) "Yes: /admin signs you in by itself" "No: sign in with the password in admin.json"
}
$adminFlag = if ($Admin -eq "on") { "1" } else { "0" }
$bypassFlag = if ($AdminBypass -eq "on") { "1" } else { "0" }
$previousCi = [bool]($saved -and $saved.ci)
if (-not $Ci) {
  if ($interactive) { BoxTop "LOCAL CI"; BoxLine "A git server (Gitea) and a CI (Woodpecker) beside the"; BoxLine "engine: your projects push there, it builds them and"; BoxLine "publishes here. Started and wired for you, no sign-in." }
  $Ci = YesNo (SavedOnOff $saved.ci) "Yes: the git server and the CI" "No: the engine only"
}
if (-not $Image) { $Image = if ($Version) { "${Registry}:$Version" } else { "${Registry}:$InstallerVersion" } }

BoxTop "INSTALL"
New-Item -ItemType Directory -Force -Path $Data | Out-Null
@{ port = $Port; syncTarget = $SyncTarget; admin = ($Admin -eq "on"); adminBypass = ($AdminBypass -eq "on"); ci = ($Ci -eq "on"); image = $Image; installer = $InstallerVersion } |
  ConvertTo-Json | Set-Content -Path $configFile
StatusLine "data folder" OK
docker pull -q $Image | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "the image could not be pulled: $Image" }
StatusLine "image pulled" OK
if (ContainerExists) { docker rm -f $Container | Out-Null; StatusLine "old container replaced" OK }
docker network inspect $Network 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { docker network create --label $Label $Network | Out-Null }
StatusLine "network $Network" OK
$legacy = @(docker ps -aq --filter "label=$Label" --filter "name=^$LegacyPrefix-")
if ($legacy.Count -gt 0) {
  $legacy | ForEach-Object { docker rm -f $_ | Out-Null }
  docker volume ls -q --filter "label=$Label" --filter "name=^$LegacyPrefix-" | ForEach-Object { docker volume rm $_ 2>$null | Out-Null }
  docker network rm $LegacyPrefix 2>$null | Out-Null
  StatusLine "old $LegacyPrefix-* git server and CI removed" OK
}
docker run -d --name $Container --restart unless-stopped --label $Label --network $Network --network-alias $Container `
  -v "/var/run/docker.sock:/var/run/docker.sock" `
  -e "PORT=$Port" -e "WARP_SYNC_TARGET=$SyncTarget" -e "WARP_ADMIN=$adminFlag" -e "WARP_ADMIN_BYPASS=$bypassFlag" `
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

if ($Ci -eq "on") {
  BoxTop "LOCAL CI"
  Write-Host "  starting the git server and CI (the first time pulls their images) ..."
  $ciLog = docker exec $Container bin/rails "warp_engine:local:enable[woodpecker]" 2>&1
  if ($LASTEXITCODE -eq 0) {
    StatusLine "git server 127.0.0.1:$($Port + 1)" OK; StatusLine "CI" OK
    if ($legacy.Count -gt 0) { BoxLine "projects on the old CI: Set up local CI again in VS Code" }
  }
  else { StatusLine "git server and CI" FAIL; $ciLog | Select-Object -Last 3 | ForEach-Object { BoxLine "$_" }; $Ci = "failed" }
  BoxBottom; Write-Host ""
} elseif ($previousCi) {
  docker exec $Container bin/rails "warp_engine:local:disable[gitea]" 2>&1 | Out-Null
}
$platforms = (Invoke-RestMethod "$url/build/platforms").platforms | Where-Object { $_.ci.builder }
if (-not $Builders) {
  $Builders = "none"
  if ($interactive) {
    BoxTop "BUILDER IMAGES"
    BoxLine "Pull the builder images now? They are large (Godot,"
    BoxLine "Bevy: several GB), and the pipelines pull them anyway."
    $choice = Menu 0 @("No: the pipelines pull them when they need them", "All of them", "Some: type their names")
    if ($choice -eq 1) { $Builders = "all" }
    elseif ($choice -eq 2) {
      BoxTop "BUILDER IMAGES"; BoxLine ("names: " + (($platforms | ForEach-Object name) -join " ")); BoxBottom
      $Builders = Ask; Write-Host ""
      if (-not $Builders) { $Builders = "none" }
    }
  }
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
if ($Admin -eq "on" -and $AdminBypass -eq "on") {
  BoxLine "admin ............ $url/admin" "admin ............ $Wh$url/admin$R"
  BoxLine "                   signs you in by itself"
} elseif ($Admin -eq "on" -and (Test-Path $adminFile)) {
  $a = Get-Content $adminFile -Raw | ConvertFrom-Json
  BoxLine "admin ............ $url/admin" "admin ............ $Wh$url/admin$R"
  BoxLine "                   $($a.email) / $($a.password)"
} else { BoxLine "admin ............ off (-Admin on turns it on)" }
BoxLine ""
if ($Ci -eq "on") { BoxLine "local CI ......... git server http://localhost:$($Port + 1)"; BoxLine "                   + Woodpecker, VS Code offers it" }
elseif ($Ci -eq "failed") { BoxLine "local CI ......... did not start (-Ci on retries)" }
else { BoxLine "local CI ......... off (-Ci on turns it on)" }
BoxLine ""
BoxLine "Open VS Code: the WarpEngine Toolbox finds this engine" "${Gr}Open VS Code:$R the WarpEngine Toolbox finds this engine"
BoxLine "by itself. Run this again any time to change the answers."
BoxBottom
Write-Host ""
