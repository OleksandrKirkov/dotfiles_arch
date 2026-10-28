# shellcheck shell=bash
# bus.sh: talk to dotctld, the dotctl bus, over its Unix socket with curl.
#
# Socket: $DOTCTL_BUS, default $XDG_RUNTIME_DIR/dotctl/bus.sock.
# API and topics: docs/bus.md.
#
# Return codes of bus_call: 0 ok, 1 rejected by the daemon, 3 daemon not
# running, 4 nothing published on that topic.

BUS_TOPIC_PATTERN='^[a-z][a-z0-9.-]{0,63}$'

bus_socket() {
    if [[ -n "${DOTCTL_BUS:-}" ]]; then
        printf '%s\n' "$DOTCTL_BUS"
    elif [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
        printf '%s/dotctl/bus.sock\n' "$XDG_RUNTIME_DIR"
    else
        die "XDG_RUNTIME_DIR is not set; set DOTCTL_BUS to the dotctld socket"
    fi
}

bus_check_topic() {
    [[ "$1" =~ $BUS_TOPIC_PATTERN ]] || die "invalid topic '$1': must match $BUS_TOPIC_PATTERN"
}

# bus_call <method> <path> [json data]: print the response body.
bus_call() {
    local method="$1" path="$2" sock out code body msg
    sock="$(bus_socket)"
    if [[ ! -S "$sock" ]]; then
        warn "dotctld is not running (no socket at $sock)"
        return 3
    fi
    local -a args=(-sS --unix-socket "$sock" -X "$method" -w '\n%{http_code}')
    if (($# > 2)); then
        args+=(-H 'Content-Type: application/json' --data-binary @-)
    fi
    if ! out="$(if (($# > 2)); then printf '%s' "$3"; fi | curl "${args[@]}" "http://dotctl$path")"; then
        warn "dotctld did not answer on $sock"
        return 3
    fi
    code="${out##*$'\n'}"
    body="${out%$'\n'*}"
    if [[ "$code" == 2?? ]]; then
        printf '%s\n' "$body"
        return 0
    fi
    msg="$(jq -r '.error // empty' <<<"$body" 2>/dev/null || true)"
    warn "dotctld: ${msg:-HTTP $code}"
    [[ "$code" != 404 ]] || return 4
    return 1
}

# bus_watch <data-only 0|1> <topic...>: stream messages until the daemon or
# the reader goes away.
bus_watch() {
    local data_only="$1" sock query="" topic
    shift
    sock="$(bus_socket)"
    if [[ ! -S "$sock" ]]; then
        warn "dotctld is not running (no socket at $sock)"
        return 3
    fi
    for topic in "$@"; do
        query+="${query:+&}topic=$topic"
    done
    if ((data_only)); then
        curl -sSN --fail-with-body --unix-socket "$sock" "http://dotctl/v1/watch?$query" | jq --unbuffered -c '.data'
    else
        curl -sSN --fail-with-body --unix-socket "$sock" "http://dotctl/v1/watch?$query"
    fi
}
