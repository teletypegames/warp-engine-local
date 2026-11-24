#!/bin/sh
# WarpEngine Local installer: one container on your machine, one port, your
# releases synced on to another WarpEngine instance if you name one, and a git
# server and CI beside it if you want them.
#
#   curl -fsSL https://git.teletypegames.org/engines/warp-engine-local/raw/branch/master/install.sh | sh
#   curl -fsSL …/install.sh | sh -s -- --port 7471 --admin on
#
# Options:
#   --port N               the port on 127.0.0.1 (default 7470)
#   --sync-target URL      another WarpEngine instance your releases go to, e.g.
#                          https://games.example.org (default none)
#   --admin on|off         the admin web UI at /admin (default on)
#   --admin-bypass on|off  /admin signs you in by itself, no password (default on)
#   --ci on|off            a git server (Gitea) and a CI (Woodpecker) beside the
#                          engine, on 127.0.0.1:<port + 1> (default on)
#   --builders LIST        pull builder images now: none, all, or names (c64 love …)
#   --version V            the engine image version (default: this installer's)
#   --image REF            a whole image reference instead (for testing a build of your own)
#   --data DIR             the data folder (default ~/.warpengine)
#   --yes                  ask nothing: the saved answers, or the defaults
#   --status               show what is installed
#   --uninstall            remove the containers (the data stays; --purge removes
#                          the data, the volumes, the network and the images too)
#
# Without a terminal (CI, a tool running it) it asks nothing either.
set -eu

INSTALLER_VERSION="1.6.0"
REGISTRY="git.teletypegames.org/build/warp-engine-local"
CONTAINER="warp-engine-local"
NETWORK="warp-engine-local"
LEGACY_PREFIX="warp-local"
SOCKET="/var/run/docker.sock"
LABEL="org.teletypegames.warp-engine.local=1"
DEFAULT_PORT=7470
DEFAULT_SYNC_TARGET="none"
EXAMPLE_SYNC_TARGET="https://games.example.org"

port=""
sync_target=""
admin=""
admin_bypass=""
ci=""
builders=""
version=""
image=""
data_dir="${HOME}/.warpengine"
assume_yes=0
action="install"
purge=0

die_usage() { printf '%s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --port) port="${2:?--port needs a number}"; shift 2 ;;
    --sync-target) sync_target="${2:?--sync-target needs an address or none}"; shift 2 ;;
    --admin) admin="${2:?--admin needs on or off}"; shift 2 ;;
    --admin-bypass) admin_bypass="${2:?--admin-bypass needs on or off}"; shift 2 ;;
    --ci) ci="${2:?--ci needs on or off}"; shift 2 ;;
    --builders) builders="${2:?--builders needs none, all or a list}"; shift 2 ;;
    --version) version="${2:?--version needs a version}"; shift 2 ;;
    --image) image="${2:?--image needs an image reference}"; shift 2 ;;
    --data) data_dir="${2:?--data needs a folder}"; shift 2 ;;
    --yes|-y) assume_yes=1; shift ;;
    --status) action="status"; shift ;;
    --uninstall) action="uninstall"; shift ;;
    --purge) purge=1; shift ;;
    -h|--help) sed -n '2,/^set -eu/p' "$0" 2>/dev/null | sed '$d' || true; exit 0 ;;
    *) die_usage "unknown option: $1 (--help lists them)" ;;
  esac
done

# --- the screen ---------------------------------------------------------------

ESC=$(printf '\033')
fancy=0
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then fancy=1; fi
utf8=0
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in *UTF-8*|*utf8*|*UTF8*|*utf-8*) utf8=1 ;; esac
[ "$fancy" = 1 ] || utf8=0

if [ "$fancy" = 1 ]; then
  R="${ESC}[0m"; B="${ESC}[1m"; DIM="${ESC}[2m"
  RED="${ESC}[31m"; YEL="${ESC}[33m"; BLU="${ESC}[34m"; MAG="${ESC}[35m"; CYN="${ESC}[36m"; WHT="${ESC}[37m"
  BRED="${ESC}[91m"; BGRN="${ESC}[92m"; BYEL="${ESC}[93m"; BBLU="${ESC}[94m"; BMAG="${ESC}[95m"; BCYN="${ESC}[96m"; BWHT="${ESC}[97m"
else
  R=""; B=""; DIM=""; RED=""; YEL=""; BLU=""; MAG=""; CYN=""; WHT=""
  BRED=""; BGRN=""; BYEL=""; BBLU=""; BMAG=""; BCYN=""; BWHT=""
fi

if [ "$utf8" = 1 ]; then
  TL="┌"; TR="┐"; BL="└"; BR="┘"; H="─"; V="│"
else
  TL="+"; TR="+"; BL="+"; BR="+"; H="-"; V="|"
fi

WIDTH=62

pause() {
  if [ "$fancy" = 1 ]; then sleep "$1" 2>/dev/null || true; fi
}

repeat() {
  n=$2; out=""
  while [ "$n" -gt 0 ]; do out="${out}$1"; n=$((n - 1)); done
  printf '%s' "$out"
}

say() { printf '%s\n' "$*"; }

box_top() {
  title="[ $1 ]"
  rest=$((WIDTH - ${#title} - 1))
  printf '  %s%s%s%s%s%s%s%s\n' "$BCYN" "$TL" "$H" "$BYEL$B" "$title" "$R$BCYN" "$(repeat "$H" "$rest")" "$TR$R"
}

short() {
  max=$2
  if [ ${#1} -le "$max" ]; then printf '%s' "$1"; return; fi
  keep=$(((max - 3) / 2))
  printf '%s...%s' "$(printf '%s' "$1" | cut -c1-"$keep")" "$(printf '%s' "$1" | rev | cut -c1-"$keep" | rev)"
}

home_path() { printf '%s' "$1" | sed "s|^$HOME|~|"; }

box_line() {
  text="$1"; colored="${2:-$1}"
  if [ ${#text} -gt $((WIDTH - 2)) ]; then
    text=$(short "$text" $((WIDTH - 2))); colored=$text
  fi
  pad=$((WIDTH - ${#text} - 2))
  [ "$pad" -lt 0 ] && pad=0
  printf '  %s%s%s %s%s %s%s%s\n' "$BCYN" "$V" "$R" "$colored" "$(repeat ' ' "$pad")" "" "$BCYN$V" "$R"
}

box_bottom() { printf '  %s%s%s%s%s\n' "$BCYN" "$BL" "$(repeat "$H" "$((WIDTH))")" "$BR" "$R"; }

dots() {
  label="$1"
  n=$((WIDTH - ${#label} - 10))
  [ "$n" -lt 2 ] && n=2
  printf '%s %s ' "$label" "$(repeat '.' "$n")"
}

status_line() {
  label="$1"; state="$2"
  case "$state" in
    OK) tag="[ OK ]"; col="$BGRN" ;;
    FAIL) tag="[FAIL]"; col="$BRED" ;;
    SKIP) tag="[SKIP]"; col="$YEL" ;;
    *) tag="[ .. ]"; col="$WHT" ;;
  esac
  plain="$(dots "$label")$tag"
  box_line "$plain" "$(dots "$label")${col}${B}${tag}${R}"
}

banner() {
  if [ "$utf8" = 1 ]; then
    bar="░▒▓$(repeat '█' 58)▓▒░"
    printf '\n  %s%s%s\n' "$BBLU" "$bar" "$R"
    for line in \
      "$BCYN|  ██╗    ██╗ █████╗ ██████╗ ██████╗" \
      "$BCYN|  ██║    ██║██╔══██╗██╔══██╗██╔══██╗" \
      "$CYN|  ██║ █╗ ██║███████║██████╔╝██████╔╝" \
      "$BBLU|  ██║███╗██║██╔══██║██╔══██╗██╔═══╝" \
      "$BLU|  ╚███╔███╔╝██║  ██║██║  ██║██║" \
      "$BLU|   ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝" \
      "$BMAG|  ███████╗███╗   ██╗ ██████╗ ██╗███╗   ██╗███████╗" \
      "$BMAG|  ██╔════╝████╗  ██║██╔════╝ ██║████╗  ██║██╔════╝" \
      "$MAG|  █████╗  ██╔██╗ ██║██║  ███╗██║██╔██╗ ██║█████╗" \
      "$MAG|  ██╔══╝  ██║╚██╗██║██║   ██║██║██║╚██╗██║██╔══╝" \
      "$BRED|  ███████╗██║ ╚████║╚██████╔╝██║██║ ╚████║███████╗" \
      "$RED|  ╚══════╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝╚═╝  ╚═══╝╚══════╝"; do
      printf '  %s%s%s\n' "${line%%|*}" "${line#*|}" "$R"
      pause 0.03
    done
    printf '  %s%s%s\n' "$BBLU" "$bar" "$R"
    printf '   %s%sL O C A L%s   %s·  a WarpEngine on your machine  ·  installer %s%s\n\n' \
      "$BYEL" "$B" "$R" "$DIM" "$INSTALLER_VERSION" "$R"
  else
    say ""
    say "  ==============================================================="
    say "   W A R P   E N G I N E   -   L O C A L      (installer $INSTALLER_VERSION)"
    say "  ==============================================================="
    say ""
  fi
}

spinner_wait() {
  pid=$1; label=$2
  if [ "$fancy" = 1 ]; then
    i=0
    while kill -0 "$pid" 2>/dev/null; do
      case $((i % 4)) in 0) f='|' ;; 1) f='/' ;; 2) f='-' ;; *) f="\\" ;; esac
      printf '\r  %s%s%s %s%s%s %s' "$BCYN" "$V" "$R" "$WHT" "$label" "$R" "$BYEL$f$R"
      i=$((i + 1))
      sleep 0.15
    done
    printf '\r%s\r' "$(repeat ' ' $((WIDTH + 6)))"
  fi
  wait "$pid"
}

fail() {
  box_line "$1" "${BRED}${1}${R}"
  [ -n "${2:-}" ] && box_line "$2"
  box_bottom
  exit 1
}

# --- questions ----------------------------------------------------------------

interactive=0
if [ "$assume_yes" = 0 ] && [ -t 1 ] && { : </dev/tty; } 2>/dev/null; then interactive=1; fi

ask() {
  printf '  %s>%s ' "$BYEL$B" "$R" >/dev/tty
  answer=""
  IFS= read -r answer </dev/tty || answer=""
  printf '%s' "$answer"
}

menu_draw() {
  i=0
  for label in "$@"; do
    if [ "$i" = "$sel" ]; then
      box_line "> $label" "${BYEL}${B}>${R} ${BWHT}${B}${label}${R}"
    else
      box_line "  $label" "  ${WHT}${label}${R}"
    fi
    i=$((i + 1))
  done
}

menu_key() {
  dd bs=1 count="$1" 2>/dev/null </dev/tty
}

menu_restore() {
  [ -n "${tty_state:-}" ] && stty "$tty_state" </dev/tty 2>/dev/null
  printf '%s' "${ESC}[?25h"
}

menu_pick() {
  count=$#
  tty_state=$(stty -g </dev/tty)
  trap 'menu_restore; exit 130' INT TERM
  stty -icanon -echo min 1 time 0 </dev/tty
  printf '%s' "${ESC}[?25l"
  while :; do
    key=$(menu_key 1)
    case "$key" in
      "") break ;;
      "$ESC") case "$(menu_key 2)" in "[A"|OA) sel=$(((sel + count - 1) % count)) ;; "[B"|OB) sel=$(((sel + 1) % count)) ;; esac ;;
      k|K) sel=$(((sel + count - 1) % count)) ;;
      j|J) sel=$(((sel + 1) % count)) ;;
      [1-9]) [ "$key" -le "$count" ] && sel=$((key - 1)) ;;
    esac
    printf '%s' "${ESC}[$((count + 1))A"
    menu_draw "$@"
    box_bottom
  done
  menu_restore
  trap - INT TERM
  tty_state=""
}

menu_typed() {
  n=1
  for label in "$@"; do
    mark=" "
    [ $((n - 1)) = "$sel" ] && mark="*"
    box_line "$mark $n) $label"
    n=$((n + 1))
  done
  box_line "(a number; Enter keeps the one marked *)"
  box_bottom
  reply=$(ask)
  case "$reply" in
    ""|*[!0-9]*) ;;
    *) [ "$reply" -ge 1 ] && [ "$reply" -le $# ] && sel=$((reply - 1)) ;;
  esac
}

# menu DEFAULT LABEL... : a choice inside the open box; sets $choice (0-based).
menu() {
  sel=$1
  shift
  if [ "$fancy" = 1 ]; then
    box_line "[Up/Down] move  [Enter] choose" "${DIM}[Up/Down] move  [Enter] choose${R}"
    box_line ""
    menu_draw "$@"
    box_bottom
    menu_pick "$@"
  else
    menu_typed "$@"
  fi
  choice=$sel
  say ""
}

# --- saved answers ------------------------------------------------------------

config_file="$data_dir/config.json"

on_off() { case "$1" in true) echo on ;; false) echo off ;; *) echo "$2" ;; esac; }

answered() { [ -f "$config_file" ] && grep -q '"adminBypass"' "$config_file"; }

saved() {
  [ -f "$config_file" ] || return 0
  sed -n "s/.*\"$1\": *\"\{0,1\}\([^\",}]*\)\"\{0,1\}.*/\1/p" "$config_file" | head -n 1
}

write_config() {
  mkdir -p "$data_dir"
  chmod 700 "$data_dir" 2>/dev/null || true
  cat >"$config_file" <<EOF
{
  "port": $port,
  "syncTarget": "$sync_target",
  "admin": $( [ "$admin" = on ] && echo true || echo false ),
  "adminBypass": $( [ "$admin_bypass" = on ] && echo true || echo false ),
  "ci": $( [ "$ci" = on ] && echo true || echo false ),
  "image": "$image",
  "installer": "$INSTALLER_VERSION"
}
EOF
}

engine_url() { printf 'http://127.0.0.1:%s' "$port"; }

container_exists() { docker container inspect "$CONTAINER" >/dev/null 2>&1; }

# --- status and uninstall -----------------------------------------------------

if [ "$action" = "status" ]; then
  banner
  box_top "STATUS"
  if container_exists; then
    state=$(docker container inspect -f '{{.State.Status}}' "$CONTAINER")
    box_line "container ........ $state"
    box_line "image ............ $(docker container inspect -f '{{.Config.Image}}' "$CONTAINER")"
  else
    box_line "container ........ not installed"
  fi
  box_line "port ............. $(saved port)"
  box_line "sync target ...... $(saved syncTarget)"
  box_line "admin ............ $(saved admin) (bypass: $(saved adminBypass))"
  box_line "local CI ......... $(saved ci)"
  box_line "data ............. $(home_path "$data_dir")"
  box_bottom
  exit 0
fi

if [ "$action" = "uninstall" ]; then
  banner
  box_top "UNINSTALL"
  images=$(docker ps -a --filter "label=$LABEL" --format '{{.Image}}' | sort -u)
  if container_exists; then
    docker rm -f "$CONTAINER" >/dev/null
    status_line "container removed" OK
  else
    status_line "no container" SKIP
  fi
  components=$(docker ps -aq --filter "label=$LABEL")
  if [ -n "$components" ]; then
    for c in $components; do docker rm -f "$c" >/dev/null; done
    status_line "git server and CI removed" OK
  fi
  if [ "$purge" = 1 ]; then
    rm -rf "$data_dir"
    status_line "data folder removed" OK
    volumes=$(docker volume ls -q --filter "label=$LABEL")
    if [ -n "$volumes" ]; then
      for v in $volumes; do docker volume rm "$v" >/dev/null; done
      status_line "git server and CI data removed" OK
    fi
    for n in "$NETWORK" "$LEGACY_PREFIX"; do
      docker network rm "$n" >/dev/null 2>&1 && status_line "network $n removed" OK
    done
    images="$images
$(docker images --format '{{.Repository}}:{{.Tag}}' "$REGISTRY")"
    removed=0
    for i in $(printf '%s\n' "$images" | sort -u); do
      docker image rm "$i" >/dev/null 2>&1 && removed=$((removed + 1))
    done
    status_line "$removed image(s) removed" OK
  else
    box_line "the data stays in $data_dir (--purge removes it)"
  fi
  box_bottom
  exit 0
fi

# --- install ------------------------------------------------------------------

banner

[ -n "$port" ] || port=$(saved port)
[ -n "$port" ] || port=$DEFAULT_PORT
case "$port" in *[!0-9]*|"") die_usage "--port needs a number, not $port" ;; esac

box_top "SYSTEM CHECK"
command -v docker >/dev/null 2>&1 || fail "docker was not found" "Install Docker Desktop, OrbStack or Docker Engine first."
status_line "docker" OK
docker info >/dev/null 2>&1 || fail "the docker daemon does not answer" "Start Docker (Desktop, OrbStack) and run this again."
status_line "docker daemon" OK
command -v curl >/dev/null 2>&1 || fail "curl was not found"
if container_exists; then
  status_line "port $port (ours, will be replaced)" OK
else
  set +e
  curl -s --max-time 2 -o /dev/null "$(engine_url)/"
  code=$?
  set -e
  [ "$code" = 7 ] || fail "port $port is taken by something else" "Choose another one: --port 7471"
  status_line "port $port" OK
fi
box_bottom
say ""

if [ -z "$sync_target" ]; then
  previous=$(saved syncTarget)
  sync_target=${previous:-$DEFAULT_SYNC_TARGET}
  if [ "$interactive" = 1 ]; then
    box_top "SYNC TARGET"
    box_line "Send your releases on to another WarpEngine instance?"
    if [ "$sync_target" = none ]; then
      menu 0 "No: they stay on this machine" "Yes: type its address"
      [ "$choice" = 1 ] && sync_target="?"
    else
      menu 1 "No: they stay on this machine" "Yes: $sync_target" "Another one: type its address"
      case "$choice" in 0) sync_target=none ;; 2) sync_target="?" ;; esac
    fi
    if [ "$sync_target" = "?" ]; then
      box_top "SYNC TARGET"
      box_line "Its address, e.g. $EXAMPLE_SYNC_TARGET"
      box_bottom
      sync_target=$(ask)
      say ""
      [ -n "$sync_target" ] || sync_target=none
    fi
  fi
fi
case "$sync_target" in -|none) sync_target="none" ;; http://*|https://*) ;; *) die_usage "the sync target must be an http(s) address or none, not $sync_target" ;; esac

yes_no() {
  if [ "$interactive" = 1 ]; then
    if [ "$1" = on ]; then menu 0 "$2" "$3"; else menu 1 "$2" "$3"; fi
    if [ "$choice" = 0 ]; then echo on; else echo off; fi >"$answer_file"
  else
    echo "$1" >"$answer_file"
  fi
}

answer_file=$(mktemp)
default_admin=on
default_bypass=on
default_ci=on
if answered; then
  default_admin=$(on_off "$(saved admin)" on)
  default_bypass=$(on_off "$(saved adminBypass)" on)
  default_ci=$(on_off "$(saved ci)" on)
fi

if [ -z "$admin" ]; then
  [ "$interactive" = 1 ] && { box_top "ADMIN WEB UI"; box_line "A web admin at /admin: the catalog, the releases, the"; box_line "sync peers, the tool sign-ins, in your browser."; }
  yes_no "$default_admin" "Yes: the admin web UI at /admin" "No: headless, the editor and the API are enough"
  admin=$(cat "$answer_file")
fi
case "$admin" in on|true|1|yes) admin=on ;; off|false|0|no) admin=off ;; *) die_usage "--admin takes on or off" ;; esac

if [ "$admin" = off ]; then
  admin_bypass=off
elif [ -z "$admin_bypass" ]; then
  [ "$interactive" = 1 ] && { box_top "ADMIN SIGN-IN"; box_line "Only this machine reaches the engine (127.0.0.1)."; box_line "Skip the password there?"; }
  yes_no "$default_bypass" "Yes: /admin signs you in by itself" "No: sign in with the password in admin.json"
  admin_bypass=$(cat "$answer_file")
fi
case "$admin_bypass" in on|true|1|yes) admin_bypass=on ;; off|false|0|no) admin_bypass=off ;; *) die_usage "--admin-bypass takes on or off" ;; esac

previous_ci=$(saved ci)
if [ -z "$ci" ]; then
  [ "$interactive" = 1 ] && { box_top "LOCAL CI"; box_line "A git server (Gitea) and a CI (Woodpecker) beside the"; box_line "engine: your projects push there, it builds them and"; box_line "publishes here. Started and wired for you, no sign-in."; }
  yes_no "$default_ci" "Yes: the git server and the CI" "No: the engine only"
  ci=$(cat "$answer_file")
fi
rm -f "$answer_file"
case "$ci" in on|true|1|yes) ci=on ;; off|false|0|no) ci=off ;; *) die_usage "--ci takes on or off" ;; esac

if [ -z "$image" ]; then
  if [ -n "$version" ]; then image="$REGISTRY:$version"; else image="$REGISTRY:$INSTALLER_VERSION"; fi
fi

box_top "INSTALL"
mkdir -p "$data_dir"
chmod 700 "$data_dir" 2>/dev/null || true
write_config
status_line "data folder $(short "$(home_path "$data_dir")" 30)" OK

if docker image inspect "$image" >/dev/null 2>&1 && [ "${image##*:}" != "latest" ]; then
  status_line "image (already here)" OK
else
  docker pull -q "$image" >/dev/null 2>"$data_dir/.pull.log" &
  spinner_wait $! "pulling the engine" || fail "the image could not be pulled: $image" "$(tail -n 1 "$data_dir/.pull.log" | cut -c1-58)"
  rm -f "$data_dir/.pull.log"
  status_line "image pulled" OK
fi

if container_exists; then
  docker rm -f "$CONTAINER" >/dev/null
  status_line "old container replaced" OK
fi

admin_flag=0
[ "$admin" = on ] && admin_flag=1
bypass_flag=0
[ "$admin_bypass" = on ] && bypass_flag=1
docker network inspect "$NETWORK" >/dev/null 2>&1 \
  || docker network create --label "$LABEL" "$NETWORK" >/dev/null \
  || fail "the $NETWORK network could not be made"
status_line "network $NETWORK" OK

legacy=$(docker ps -aq --filter "label=$LABEL" --filter "name=^$LEGACY_PREFIX-")
if [ -n "$legacy" ]; then
  for c in $legacy; do docker rm -f "$c" >/dev/null; done
  for v in $(docker volume ls -q --filter "label=$LABEL" --filter "name=^$LEGACY_PREFIX-"); do docker volume rm "$v" >/dev/null 2>&1 || true; done
  docker network rm "$LEGACY_PREFIX" >/dev/null 2>&1 || true
  status_line "old $LEGACY_PREFIX-* git server and CI removed" OK
  legacy=1
fi

docker run -d --name "$CONTAINER" --restart unless-stopped \
  --label "$LABEL" --network "$NETWORK" --network-alias "$CONTAINER" -v "$SOCKET:$SOCKET" \
  -e PORT="$port" -e WARP_SYNC_TARGET="$sync_target" -e WARP_ADMIN="$admin_flag" -e WARP_ADMIN_BYPASS="$bypass_flag" \
  -p "127.0.0.1:$port:$port" -v "$data_dir:/data" "$image" >/dev/null \
  || fail "the container did not start"
status_line "container started" OK

(
  tries=0
  until curl -sf --max-time 2 "$(engine_url)/.well-known/warp-engine" >/dev/null 2>&1; do
    tries=$((tries + 1))
    [ "$tries" -gt 120 ] && exit 1
    sleep 1
  done
) &
spinner_wait $! "the engine wakes up" || fail "the engine did not answer in two minutes" "docker logs $CONTAINER tells why"
status_line "engine answers" OK
box_bottom
say ""

# --- local CI -------------------------------------------------------------------

ci_log=$(mktemp)
if [ "$ci" = on ]; then
  box_top "LOCAL CI"
  docker exec "$CONTAINER" bin/rails "warp_engine:local:enable[woodpecker]" >"$ci_log" 2>&1 &
  if spinner_wait $! "git server and CI (the first time pulls their images)"; then
    status_line "git server 127.0.0.1:$((port + 1))" OK
    status_line "CI" OK
    [ -n "$legacy" ] && box_line "projects on the old CI: Set up local CI again in VS Code"
  else
    status_line "git server and CI" FAIL
    tail -n 3 "$ci_log" | while IFS= read -r line; do box_line "$(printf '%.58s' "$line")"; done
    box_line "the engine runs; run this again with --ci on to retry"
    ci=failed
  fi
  box_bottom
  say ""
elif [ "$previous_ci" = true ]; then
  box_top "LOCAL CI"
  docker exec "$CONTAINER" bin/rails "warp_engine:local:disable[gitea]" >"$ci_log" 2>&1 &
  spinner_wait $! "stopping the git server and CI" && status_line "git server and CI stopped (data kept)" OK
  box_bottom
  say ""
fi
rm -f "$ci_log"

# --- builder images -------------------------------------------------------------

platform_images() {
  docker exec "$CONTAINER" ruby -rjson -rnet/http -e '
    body = Net::HTTP.get(URI("http://127.0.0.1:#{ENV.fetch("PORT")}/build/platforms"))
    JSON.parse(body).fetch("platforms").each do |p|
      image = p.dig("ci", "builder")
      puts "#{p["name"]} #{image}" if image
    end' 2>/dev/null
}

if [ -z "$builders" ]; then
  builders=none
  if [ "$interactive" = 1 ]; then
    names=$(platform_images | cut -d' ' -f1 | tr '\n' ' ')
    box_top "BUILDER IMAGES"
    box_line "Pull the builder images now? They are large (Godot,"
    box_line "Bevy: several GB), and the pipelines pull them anyway."
    menu 0 "No: the pipelines pull them when they need them" "All of them" "Some: type their names"
    case "$choice" in
      1) builders=all ;;
      2)
        box_top "BUILDER IMAGES"
        prefix="names:"
        line=""
        for name in $names; do
          if [ $((${#line} + ${#name} + 1)) -gt 50 ]; then
            box_line "$prefix $line"
            prefix="      "; line=""
          fi
          if [ -n "$line" ]; then line="$line $name"; else line=$name; fi
        done
        [ -n "$line" ] && box_line "$prefix $line"
        box_bottom
        builders=$(ask)
        say ""
        [ -n "$builders" ] || builders=none ;;
    esac
  fi
fi

if [ "$builders" != "none" ]; then
  box_top "BUILDER IMAGES"
  platform_images | while read -r name ref; do
    case " $builders " in *" all "*|*" $name "*) ;; *) continue ;; esac
    docker pull -q "$ref" >/dev/null 2>&1 &
    if spinner_wait $! "pulling $name"; then status_line "$name" OK; else status_line "$name" FAIL; fi
  done
  box_bottom
  say ""
fi

# --- the end ------------------------------------------------------------------

info=$(curl -s "$(engine_url)/.well-known/warp-engine")
engine_version=$(printf '%s' "$info" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')

box_top "READY"
box_line "engine ........... $(engine_url)" "engine ........... ${BWHT}$(engine_url)${R}"
box_line "version .......... $engine_version"
if [ "$sync_target" = none ]; then
  box_line "sync target ...... none"
else
  box_line "sync target ...... $sync_target"
fi
box_line "token ............ $(home_path "$data_dir")/local-token"
if [ "$admin" = on ] && [ "$admin_bypass" = on ]; then
  box_line "admin ............ $(engine_url)/admin" "admin ............ ${BWHT}$(engine_url)/admin${R}"
  box_line "                   signs you in by itself"
elif [ "$admin" = on ] && [ -f "$data_dir/admin.json" ]; then
  email=$(sed -n 's/.*"email": *"\([^"]*\)".*/\1/p' "$data_dir/admin.json")
  password=$(sed -n 's/.*"password": *"\([^"]*\)".*/\1/p' "$data_dir/admin.json")
  box_line "admin ............ $(engine_url)/admin" "admin ............ ${BWHT}$(engine_url)/admin${R}"
  box_line "                   $email / $password"
else
  box_line "admin ............ off (--admin on turns it on)"
fi
case "$ci" in
  on) box_line "local CI ......... git server http://localhost:$((port + 1))" "local CI ......... git server ${BWHT}http://localhost:$((port + 1))${R}"
      box_line "                   + Woodpecker, VS Code offers it" ;;
  failed) box_line "local CI ......... did not start (--ci on retries)" ;;
  *) box_line "local CI ......... off (--ci on turns it on)" ;;
esac
box_line ""
box_line "Open VS Code: the WarpEngine Toolbox finds this engine" "${BGRN}Open VS Code:${R} the WarpEngine Toolbox finds this engine"
box_line "by itself. Run this again any time to change the answers."
box_bottom
say ""
