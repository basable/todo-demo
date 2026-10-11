#!/usr/bin/env bash
# The end-to-end checks. Runs inside the test client container (see
# test/Dockerfile), on the same Docker network as the server, which answers
# at http://app:8080. test/e2e.sh runs one phase at a time:
#
#   wait        poll /health until the server is up
#   api         every case the old handlers_test.go covered, and the edges
#   timestamps  createdAt formatting, for rows e2e.sh wrote straight to SQL
#   recovery    the first request after PostgreSQL restarted
#   slow        clients that stall or trickle cannot hold the server
#
# Every response is checked for its status, its exact body, the two security
# headers, "Connection: close", and a Content-Length that matches the body.
set -uo pipefail
# A write to a connection the server has closed must fail, not kill bash.
trap '' PIPE

phase=${1:?usage: cases.sh wait|api|timestamps|recovery|slow}
host=app
port=8080
base="http://$host:$port"

passed=0
failed=0
pass() { passed=$((passed + 1)); printf 'PASS  %s\n' "$1"; }
fail() {
    failed=$((failed + 1))
    printf 'FAIL  %s\n' "$1"
    shift
    for line in "$@"; do printf '        %s\n' "$line"; done
}

bs=$(printf '\134')   # a single backslash
q='"'
nl=$'\n'
# esc 2028 -> the six characters of the JSON escape for U+2028
esc() { printf '%su%s' "$bs" "$1"; }

# call METHOD PATH [curl options...]: sets status, body (exact bytes, final
# newline kept), and leaves the response headers in /tmp/headers.
call() {
    method=$1 path=$2
    shift 2
    local mode=(-X "$method")
    [ "$method" = HEAD ] && mode=(-I)
    status=$(curl -sS --path-as-is --max-time 30 "${mode[@]}" \
        -D /tmp/headers -o /tmp/body -w '%{http_code}' "$@" "$base$path") \
        || status=000
    body=$(cat /tmp/body; printf x)
    body=${body%x}
}

header() {
    grep -i "^$1:" /tmp/headers | head -1 | cut -d' ' -f2- | tr -d '\r'
}

# The body with each well-formed RFC 3339 createdAt replaced by "T".
normalised_body() {
    printf '%s' "$body" | sed -E \
        's/"createdAt":"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]*[1-9])?Z"/"createdAt":"T"/g'
}

# expect NAME STATUS [EXACT-BODY]: check the last response.
expect() {
    local name=$1 want=$2 problems=()
    [ "$status" = "$want" ] || problems+=("status $status, want $want")
    [ "$(header Content-Security-Policy)" = "frame-ancestors 'self' https://basable.com" ] \
        || problems+=("no Content-Security-Policy header")
    [ "$(header X-Content-Type-Options)" = nosniff ] \
        || problems+=("no X-Content-Type-Options header")
    [ "$(header Connection)" = close ] || problems+=("no Connection: close")
    if [ "$want" = 204 ]; then
        [ -z "$(header Content-Length)" ] || problems+=("a 204 with a Content-Length")
        [ -z "$body" ] || problems+=("a 204 with a body")
    elif [ "$method" != HEAD ]; then
        local length
        length=$(wc -c < /tmp/body | tr -d ' ')
        [ "$(header Content-Length)" = "$length" ] \
            || problems+=("Content-Length $(header Content-Length), body has $length bytes")
    fi
    if [ $# -ge 3 ]; then
        local got
        got=$(normalised_body; printf x)
        got=${got%x}
        [ "$got" = "$3" ] || problems+=("body:   $(printf %q "$got")" "wanted: $(printf %q "$3")")
    fi
    if [ ${#problems[@]} -eq 0 ]; then pass "$name"; else fail "$name" "${problems[@]}"; fi
}

expect_header() {
    local name=$1 header_name=$2 want=$3 got
    got=$(header "$header_name")
    if [ "$got" = "$want" ]; then pass "$name"; else fail "$name" "$header_name: $(printf %q "$got"), want $(printf %q "$want")"; fi
}

# The id in a {"id":N,...} body.
id_of() { printf '%s' "$body" | sed -E 's/^\{"id":([0-9]+),.*/\1/'; }

todo() { # todo ID TITLE DONE -> the JSON the server writes for it
    printf '{"id":%s,"title":"%s","done":%s,"createdAt":"T"}' "$1" "$2" "$3"
}
err() { printf '{"error":"%s"}' "$1"; }

# raw BYTES: send exactly these bytes on a fresh connection, read the reply
# until the server closes the connection.
raw() {
    exec 3<>"/dev/tcp/$host/$port"
    printf '%b' "$1" >&3
    read_reply
}
read_reply() {
    timeout 15 cat <&3 > /tmp/raw
    exec 3<&- 3>&-
    reply=$(tr -d '\r' < /tmp/raw)
}
expect_raw() { # NAME STATUS-LINE [SUBSTRING]
    local problems=() head_bytes body_bytes length
    # The head runs through the first empty line; the rest is the body,
    # and Content-Length must count it exactly.
    head_bytes=$(sed -n '1,/^\r$/p' /tmp/raw | wc -c | tr -d ' ')
    body_bytes=$(( $(wc -c < /tmp/raw | tr -d ' ') - head_bytes ))
    length=$(printf '%s' "$reply" | sed -n 's/^Content-Length: //p' | head -1)
    [ "$length" = "$body_bytes" ] || problems+=("Content-Length ${length:-missing}, body has $body_bytes bytes")
    case $reply in *"Connection: close"*) ;; *) problems+=("no Connection: close") ;; esac
    [ "$(printf '%s' "$reply" | head -1)" = "$2" ] \
        || problems+=("status line $(printf '%s' "$reply" | head -1 | od -c | head -2 | tr -s ' ')")
    case $reply in *"Content-Security-Policy: frame-ancestors 'self' https://basable.com"*) ;; *) problems+=("no Content-Security-Policy") ;; esac
    case $reply in *"X-Content-Type-Options: nosniff"*) ;; *) problems+=("no X-Content-Type-Options") ;; esac
    if [ $# -ge 3 ]; then case $reply in *"$3"*) ;; *) problems+=("reply lacks $(printf %q "$3")") ;; esac; fi
    if [ ${#problems[@]} -eq 0 ]; then pass "$1"; else fail "$1" "${problems[@]}"; fi
}

millis_since() { echo $(( ($(date +%s%N) - $1) / 1000000 )); }   # in ms

phase_wait() {
    for _ in $(seq 120); do
        if [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$base/health")" = 200 ]; then
            pass "server answers /health"
            return
        fi
        sleep 1
    done
    fail "server answers /health" "no 200 within 120 seconds"
}

phase_api() {
    echo "-- the cases handlers_test.go covered"
    call POST /api/todos -d '{"title":"   "}'
    expect "a blank title is refused" 400 "$(err 'title must be 1-200 characters')$nl"
    call POST /api/todos -d '{"title":"buy milk"}'
    local milk
    milk=$(id_of)
    expect "a todo is created" 201 "$(todo "$milk" 'buy milk' false)$nl"
    expect_header "a created todo is JSON" Content-Type application/json
    call PATCH "/api/todos/$milk" -d '{"done":true}'
    expect "a todo is ticked off" 200 "$(todo "$milk" 'buy milk' true)$nl"
    call GET /api/todos
    expect "the list has the ticked-off todo" 200 "[$(todo "$milk" 'buy milk' true)]$nl"
    call DELETE "/api/todos/$milk"
    expect "a todo is deleted" 204
    expect_header "a 204 has no Content-Type" Content-Type ''
    call DELETE "/api/todos/$milk"
    expect "deleting it again is 404" 404 "$(err 'todo not found')$nl"
    call GET /
    expect "/ is index.html" 200
    if cmp -s /tmp/body /expected/web/index.html; then pass "/ is byte for byte web/index.html"; else fail "/ is byte for byte web/index.html"; fi
    expect_header "/ is HTML" Content-Type 'text/html; charset=utf-8'

    echo "-- health and routing"
    call GET /health
    expect "GET /health" 200 OK
    expect_header "/health is plain text" Content-Type text/plain
    call HEAD /health
    expect "HEAD /health" 200
    expect_header "HEAD /health has GET's length" Content-Length 2
    exec 3<>"/dev/tcp/$host/$port"
    printf 'HEAD /health HTTP/1.1\r\nHost: app\r\n\r\n' >&3
    read_reply
    if [ "$(sed -n '1,/^\r$/p' /tmp/raw | wc -c)" = "$(wc -c < /tmp/raw)" ]; then
        pass "HEAD /health has no body"
    else
        fail "HEAD /health has no body" "$reply"
    fi
    call GET '/api/todos?page=2'
    expect "a query string is ignored" 200 "[]$nl"
    call POST /health
    expect "POST /health is 405" 405 "Method Not Allowed$nl"
    expect_header "405 on /health lists GET, HEAD" Allow 'GET, HEAD'
    call PUT /api/todos
    expect "PUT /api/todos is 405" 405 "Method Not Allowed$nl"
    expect_header "405 on /api/todos lists its methods" Allow 'GET, HEAD, POST'
    call POST /api/todos/1
    expect "POST /api/todos/1 is 405" 405 "Method Not Allowed$nl"
    expect_header "405 on /api/todos/{id} lists its methods" Allow 'DELETE, GET, HEAD, PATCH'
    call PATCH /api/todos/ -d '{"done":true}'
    expect "an empty id is not a route" 405 "Method Not Allowed$nl"
    call GET /api/todos/1
    expect "GET /api/todos/1 falls through to the files: 404" 404 "404 page not found$nl"
    call get /health
    expect "methods are case sensitive" 405 "Method Not Allowed$nl"
    call GET '/api//todos'
    expect "an untidy path is redirected" 301 "<a href=\"/api/todos\">Moved Permanently</a>.$nl$nl"
    expect_header "to the tidy path" Location /api/todos
    call GET '/api/%74odos'
    expect "an escaped path segment still routes" 200 "[]$nl"

    echo "-- web files"
    call GET /app.js
    expect "/app.js" 200
    expect_header "/app.js is JavaScript" Content-Type 'text/javascript; charset=utf-8'
    if cmp -s /tmp/body /expected/web/app.js; then pass "/app.js is byte for byte web/app.js"; else fail "/app.js is byte for byte web/app.js"; fi
    call GET /style.css
    expect "/style.css" 200
    expect_header "/style.css is CSS" Content-Type 'text/css; charset=utf-8'
    if cmp -s /tmp/body /expected/web/style.css; then pass "/style.css is byte for byte web/style.css"; else fail "/style.css is byte for byte web/style.css"; fi
    call HEAD /
    expect "HEAD /" 200
    expect_header "HEAD / has index.html's length" Content-Length "$(wc -c < /expected/web/index.html | tr -d ' ')"
    call GET /index.html
    expect "/index.html redirects to ./" 301 ''
    expect_header "with Location ./" Location ./
    call GET /app.js/
    expect "/app.js/ redirects to the file" 301 ''
    expect_header "with Location ../app.js" Location ../app.js
    call GET /missing.txt
    expect "a missing file is 404" 404 "404 page not found$nl"
    call POST /app.js
    expect "POST to a file is 405" 405 "Method Not Allowed$nl"
    for path in /web/index.html /todo-server /cobol/TODOSRV.cbl /etc/passwd \
                '/%2e%2e/%2e%2e/etc/passwd' '/..%2f..%2fetc/passwd' '/.%2e/app.js/../../etc/passwd'; do
        call GET "$path"
        case $status in
            404) expect "no file outside web/: $path" 404 "404 page not found$nl" ;;
            301) expect "no file outside web/: $path" 301 ;;
            *)   fail "no file outside web/: $path" "status $status" ;;
        esac
    done
    call GET '/../../etc/passwd'
    expect "/../../etc/passwd is tidied, not followed" 301
    expect_header "to /etc/passwd, itself a 404" Location /etc/passwd

    echo "-- reading request bodies"
    call POST /api/todos --data-binary ''
    expect "an empty body" 400 "$(err 'invalid JSON body')$nl"
    call POST /api/todos --data-binary 'null'
    expect "null sets nothing" 400 "$(err 'title must be 1-200 characters')$nl"
    call POST /api/todos --data-binary '[]'
    expect "an array is the wrong type" 400 "$(err 'invalid JSON body')$nl"
    call POST /api/todos --data-binary '{"title":123}'
    expect "a number title is the wrong type" 400 "$(err 'invalid JSON body')$nl"
    call POST /api/todos --data-binary '{"title":"a",}'
    expect "a trailing comma" 400 "$(err 'invalid JSON body')$nl"
    call POST /api/todos --data-binary '{"title":"x"} and then some'
    expect "anything after the JSON value is ignored" 201 "$(todo "$(id_of)" x false)$nl"
    call POST /api/todos --data-binary '{"TITLE":"upper"}'
    expect "field names ignore case" 201 "$(todo "$(id_of)" upper false)$nl"
    call POST /api/todos --data-binary '{"title":"a","title":null}'
    expect "a later null title changes nothing" 201 "$(todo "$(id_of)" a false)$nl"
    call POST /api/todos --data-binary "{\"t$(esc 0069)tle\":\"escaped key\",\"other\":{\"title\":[1,2.5e3,true,null]}}"
    expect "escaped keys match, unknown fields are skipped" 201 "$(todo "$(id_of)" 'escaped key' false)$nl"
    call POST /api/todos --data-binary "{\"x\":$(printf '[%.0s' $(seq 9999))$(printf ']%.0s' $(seq 9999)),\"title\":\"deep\"}"
    expect "10000 levels of nesting are fine" 201 "$(todo "$(id_of)" deep false)$nl"
    call POST /api/todos --data-binary "{\"x\":$(printf '[%.0s' $(seq 10000))$(printf ']%.0s' $(seq 10000)),\"title\":\"deeper\"}"
    expect "10001 levels are not" 400 "$(err 'invalid JSON body')$nl"
    call PATCH /api/todos/1 --data-binary '{"done":null}'
    expect "done: null" 400 "$(err 'done is required')$nl"
    call PATCH /api/todos/1 --data-binary '{}'
    expect "done missing" 400 "$(err 'done is required')$nl"
    call PATCH /api/todos/1 --data-binary '{"done":"true"}'
    expect "done as a string" 400 "$(err 'invalid JSON body')$nl"
    call PATCH /api/todos/1 --data-binary '{"done":true,"done":null}'
    expect "a later done: null wins" 400 "$(err 'done is required')$nl"
    call PATCH /api/todos/abc --data-binary 'not json'
    expect "the id is checked before the body" 400 "$(err 'invalid id')$nl"

    echo "-- ids"
    call POST /api/todos -d '{"title":"id target"}'
    local target
    target=$(id_of)
    call PATCH "/api/todos/+$target" -d '{"done":true}'
    expect "a + sign is allowed" 200 "$(todo "$target" 'id target' true)$nl"
    call PATCH "/api/todos/000$target" -d '{"done":false}'
    expect "leading zeros are allowed" 200 "$(todo "$target" 'id target' false)$nl"
    for id in 0 -1 -0 + abc 1.5 '1%2F2' 9223372036854775808 99999999999999999999; do
        call PATCH "/api/todos/$id" -d '{"done":true}'
        expect "id $id is invalid" 400 "$(err 'invalid id')$nl"
        call DELETE "/api/todos/$id"
        expect "id $id is invalid for DELETE too" 400 "$(err 'invalid id')$nl"
    done
    call PATCH /api/todos/9223372036854775807 -d '{"done":true}'
    expect "the largest 64-bit id is valid, just absent" 404 "$(err 'todo not found')$nl"

    echo "-- titles"
    local e200 e201 smile200 smile201
    e200=$(printf '\303\251%.0s' $(seq 200))
    e201=$(printf '\303\251%.0s' $(seq 201))
    smile200=$(printf '\360\237\230\200%.0s' $(seq 200))
    smile201=$(printf '\360\237\230\200%.0s' $(seq 201))
    call POST /api/todos --data-binary "{\"title\":\"$e200\"}"
    expect "200 two-byte characters are accepted, and kept to 64 bytes" 201 \
        "$(todo "$(id_of)" "$(printf '\303\251%.0s' $(seq 32))" false)$nl"
    call POST /api/todos --data-binary "{\"title\":\"$e201\"}"
    expect "201 are refused" 400 "$(err 'title must be 1-200 characters')$nl"
    call POST /api/todos --data-binary "{\"title\":\"$smile200\"}"
    expect "200 four-byte characters are accepted, and kept to 64 bytes" 201 \
        "$(todo "$(id_of)" "$(printf '\360\237\230\200%.0s' $(seq 16))" false)$nl"
    call POST /api/todos --data-binary "{\"title\":\"$smile201\"}"
    expect "201 are refused" 400 "$(err 'title must be 1-200 characters')$nl"

    echo "-- titles are kept to 64 bytes"
    local a62 a63
    a62=$(printf 'a%.0s' $(seq 62))
    a63=$(printf 'a%.0s' $(seq 63))
    call POST /api/todos --data-binary "{\"title\":\"$(printf 'x%.0s' $(seq 100))\"}"
    expect "a 100-byte title is cut to 64" 201 "$(todo "$(id_of)" "$(printf 'x%.0s' $(seq 64))" false)$nl"
    call POST /api/todos --data-binary "{\"title\":\"${a62}$(printf '\303\251')\"}"
    expect "a title of exactly 64 bytes is kept whole" 201 "$(todo "$(id_of)" "${a62}$(printf '\303\251')" false)$nl"
    call POST /api/todos --data-binary "{\"title\":\"${a63}$(printf '\303\251')b\"}"
    expect "the cut never splits a character" 201 "$(todo "$(id_of)" "$a63" false)$nl"
    call POST /api/todos --data-binary "{\"title\":\"${a63} bbb\"}"
    expect "a space the cut leaves at the end is dropped" 201 "$(todo "$(id_of)" "$a63" false)$nl"
    call POST /api/todos --data-binary "{\"title\":\"$(esc 00a0)$(esc 3000) $(esc 0009) hi $(esc 2028)$(esc 0085)\"}"
    expect "Unicode whitespace is trimmed" 201 "$(todo "$(id_of)" hi false)$nl"
    call POST /api/todos --data-binary "{\"title\":\"$(esc 3000)$(esc 00a0)\"}"
    expect "a title of only Unicode whitespace is blank" 400 "$(err 'title must be 1-200 characters')$nl"
    call POST /api/todos --data-binary "{\"title\":\"$(esc 0000)\"}"
    expect "a zero byte is a 500, as PostgreSQL refused it before" 500 "$(err 'internal error')$nl"

    echo "-- writing JSON"
    local sent wanted
    sent="<b>&${bs}${q}q${bs}${q} ${bs}${bs} ${bs}/ x$(esc 0001)y$(esc 001f)$(esc 007f)${bs}t${bs}b${bs}f $(printf '\303\251\360\237\230\200')$(esc 2028)$(esc 2029)z"
    wanted="$(esc 003c)b$(esc 003e)$(esc 0026)${bs}${q}q${bs}${q} ${bs}${bs} / x$(esc 0001)y$(esc 001f)$(printf '\177')${bs}t${bs}b${bs}f $(printf '\303\251\360\237\230\200')$(esc 2028)$(esc 2029)z"
    call POST /api/todos --data-binary "{\"title\":\"$sent\"}"
    expect "quotes, backslashes, control characters, HTML and U+2028 are escaped" 201 "$(todo "$(id_of)" "$wanted" false)$nl"
    call POST /api/todos --data-binary "{\"title\":\"a$(printf '\377\342\202')b $(esc d800)c $(esc d83d)$(esc de00)\"}"
    expect "broken UTF-8 and lone surrogates become U+FFFD" 201 \
        "$(todo "$(id_of)" "a$(printf '\357\277\275\357\277\275\357\277\275')b $(printf '\357\277\275')c $(printf '\360\237\230\200')" false)$nl"

    echo "-- the 1 MiB limit"
    { printf '{"title":"padded"}'; head -c 2097152 /dev/zero | tr '\0' ' '; } > /tmp/padded.json
    call POST /api/todos --data-binary @/tmp/padded.json
    expect "a value that ends early may be followed by 2 MiB" 201 "$(todo "$(id_of)" padded false)$nl"
    { printf '{"title":"'; head -c 1048600 /dev/zero | tr '\0' a; printf '"}'; } > /tmp/long.json
    call POST /api/todos --data-binary @/tmp/long.json
    expect "a value longer than 1 MiB is cut off" 400 "$(err 'invalid JSON body')$nl"
    { head -c 1048570 /dev/zero | tr '\0' ' '; printf '{"title":"late"}'; } > /tmp/late.json
    call POST /api/todos --data-binary @/tmp/late.json
    expect "a value that ends past 1 MiB is cut off" 400 "$(err 'invalid JSON body')$nl"

    echo "-- HTTP on the wire"
    local start
    start=$(date +%s%N)
    call POST /api/todos -H 'Expect: 100-continue' --data-binary '{"title":"expect 100-continue"}'
    expect "Expect: 100-continue" 201 "$(todo "$(id_of)" 'expect 100-continue' false)$nl"
    if [ "$(millis_since "$start")" -lt 900 ]; then pass "the server says 100 Continue (curl did not wait)"; else fail "the server says 100 Continue" "took $(millis_since "$start") ms"; fi

    exec 3<>"/dev/tcp/$host/$port"
    printf 'POST /api/to' >&3; sleep 0.3
    printf 'dos HTTP/1.1\r\nHost: app\r\nContent-' >&3; sleep 0.3
    printf 'Length: 21\r\n\r\n{"title":' >&3; sleep 0.3
    printf '"in pieces"}' >&3
    read_reply
    expect_raw "a request that arrives in pieces" 'HTTP/1.1 201 Created' '"title":"in pieces"'

    raw 'GET /health HTTP/1.0\r\n\r\n'
    expect_raw "HTTP/1.0 gets an HTTP/1.0 answer" 'HTTP/1.0 200 OK' "${nl}${nl}OK"
    raw 'GET /health HTTP/1.1\nHost: app\n\n'
    expect_raw "bare line feeds are accepted" 'HTTP/1.1 200 OK'
    raw 'GET /health HTTP/1.1\r\n\r\n'
    expect_raw "HTTP/1.1 without Host" 'HTTP/1.1 400 Bad Request: missing required Host header' '400 Bad Request: missing required Host header'
    raw 'HELLO\r\n\r\n'
    expect_raw "a garbage request line" 'HTTP/1.1 400 Bad Request' '400 Bad Request'
    raw 'GET /health HTTP/2.0\r\nHost: app\r\n\r\n'
    expect_raw "HTTP/2.0 is refused" 'HTTP/1.1 505 HTTP Version Not Supported: unsupported protocol version'
    raw 'GET /health HTTP/1.1\r\nHost: app\r\nNo colon here\r\n\r\n'
    expect_raw "a header without a colon" 'HTTP/1.1 400 Bad Request'
    raw 'GET /health HTTP/1.1\r\nHost: app\r\nBad Name: x\r\n\r\n'
    expect_raw "a header name with a space" 'HTTP/1.1 400 Bad Request: invalid header name'
    raw 'POST /api/todos HTTP/1.1\r\nHost: app\r\nContent-Length: -1\r\n\r\n'
    expect_raw "a negative Content-Length" 'HTTP/1.1 400 Bad Request'
    raw 'POST /api/todos HTTP/1.1\r\nHost: app\r\nContent-Length: 2\r\nContent-Length: 3\r\n\r\n{}'
    expect_raw "two different Content-Lengths" 'HTTP/1.1 400 Bad Request'
    raw 'POST /api/todos HTTP/1.1\r\nHost: app\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n'
    expect_raw "chunked request bodies are not supported" 'HTTP/1.1 501 Not Implemented' 'Unsupported transfer encoding'
    raw 'GET /a%zz HTTP/1.1\r\nHost: app\r\n\r\n'
    expect_raw "a broken %-escape" 'HTTP/1.1 400 Bad Request'
    raw 'GET /health HTTP/1.1\r\nHost: app\r\nExpect: something-else\r\n\r\n'
    expect_raw "an unknown expectation" 'HTTP/1.1 417 Expectation Failed'
    raw 'OPTIONS * HTTP/1.1\r\nHost: app\r\n\r\n'
    expect_raw "OPTIONS *" 'HTTP/1.1 200 OK' 'Content-Length: 0'
    { printf 'GET /health HTTP/1.1\r\nHost: app\r\nX-Big: '; head -c 1100000 /dev/zero | tr '\0' a; printf '\r\n\r\n'; } > /tmp/big-head
    exec 3<>"/dev/tcp/$host/$port"; cat /tmp/big-head >&3 2>/dev/null
    read_reply
    expect_raw "headers over 1 MiB" 'HTTP/1.1 431 Request Header Fields Too Large'
    call GET /health
    expect "the server is still up after all of that" 200 OK
}

phase_timestamps() {
    call GET /api/todos
    local want
    want="[{\"id\":101,\"title\":\"whole second\",\"done\":false,\"createdAt\":\"2026-01-02T03:04:05Z\"}"
    want+=",{\"id\":104,\"title\":\"tenth\",\"done\":true,\"createdAt\":\"2026-01-02T03:04:05.1Z\"}"
    want+=",{\"id\":102,\"title\":\"hundredths\",\"done\":false,\"createdAt\":\"2026-01-02T03:04:05.12Z\"}"
    want+=",{\"id\":103,\"title\":\"microseconds\",\"done\":false,\"createdAt\":\"2026-01-02T03:04:05.123456Z\"}"
    want+=",{\"id\":105,\"title\":\"from another zone\",\"done\":false,\"createdAt\":\"2026-01-02T03:04:06.5Z\"}"
    want+=",{\"id\":106,\"title\":\"$(printf 'L%.0s' $(seq 64))\",\"done\":false,\"createdAt\":\"2026-01-02T03:04:07Z\"}]"
    if [ "$body" = "$want$nl" ]; then
        pass "createdAt is RFC 3339 in UTC, trailing zeros dropped, oldest first"
        pass "a longer title stored before the limit is sent cut to 64 bytes"
    else
        fail "createdAt is RFC 3339 in UTC, oldest first; old long titles cut to 64 bytes" "body:   $body" "wanted: $want"
    fi
}

phase_recovery() {
    call POST /api/todos -d '{"title":"after the database restarted"}'
    expect "the first request after a PostgreSQL restart succeeds" 201 \
        "$(todo "$(id_of)" 'after the database restarted' false)$nl"
}

phase_slow() {
    local start elapsed
    # A client that sends half a request line and then nothing.
    start=$(date +%s%N)
    (
        exec 3<>"/dev/tcp/$host/$port"
        printf 'GET /hea' >&3
        cat <&3 > /dev/null
        echo $(( ($(date +%s%N) - start) / 1000000 )) > /tmp/stalled-ms
    ) &
    sleep 1
    call GET /health
    expect "a request queued behind a stalled client is answered" 200 OK
    elapsed=$(millis_since "$start")
    wait
    local stalled
    stalled=$(cat /tmp/stalled-ms)
    if [ "$stalled" -ge 9500 ] && [ "$stalled" -le 12000 ]; then
        pass "the stalled client is cut off after 10 seconds (${stalled} ms)"
    else
        fail "the stalled client is cut off after 10 seconds" "after ${stalled} ms"
    fi
    if [ "$elapsed" -le 12500 ]; then pass "and the queued request waited only that long (${elapsed} ms)"; else fail "the queued request waited too long" "${elapsed} ms"; fi

    # A client that sends one header byte a second, forever.
    start=$(date +%s%N)
    exec 4<>"/dev/tcp/$host/$port"
    printf 'GET /health HTTP/1.1\r\n' >&4
    ( cat <&4 > /dev/null; echo $(( ($(date +%s%N) - start) / 1000000 )) > /tmp/trickle-ms ) &
    for _ in $(seq 25); do printf 'X' >&4 2>/dev/null || break; sleep 1; done
    wait
    exec 4<&- 4>&-
    local trickled
    trickled=$(cat /tmp/trickle-ms)
    if [ "$trickled" -ge 9500 ] && [ "$trickled" -le 12000 ]; then
        pass "a client sending a byte a second is still cut off at 10 seconds (${trickled} ms)"
    else
        fail "a client sending a byte a second is cut off at 10 seconds" "after ${trickled} ms"
    fi

    # Headers that promise a body that never comes.
    start=$(date +%s%N)
    raw 'POST /api/todos HTTP/1.1\r\nHost: app\r\nContent-Length: 100\r\n\r\n{"title":"'
    expect_raw "a body that stops coming is answered at the deadline" 'HTTP/1.1 400 Bad Request' '{"error":"invalid JSON body"}'
    elapsed=$(millis_since "$start")
    if [ "$elapsed" -ge 9500 ] && [ "$elapsed" -le 12000 ]; then pass "after 10 seconds (${elapsed} ms)"; else fail "after 10 seconds" "${elapsed} ms"; fi
    call GET /health
    expect "the server is still up" 200 OK
}

case $phase in
    wait)       phase_wait ;;
    api)        phase_api ;;
    timestamps) phase_timestamps ;;
    recovery)   phase_recovery ;;
    slow)       phase_slow ;;
    *)          echo "unknown phase $phase" >&2; exit 2 ;;
esac
printf '%s: %d passed, %d failed\n' "$phase" "$passed" "$failed"
[ "$failed" -eq 0 ]
