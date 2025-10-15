#!/bin/bash

set -euo pipefail                      # 즉시 실패/미정의 변수 에러/파이프라인 실패 전파
DEBUG_FLAG=true

# -------------------------
# Globals / Defaults
# -------------------------
PROVIDED_PROCESS=""                    # 사용자 지정 프로세스명(옵션으로 입력)
USER_ARG=""                            # mysql -u 에 넣을 사용자
ASK_PASS=false                         # 비밀번호 프롬프트/지정 여부
PASSWORD_INPUT=""                      # -p PASSWORD / -pPASSWORD / --password= / --ask-pass= 값
RUN_TEST=false                         # --test 여부

HOST_ARG=""                            # --host / -H
PORT_ARG=""                            # --port / -P
SOCKET_ARG=""                          # --socket / -S

DB_CONFIG=""                           # 데몬의 --defaults-file 경로
TEMP_CNF=""                            # 임시 인증 옵션파일 경로
MYSQL=""                             # --mysql 또는 -B 로 받은 경로
MYSQL_BIN=""                           # mysql 바이너리 절대경로

CURRENT_MONTH="$(date +%Y-%m)"
LAST_MONTH="$(date -d 'last month' +%Y-%m)"
TWO_MONTHS_AGO="$(date -d '2 months ago' +%Y-%m)"

# -------------------------
# Helpers: 공용 출력/유틸
# -------------------------
usage() {                              # 사용법 출력 함수
    cat <<'EOF'
Usage:
  script.sh [--name=PROCESS_NAME|--process=PROCESS_NAME|-n PROCESS_NAME]
            [--user=USER|-u USER]
            [--password=PASS | -p[PASS] | --ask-pass[=PASS]]
            [--host=HOST | -H HOST]
            [--port=PORT | -P PORT]
            [--socket=PATH | -S PATH]
            [--mysql=PATH | -B PATH]
            [--test]
            [--help]

Examples:
  script.sh -u user -p
  script.sh -n mysqld|mariadbd -u user -p
  script.sh --test -u USER -p
  script.sh --host=127.0.0.1 -P 3306 -u USER -pPASSWORD
  script.sh --socket=/var/lib/mysql/mysql.sock --user=USER --password=PASS
  script.sh -B /usr/local/mysql -u USER -p         # /usr/local/mysql 사용

Notes:
  - -p / --password=/ --ask-pass 사용 시 --user(또는 -u) 필수
  - -p 옵션은 비밀번호를 지정하지 않는 경우, command 마지막에 위치하여야 합니다.
  - -mysql 옵션은 mysql 실행 파일의 절대 경로를 지정하여야 합니다. (ex : /MARIA/mariadb/bin/mysql 인 경우, --mysql=/MARIA/mariadb/bin/mysql)
  - 임시 옵션파일은 스크립트 종료 시 자동 삭제됩니다.
  - -h 는 help 전용입니다. host 단축옵션은 -H 를 사용하세요.
  - --mysql/-B 를 주지 않으면 기본 /usr/bin/mysql 을 사용합니다.
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }           # 에러 메시지 후 종료

cleanup() {                                       # 종료 시 민감파일 제거
    if [ -n "${TEMP_CNF:-}" ] && [ -f "$TEMP_CNF" ]; then
        shred -u "$TEMP_CNF" 2>/dev/null || rm -f "$TEMP_CNF"
    fi
}
trap cleanup EXIT                                  # 어떤 종료 경로든 cleanup 보장

# -------------------------
# Argument Normalization (short -> long): 단축옵션을 롱옵션으로 정규화
# -------------------------
norm_args=""                                       # 정규화된 인자 문자열
prev=""                                            # 직전 옵션 보관(-n/-u/-p/-H/-P/-S 값용)
for x in "$@"; do                                  # 원 인자 순회
    if [ -n "$prev" ]; then                        # 직전 옵션이 값 필요
        case "$prev" in
            -n) norm_args="$norm_args --name=$x" ;;
            -u) norm_args="$norm_args --user=$x" ;;
            -p) norm_args="$norm_args --ask-pass=$x" ;;     # -p <PASS>
            -H) norm_args="$norm_args --host=$x" ;;
            -P) norm_args="$norm_args --port=$x" ;;
            -S) norm_args="$norm_args --socket=$x" ;;
            -B) norm_args="$norm_args --mysql=$x" ;;
            *)  norm_args="$norm_args $prev $x" ;;
        esac
        prev=""
        continue
    fi
    case "$x" in
        -n|-u|-p|-H|-P|-S|-B) prev="$x" ;;                         # 다음 토큰이 값
        -p*) norm_args="$norm_args --ask-pass=${x#-p}" ;;          # -pPASSWORD
        --password=*) norm_args="$norm_args $x" ;;                 # --password=PASS
        --ask-pass=*|--name=*|--process=*|--user=*|--host=*|--port=*|--socket=*|--mysql=*)
            norm_args="$norm_args $x" ;;
        --ask-pass|--test|--help) norm_args="$norm_args $x" ;;
        -h) norm_args="$norm_args --help" ;;
        --) norm_args="$norm_args --" ;;
        *) norm_args="$norm_args $x" ;;
    esac
done
if [ -n "$prev" ]; then                            # 값 없이 끝난 단축옵션 처리
    case "$prev" in
        -p) norm_args="$norm_args --ask-pass" ;;  # -p만 주면 프롬프트 모드
        *)  die "option '$prev' requires a value" ;;
    esac
fi
# shellcheck disable=SC2086
set -- $norm_args                                  # 정규화된 인자로 재설정

# -------------------------
# Argument Parsing (for arg … case)
# -------------------------
for arg do
    val=$(echo "$arg" | sed -e 's/^[^=]*=//')      # --key=value 에서 value 추출
    if [ "$arg" = "--help" ] || [ "$arg" = "help" ]; then usage; exit 0; fi
    case "$arg" in
        --name=*|--process=*) PROVIDED_PROCESS="$val" ;;
        --user=*)             USER_ARG="$val" ;;
        --password=*)         ASK_PASS=true; PASSWORD_INPUT="$val" ;;
        --ask-pass=*)         ASK_PASS=true; PASSWORD_INPUT="$val" ;;
        --ask-pass)           ASK_PASS=true ;;
        --host=*)             HOST_ARG="$val" ;;
        --port=*)             PORT_ARG="$val" ;;
        --socket=*)           SOCKET_ARG="$val" ;;
        --mysql=*)          mysql="$val" ;;
        --test)               RUN_TEST=true ;;
        --)                   ;;                   # 포지셔널 인자 시작(본 스크립트 미사용)
        --*=*)                die "Invalid argument: $arg (use --help)" ;;
        --*)                  die "Missing value for $arg (use --key=value)" ;;
        *)                    die "Unexpected positional argument: $arg" ;;
    esac
done
if [ "$ASK_PASS" = true ] && [ -z "$USER_ARG" ]; then die "--password/--ask-pass/-p requires --user=USER"; fi

# -------------------------
# Resolve mysql absolute path (from --mysql or default)
# -------------------------
# 기본값: /usr/bin/mysql
MYSQL_BIN="/usr/bin/mysql"

# --mysql 이 주어지면 <mysql>/mysql 사용
if [ -n "${mysql:-}" ]; then
    MYSQL_BIN="${mysql%/}"
fi

# 존재/실행 가능 여부 확인
if [ ! -x "$MYSQL_BIN" ]; then
    die "mysql binary not found or not executable at '$MYSQL_BIN'. --mysql 로 경로를 지정하거나 기본 경로(/usr/bin/mysql)에 파일이 위치하는지, 파일 권한 문제가 있는지 확인하세요."
fi

# 프롬프트 모드라면 비번 입력 받기(무에코)
if [ "$ASK_PASS" = true ] && [ -z "$PASSWORD_INPUT" ]; then
    printf "Password for %s: " "$USER_ARG" >&2
    stty -echo
    read -r PASSWORD_INPUT
    stty echo
    echo >&2
fi

# -------------------------
# Process Discovery
# -------------------------
_find_pid_once() {                                 # 이름 하나로 PID 1개 찾기
    _name="$1"
    if command -v pidof >/dev/null 2>&1; then      # 1) pidof
        _pids="$(pidof "$_name" 2>/dev/null || true)"
        if [ -n "$_pids" ]; then for _p in $_pids; do echo "$_p"; return 0; done; fi
    fi
    if command -v pgrep >/dev/null 2>&1; then      # 2) pgrep -x
        _pid="$(pgrep -x "$_name" 2>/dev/null | head -n1 || true)"
        if [ -n "$_pid" ]; then echo "$_pid"; return 0; fi
        _pid="$(pgrep -f "(/|^|[[:space:]])${_name}([[:space:]]|$)" 2>/dev/null | head -n1 || true)"  # 3) pgrep -f
        if [ -n "$_pid" ]; then echo "$_pid"; return 0; fi
    fi
    if ps -C "$_name" -o pid= >/dev/null 2>&1; then    # 4) ps -C
        _pid="$(ps -C "$_name" -o pid= | awk 'NF{print $1; exit}')"
        if [ -n "$_pid" ]; then echo "$_pid"; return 0; fi
    fi
    # 5) 최종 폴백: 전체 테이블에서 comm/args 매칭
    _pid="$(ps -eo pid,comm,args | awk -v N="$_name" '
        NR>1 { if ($2==N || $0 ~ ("(/| |^)" N "($| )")) { print $1; exit } }' 2>/dev/null || true)"
    if [ -n "$_pid" ]; then echo "$_pid"; return 0; fi
    echo ""; return 1
}

_auto_find() {                                     # mariadbd 우선 → 실패 시 mysqld
    for _cand in mariadbd mysqld; do
        _pid="$(_find_pid_once "$_cand" || true)"
        if [ -n "$_pid" ]; then echo "${_cand}:${_pid}"; return 0; fi
    done
    echo ""; return 1
}

_warn_if_no_mysqld_safe() {                        # mysqld_safe 유무 안내
    _safe="$(_find_pid_once mysqld_safe || true)"
    if [ -z "$_safe" ]; then
        echo "알림: 'mysqld_safe' 프로세스가 보이지 않습니다. (직접 'mysqld'로 기동되었거나 구성 상 미사용일 수 있습니다.)"
    fi
}

discover_process_and_pid() {                       # 최종 탐색 엔트리
    local pid=""; local pname=""
    if [ -n "$PROVIDED_PROCESS" ]; then
        pid="$(_find_pid_once "$PROVIDED_PROCESS" || true)"
        [ -n "$pid" ] || die "Process '$PROVIDED_PROCESS' not found"
        pname="$PROVIDED_PROCESS"
    else
        local out; out="$(_auto_find)" || true
        [ -n "$out" ] || die "DB daemon not found (자동 탐색 mariadbd→mysqld 실패; --name= 으로 지정해 보세요)"
        pname="${out%%:*}"; pid="${out##*:}"
    fi
    _warn_if_no_mysqld_safe
    echo "$pname:$pid"
}

# -------------------------
# Extract --defaults-file from daemon cmdline
# -------------------------
extract_defaults_file_from_cmdline() {             # 데몬 CMD에서 --defaults-file 추출
    _pid="$1"
    local cmdline=""
    if [ -r "/proc/$_pid/cmdline" ]; then
        cmdline=$(tr '\0' ' ' < "/proc/$_pid/cmdline")
    else
        cmdline=$(ps -p "$_pid" -o args=)
    fi
    echo "$cmdline" | sed -n 's/.*--defaults-file=\([^[:space:]]\+\).*/\1/p' | head -n1 && return 0
    set -- $cmdline
    while [ $# -gt 0 ]; do
        if [ "$1" = "--defaults-file" ] && [ $# -ge 2 ]; then echo "$2"; return 0; fi
        shift
    done
    echo ""
}

# -------------------------
# Extract --socket from daemon cmdline
# -------------------------
extract_socket_from_cmdline() {                    # 데몬 CMD에서 --socket 추출
    _pid="$1"
    local cmdline=""
    if [ -r "/proc/$_pid/cmdline" ]; then
        cmdline=$(tr '\0' ' ' < "/proc/$_pid/cmdline")
    else
        cmdline=$(ps -p "$_pid" -o args=)
    fi
    # --socket=/path 형태 우선
    echo "$cmdline" | sed -n 's/.*--socket=\([^[:space:]]\+\).*/\1/p' | head -n1 && return 0
    # --socket [path] 형태도 대응
    set -- $cmdline
    while [ $# -gt 0 ]; do
        if [ "$1" = "--socket" ] && [ $# -ge 2 ]; then echo "$2"; return 0; fi
        shift
    done
    echo ""
}

# -------------------------
# Temp .cnf for client auth
# -------------------------
create_temp_cnf() {                                # --defaults-extra-file 로 쓸 임시 옵션 파일 생성
    _user="$1"; _pass="$2"
    umask 177
    TEMP_CNF="$(mktemp "$(pwd)"/mysql-auth-XXXXXX.cnf)"
    [ -n "$TEMP_CNF" ] && [ -f "$TEMP_CNF" ] || die "Failed to create temp options file"
    {
        echo "[client]"
        echo "user=${_user}"
        echo "password=${_pass}"
        # host/port/socket 설정이 주어졌다면 함께 기록
        if [ -n "${HOST_ARG:-}" ]; then echo "host=${HOST_ARG}"; fi
        if [ -n "${PORT_ARG:-}" ]; then echo "port=${PORT_ARG}"; fi
        if [ -n "${SOCKET_ARG:-}" ]; then echo "socket=${SOCKET_ARG}"; fi
    } > "$TEMP_CNF"
    chmod 600 "$TEMP_CNF"
}

# -------------------------
# Result File / Output helpers
# -------------------------
_result_file_path() {                              # 결과파일 경로(타입별/현재 일시 포함)
    local type="$1"
    local ts; ts="$(date +%Y_%m_%d_%H%M%S)"
    echo "$(pwd)/${ts}_${type}_script_checklist.result"
}
_write_div()  { echo "============================================================" >> "$RESULT_FILE"; }   # 구분선
_write_hdr()  { _write_div; echo "[$1]" >> "$RESULT_FILE"; _write_div; }                                   # 섹션 헤더
_write_qhdr() { echo "============================================================" >> "$RESULT_FILE"; echo "[QUERY]"  >> "$RESULT_FILE"; echo "" >> "$RESULT_FILE"; }
_write_rhdr() { echo "" >> "$RESULT_FILE"; echo "[RESULT]" >> "$RESULT_FILE"; echo "" >> "$RESULT_FILE"; }
_write_qftr() { echo "============================================================" >> "$RESULT_FILE"; echo "" >> "$RESULT_FILE"; }

# ------------------------------------------------------------
# MySQL 결과만 반환하는 경량 헬퍼
#  - _mysql_query_raw "SQL"            → 쿼리 전체 결과(stdout)
#  - _mysql_get_cell  "SQL" row col    → 지정 셀(기본 1행 2열)만 반환
#  - _mysql_get_var   key              → SHOW VARIABLES LIKE 'key' 의 값만 반환
#  종료코드: 성공 0, 실패 1 (빈 출력)
# ------------------------------------------------------------

_mysql_query_raw() {
    local sql="$1"
    # 사용자 미설정 → 실패
    [ -z "${USER_ARG:-}" ] && return 1

    if [ -n "${TEMP_CNF:-}" ] && [ -f "$TEMP_CNF" ]; then
        "$MYSQL_BIN" --defaults-extra-file="$TEMP_CNF" -u "$USER_ARG" -N -B -e "$sql" || return 1
    else
        local extra=()
        [ -n "${HOST_ARG:-}" ]   && extra+=("-h" "$HOST_ARG")
        [ -n "${PORT_ARG:-}" ]   && extra+=("-P" "$PORT_ARG")
        [ -n "${SOCKET_ARG:-}" ] && extra+=("-S" "$SOCKET_ARG")
        "$MYSQL_BIN" -u "$USER_ARG" "${extra[@]}" -N -B -e "$sql" || return 1
    fi
}

_mysql_get_cell() {
    # 사용: _mysql_get_cell "SQL" [row] [col]
    # 기본: row=1, col=2 (SHOW VARIABLES LIKE … → 2열 값)
    local sql="$1" row="${2:-1}" col="${3:-2}"
    local out
    if ! out="$(_mysql_query_raw "$sql")"; then
        return 1
    fi
    # 탭 우선, 탭 없으면 공백도 허용
    echo "$out" | awk -v r="$row" -v c="$col" -F'\t' '
        BEGIN{ORS="";} NR==r { if (NF<c) next; print $c; exit }
    '
    # 출력이 비면 실패 취급
    [ -s /dev/stdout ] || return 1
}

_mysql_get_var() {
    # 사용: _mysql_get_var log_error  (→ 값만 반환)
    local key="$1"
    _mysql_get_cell "SHOW GLOBAL VARIABLES LIKE '${key//\'/\\\'}';" 1 2
}

# -------------------------
# MySQL Runner
# -------------------------
_mysql_run() {                                    # 단일 쿼리 실행 + 결과 저장(쿼리/결과 블록 자동)
    local query="$1"                               # 실행할 SQL 텍스트
    _write_qhdr                                    # [QUERY] 헤더
    echo "$query" >> "$RESULT_FILE"                # 쿼리 본문 기록
    _write_rhdr                                    # [RESULT] 헤더

    if [ -z "${USER_ARG:-}" ]; then                # 사용자 미설정 시 불가능
        echo "불가능." >> "$RESULT_FILE"
    else
        if [ -n "${TEMP_CNF:-}" ] && [ -f "$TEMP_CNF" ]; then
            "$MYSQL_BIN" --defaults-extra-file="$TEMP_CNF" -u "$USER_ARG" -N -B -e "$query" >> "$RESULT_FILE" 2>&1 || echo "불가능." >> "$RESULT_FILE"
        else
            # 임시 옵션파일이 없으면 개별 옵션(-h/-P/-S)로 직접 전달
            local extra=()
            if [ -n "${HOST_ARG:-}" ]; then extra+=("-h" "$HOST_ARG"); fi
            if [ -n "${PORT_ARG:-}" ]; then extra+=("-P" "$PORT_ARG"); fi
            if [ -n "${SOCKET_ARG:-}" ]; then extra+=("-S" "$SOCKET_ARG"); fi
            "$MYSQL_BIN" -u "$USER_ARG" "${extra[@]}" -N -B -e "$query" >> "$RESULT_FILE" 2>&1 || echo "불가능." >> "$RESULT_FILE"
        fi
    fi
    _write_qftr                                     # 쿼리 블록 푸터
}

_mysql_run_include_header() {
    local query="$1"                               # 실행할 SQL 텍스트
    _write_qhdr                                    # [QUERY] 헤더
    echo "$query" >> "$RESULT_FILE"                # 쿼리 본문 기록
    _write_rhdr                                    # [RESULT] 헤더

    if [ -z "${USER_ARG:-}" ]; then                # 사용자 미설정 시 불가능
        echo "불가능." >> "$RESULT_FILE"
    else
        if [ -n "${TEMP_CNF:-}" ] && [ -f "$TEMP_CNF" ]; then
            "$MYSQL_BIN" --defaults-extra-file="$TEMP_CNF" -u "$USER_ARG" -e "$query" >> "$RESULT_FILE" 2>&1 || echo "불가능." >> "$RESULT_FILE"
        else
            # 임시 옵션파일이 없으면 개별 옵션(-h/-P/-S)로 직접 전달
            local extra=()
            if [ -n "${HOST_ARG:-}" ]; then extra+=("-h" "$HOST_ARG"); fi
            if [ -n "${PORT_ARG:-}" ]; then extra+=("-P" "$PORT_ARG"); fi
            if [ -n "${SOCKET_ARG:-}" ]; then extra+=("-S" "$SOCKET_ARG"); fi
            "$MYSQL_BIN" -u "$USER_ARG" "${extra[@]}" -e "$query" >> "$RESULT_FILE" 2>&1 || echo "불가능." >> "$RESULT_FILE"
        fi
    fi
    _write_qftr
}

_mysql_run_include_header_repeats() {
    local query="$1"                               # 실행할 SQL 텍스트

    for i in 1 2 3; do
        _write_qhdr                                # [QUERY] 헤더
        echo "${query} --(${i})" >> "$RESULT_FILE" # 쿼리 본문 + 실행횟수 표기
        _write_rhdr                                # [RESULT] 헤더

        if [ -z "${USER_ARG:-}" ]; then            # 사용자 미설정 시 불가능
            echo "불가능." >> "$RESULT_FILE"
        else
            if [ -n "${TEMP_CNF:-}" ] && [ -f "$TEMP_CNF" ]; then
                "$MYSQL_BIN" --defaults-extra-file="$TEMP_CNF" -u "$USER_ARG" -N -B -e "$query" \
                    >> "$RESULT_FILE" 2>&1 || echo "불가능." >> "$RESULT_FILE"
            else
                # 임시 옵션파일이 없으면 개별 옵션(-h/-P/-S)로 직접 전달
                local extra=()
                if [ -n "${HOST_ARG:-}" ]; then extra+=("-h" "$HOST_ARG"); fi
                if [ -n "${PORT_ARG:-}" ]; then extra+=("-P" "$PORT_ARG"); fi
                if [ -n "${SOCKET_ARG:-}" ]; then extra+=("-S" "$SOCKET_ARG"); fi
                "$MYSQL_BIN" -u "$USER_ARG" "${extra[@]}" -N -B -e "$query" >> "$RESULT_FILE" 2>&1 || echo "불가능." >> "$RESULT_FILE"
            fi
        fi
        _write_qftr                                # 쿼리 블록 푸터

        # 마지막 반복 전까지는 sleep 1s
        if [ "$i" -lt 3 ]; then
            sleep 1
        fi
    done
}

_mysql_capture_value() {                           # 단일 값 캡처(STATUS LIKE 결과 2열 등)
    local query="$1"
    if [ -z "${USER_ARG:-}" ]; then echo ""; return 0; fi
    if [ -n "${TEMP_CNF:-}" ] && [ -f "$TEMP_CNF" ]; then
        "$MYSQL_BIN" --defaults-extra-file="$TEMP_CNF" -u "$USER_ARG" -N -B -e "$query" 2>/dev/null | awk '{print $2}'
    else
        local extra=()
        if [ -n "${HOST_ARG:-}" ]; then extra+=("-h" "$HOST_ARG"); fi
        if [ -n "${PORT_ARG:-}" ]; then extra+=("-P" "$PORT_ARG"); fi
        if [ -n "${SOCKET_ARG:-}" ]; then extra+=("-S" "$SOCKET_ARG"); fi
        "$MYSQL_BIN" -u "$USER_ARG" "${extra[@]}" -N -B -e "$query" 2>/dev/null | awk '{print $2}'
    fi
}

# 상태 변수 2개를 한 번의 호출로 "v1;v2" 형태로 반환 (성능 최적화)
_mysql_capture_status_pair() {
    local name1="$1" name2="$2"
    local out v1="" v2=""
    if [ -z "${USER_ARG:-}" ]; then printf "%s;%s\n" "" ""; return 0; fi

    if [ -n "${TEMP_CNF:-}" ] && [ -f "$TEMP_CNF" ]; then
        out="$("$MYSQL_BIN" --defaults-extra-file="$TEMP_CNF" -u "$USER_ARG" -N -B \
            -e "SHOW GLOBAL STATUS WHERE Variable_name IN ('${name1}','${name2}');" 2>/dev/null)"
    else
        local extra=()
        if [ -n "${HOST_ARG:-}" ]; then extra+=("-h" "$HOST_ARG"); fi
        if [ -n "${PORT_ARG:-}" ]; then extra+=("-P" "$PORT_ARG"); fi
        if [ -n "${SOCKET_ARG:-}" ]; then extra+=("-S" "$SOCKET_ARG"); fi
        out="$("$MYSQL_BIN" -u "$USER_ARG" "${extra[@]}" -N -B \
            -e "SHOW GLOBAL STATUS WHERE Variable_name IN ('${name1}','${name2}');" 2>/dev/null)"
    fi

    # 결과 파싱 (두 줄 예상: name value)
    while read -r k v; do
        [ -z "$k" ] && continue
        case "$k" in
            "$name1") v1="$v" ;;
            "$name2") v2="$v" ;;
        esac
    done <<EOF
$out
EOF
    printf "%s;%s\n" "${v1:-0}" "${v2:-0}"
}

# -------------------------
# Shell Command Runner
# -------------------------
_sh_run() {
    local cmd="$1"
    _write_qhdr
    echo "$cmd" >> "$RESULT_FILE"
    _write_rhdr
    eval "$cmd" >> "$RESULT_FILE" 2>&1 || echo "불가능." >> "$RESULT_FILE"
    _write_qftr
}

# -------------------------
# free -m Runner (with usage % 계산)
# -------------------------
_sh_run_free_with_calc() {
    # _write_qhdr
    # free -m >> "$RESULT_FILE"
    _write_qhdr
    echo "free -m   # (total - free - buff/cache)/total * 100" >> "$RESULT_FILE"
    _write_rhdr

    # free 실행 결과
    local output
    if ! output="$(free -m 2>/dev/null)"; then
        echo "불가능." >> "$RESULT_FILE"
    else
        echo "$output" >> "$RESULT_FILE"

        # Mem: 라인에서 사용률 계산
        local total free used
        read -r _ total used free shared buff_cache available <<<"$(echo "$output" | awk '/^Mem:/ {print $1, $2, $3, $4, $5, $6, $7}')"

        if [ -n "$total" ] && [ "$total" -gt 0 ]; then
            local calc
            calc=$(awk -v t="$total" -v f="$free" -v b="$buff_cache" 'BEGIN{printf "%.2f", ((t - f - b)/t)*100}')
            echo "Memory Usage % (calc): $calc%" >> "$RESULT_FILE"
        else
            echo "Memory Usage %: NA" >> "$RESULT_FILE"
        fi
    fi
    _write_qftr
}

# -------------------------
# DB Checklist (SQL only, per-query separators)
# -------------------------
db_checklist() {
    RESULT_FILE="$(_result_file_path "DB")"       # 결과 파일 생성(타입=DB)

    SLOW_RESULT_FILE="$(_result_file_path "DB_SLOWLOG")"
    ERROR_RESULT_FILE="$(_result_file_path "DB_ERRORLOG")"

    _write_hdr "DB CHECKLIST (SQL ONLY, WITH PER-QUERY SEPARATORS)"

    # ===== System / Environment Checks =====
    _write_hdr "SYSTEM / ENVIRONMENT CHECKS"

    # /etc/os-release (없을 수 있음 → 실패 시 '불가능.' 기록)
    _sh_run "cat /etc/os-release"

    # /proc/loadavg
    _sh_run "cat /proc/loadavg"

    # free -m + 계산값
    _sh_run_free_with_calc

    # df -ThP
    _sh_run "df -ThP"

    # datadir (요청에 따라 명시적으로 한 번 더 출력)
    _mysql_run "SHOW VARIABLES LIKE 'datadir';"

    # ps -ef | grep ${PROC_NAME}  (PROC_NAME이 없으면 PROC 사용)
    PROC_GREP_TARGET="${PROC_NAME:-${PROC}}"
    _sh_run "ps -ef | grep ${PROC_GREP_TARGET}"

    # 0) LOG 변수(가능하면 SQL로) — 쿼리와 결과를 그대로 남김
    _mysql_run "SELECT @@hostname;"
    _mysql_run "SHOW VARIABLES LIKE 'log_error';"

############### 2025-10-13 추가(수정) ##############
## error log 경로 파싱 후 결과 분석 (RESULT_FILE 재파싱 제거, 안전한 grep)
    error_log_file="$(_mysql_get_var log_error || true)"

    if [ -n "$error_log_file" ] && [ -f "$error_log_file" ]; then
        _write_qhdr
        echo "Number of Got timeout warnings" >> "$RESULT_FILE"
        _write_rhdr
        { grep -i 'got timeout' "$error_log_file" || true; } | wc -l >> "$RESULT_FILE" 2>&1
        _write_qftr

        _write_qhdr
        echo "Number of Got an error warnings" >> "$RESULT_FILE"
        _write_rhdr
        { grep -i 'got an error' "$error_log_file" || true; } | wc -l >> "$RESULT_FILE" 2>&1
        _write_qftr

        _write_qhdr
        echo "Number of Aborted Connection warnings" >> "$RESULT_FILE"
        _write_rhdr
        { grep -i 'aborted connection' "$error_log_file" || true; } | wc -l >> "$RESULT_FILE" 2>&1
        _write_qftr

        _write_qhdr
        echo "Number of Access denied for user warnings" >> "$RESULT_FILE"
        _write_rhdr
        { grep -i 'access denied' "$error_log_file" || true; } | wc -l >> "$RESULT_FILE" 2>&1
        _write_qftr

        echo "Other error message details" >> "$ERROR_RESULT_FILE"
        echo "Target months : $CURRENT_MONTH, $LAST_MONTH, $TWO_MONTHS_AGO" >> "$ERROR_RESULT_FILE"
        { grep -i -e "$CURRENT_MONTH" -e "$LAST_MONTH" -e "$TWO_MONTHS_AGO" "$error_log_file" || true; } \
          | grep -vi -e 'aborted connection' -e 'got timeout' -e 'got an error' -e 'access denied' \
          >> "$ERROR_RESULT_FILE" 2>/dev/null || true
    else
        echo "Error log 파일을 찾지 못했거나 경로가 비어 있습니다: '$error_log_file'" >> "$RESULT_FILE"
    fi
################################################

    _mysql_run "SHOW VARIABLES LIKE 'slow_query_log';"
    _mysql_run "SHOW VARIABLES LIKE 'slow_query_log_file';"

############### 2025-10-14 추가(수정) ##############
## slow log 경로 파싱 후 결과 분석 (RESULT_FILE 재파싱 제거, 안전한 카운트)
    slow_log_file="$(_mysql_get_var slow_query_log_file || true)"

    RE_DASH='[0-9]{4}-[0-9]{2}-[0-9]{2}'
    RE_COMPACT='[0-9]{8}'

    # 단순화된 월별 패턴(YYYY-MM-DD / YYYYMMDD 모두 대응)
    pat_cur="(${CURRENT_MONTH}-[0-9]{2}|${CURRENT_MONTH//-/}[0-9]{2})"
    pat_last="(${LAST_MONTH}-[0-9]{2}|${LAST_MONTH//-/}[0-9]{2})"
    pat_two="(${TWO_MONTHS_AGO}-[0-9]{2}|${TWO_MONTHS_AGO//-/}[0-9]{2})"

    count_current=0
    count_last=0
    count_twoago=0

    if [ -n "$slow_log_file" ] && [ -f "$slow_log_file" ]; then
        count_current=$( { grep -Eoc "$pat_cur" "$slow_log_file" 2>/dev/null || echo ""; } )
        count_last=$(    { grep -Eoc "$pat_last" "$slow_log_file" 2>/dev/null || echo ""; } )
        count_twoago=$(  { grep -Eoc "$pat_two" "$slow_log_file" 2>/dev/null || echo ""; } )
    else
        echo "Error: slow_query_log_file 파일을 찾지 못했습니다: '$slow_log_file'" >> "$RESULT_FILE"
    fi

    # echo "slow log 파일명: $slow_log_file" >> "$RESULT_FILE"
    echo "Number of SLOW LOG $CURRENT_MONTH :  $count_current" >> "$RESULT_FILE"
    echo "Number of SLOW LOG $LAST_MONTH :  $count_last" >> "$RESULT_FILE"
    echo "Number of SLOW LOG $TWO_MONTHS_AGO :  $count_twoago" >> "$RESULT_FILE"
    echo " "

################################################

    # 1) status; → 클라이언트 명령(비-SQL) 이므로 불가능 명시
    _mysql_run "status;"

    # 2) 버전
    _mysql_run "SELECT @@version;"

    # 3~6) 주요 지표
    _mysql_run_include_header_repeats "SHOW GLOBAL STATUS LIKE 'Threads_created';"
    _mysql_run_include_header_repeats "SHOW GLOBAL STATUS LIKE 'Sort_merge_passes';"
    _mysql_run "SHOW GLOBAL STATUS LIKE 'Max_used_connections';"
    _mysql_run_include_header_repeats "SHOW GLOBAL STATUS LIKE 'Created_tmp_disk_tables';"

    # 7) MyISAM 테이블 목록(시스템 DB 제외)
    _mysql_run "SELECT TABLE_SCHEMA, TABLE_NAME, ENGINE FROM information_schema.tables WHERE ENGINE='MyISAM' AND TABLE_SCHEMA <> 'mysql' ORDER BY TABLE_SCHEMA, TABLE_NAME;"
    _mysql_run "SELECT TABLE_SCHEMA, TABLE_NAME, ENGINE FROM information_schema.tables WHERE ENGINE='MyISAM' ORDER BY TABLE_SCHEMA, TABLE_NAME;"

    _mysql_run_include_header "show slave status\\G;"
    _mysql_run_include_header "show replica status\\G;"

    # -------------------------
    # Key Cache & Buffer Pool 계산 (WHERE IN 단일 호출 최적화)
    # -------------------------

    # 8) Key Cache 계산(읽기 히트)
    _mysql_run "SHOW GLOBAL STATUS LIKE 'Key_reads';"
    _mysql_run "SHOW GLOBAL STATUS LIKE 'Key_read_requests';"
    _write_qhdr
    echo "/* [1 - (Key_reads/Key_read_requests)]*100 */" >> "$RESULT_FILE"
    echo "SHOW GLOBAL STATUS WHERE Variable_name IN ('Key_reads','Key_read_requests');" >> "$RESULT_FILE"
    _write_rhdr
    {
        local pair kr krr oldIFS
        pair="$(_mysql_capture_status_pair "Key_reads" "Key_read_requests")"
        oldIFS="$IFS"; IFS=';'; read -r kr krr <<< "$pair"; IFS="$oldIFS"
        if [ -z "${krr:-}" ] || [ "${krr:-0}" = "0" ]; then
            echo "Key Read Hit %: NA (Key_read_requests=0)"
        else
            awk -v a="${kr:-0}" -v b="${krr:-0}" 'BEGIN{printf "Key Read Hit %%: %.2f%%\n", (1 - (a/b))*100}'
        fi
    } >> "$RESULT_FILE" 2>&1
    _write_qftr

    # 9) Key Cache 계산(쓰기 비율)
    _mysql_run "SHOW GLOBAL STATUS LIKE 'Key_writes';"
    _mysql_run "SHOW GLOBAL STATUS LIKE 'Key_write_requests';"
    _write_qhdr
    echo "/* (Key_writes/Key_write_requests)*100 */" >> "$RESULT_FILE"
    echo "SHOW GLOBAL STATUS WHERE Variable_name IN ('Key_writes','Key_write_requests');" >> "$RESULT_FILE"
    _write_rhdr
    {
        local pair kw kwr oldIFS
        pair="$(_mysql_capture_status_pair "Key_writes" "Key_write_requests")"
        oldIFS="$IFS"; IFS=';'; read -r kw kwr <<< "$pair"; IFS="$oldIFS"
        if [ -z "${kwr:-}" ] || [ "${kwr:-0}" = "0" ]; then
            echo "Key Write Hit %: NA (Key_write_requests=0)"
        else
            awk -v a="${kw:-0}" -v b="${kwr:-0}" 'BEGIN{printf "Key Write Hit %%: %.2f%%\n", (a/b)*100}'
        fi
    } >> "$RESULT_FILE" 2>&1
    _write_qftr

    # 10) Buffer Pool Read 비율
    _mysql_run "SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_reads';"
    _mysql_run "SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_read_requests';"
    _write_qhdr
    echo "/* 100-(100*Innodb_buffer_pool_reads/Innodb_buffer_pool_read_requests) */" >> "$RESULT_FILE"
    echo "SHOW GLOBAL STATUS WHERE Variable_name IN ('Innodb_buffer_pool_reads','Innodb_buffer_pool_read_requests');" >> "$RESULT_FILE"
    _write_rhdr
    {
        local pair bp_reads bp_read_reqs oldIFS
        pair="$(_mysql_capture_status_pair "Innodb_buffer_pool_reads" "Innodb_buffer_pool_read_requests")"
        oldIFS="$IFS"; IFS=';'; read -r bp_reads bp_read_reqs <<< "$pair"; IFS="$oldIFS"
        if [ -z "${bp_read_reqs:-}" ] || [ "${bp_read_reqs:-0}" = "0" ]; then
            echo "Buffer Pool Hit %: NA (Innodb_buffer_pool_read_requests=0)"
        else
            awk -v r="${bp_reads:-0}" -v rr="${bp_read_reqs:-0}" 'BEGIN{printf "Buffer Pool Hit %%: %.2f%%\n", 100 - (100*r/rr)}'
        fi
    } >> "$RESULT_FILE" 2>&1
    _write_qftr

    # 12) Pending IO 지표
    _mysql_run "SHOW GLOBAL STATUS LIKE 'Innodb_data_pending_reads';"
    _mysql_run "SHOW GLOBAL STATUS LIKE 'Innodb_data_pending_writes';"
    _mysql_run "SHOW GLOBAL STATUS LIKE 'Innodb_data_pending_fsyncs';"
    _mysql_run "SHOW GLOBAL STATUS LIKE 'Innodb_os_log_pending_fsyncs';"
}

# -------------------------
# Main
# -------------------------
PROC_AND_PID="$(discover_process_and_pid)"         # 데몬 프로세스 탐색(자동/지정)
PROC_NAME="${PROC_AND_PID%%:*}"                    # 프로세스명
PID="${PROC_AND_PID##*:}"                          # PID

DB_CONFIG="$(extract_defaults_file_from_cmdline "$PID")"   # --defaults-file 추출
if [ -z "$DB_CONFIG" ]; then
    echo "경고: 데몬 인자에서 --defaults-file을 찾지 못했습니다. (proc: ${PROC_NAME}, pid: ${PID})"
    for cand in /etc/my.cnf /etc/mysql/my.cnf /usr/local/etc/my.cnf; do
        if [ -f "$cand" ]; then
            echo "참고: 기본 경로에서 설정 파일을 발견했습니다: $cand"
            echo "Database 데몬이 ${cand} 를 사용한다고 가정합니다."
            DB_CONFIG=$cand
            break
        fi
    done
else
    echo "데몬 config 파일: ${DB_CONFIG}"
fi
# export DB_CONFIG

if [ -z "${SOCKET_ARG:-}" ]; then
    # 프로세스 cmdline에서 --socket 추출 시도
    SOCKET_FROM_CMD="$(extract_socket_from_cmdline "$PID" || true)"
    if [ -n "$SOCKET_FROM_CMD" ]; then
        SOCKET_ARG="$SOCKET_FROM_CMD"
        echo "데몬 socket: ${SOCKET_ARG}"
    else
        # 인자/프로세스 어디에서도 발견되지 않은 경우: 빈 값으로 둠
        echo "알림: 소켓 경로를 찾지 못했습니다. (proc: ${PROC_NAME}, pid: ${PID})"
        echo "      TCP(host/port) 접속 또는 --socket=PATH 인자 사용을 권장합니다."
    fi
fi


if [ "$ASK_PASS" = true ]; then                   # 인증 옵션파일 생성(요청 시)
    create_temp_cnf "$USER_ARG" "$PASSWORD_INPUT"  
fi

# if [ "$RUN_TEST" = true ]; then                   # 연결 테스트(선택)
if [ ! -x "$MYSQL_BIN" ]; then die "'$MYSQL_BIN' not found or not executable"; fi
echo "연결 테스트 SELECT VERSION(); 을 수행합니다 ..."
if [ -n "$TEMP_CNF" ]; then
    "$MYSQL_BIN" --defaults-extra-file="$TEMP_CNF" -u "$USER_ARG" -N -B -e "SELECT VERSION();" || die "연결/인증 실패"
else
    # 임시 옵션파일이 없을 경우 직접 옵션 전달
    extra=()
    if [ -n "${HOST_ARG:-}" ]; then extra+=("-h" "$HOST_ARG"); fi
    if [ -n "${PORT_ARG:-}" ]; then extra+=("-P" "$PORT_ARG"); fi
    if [ -n "${SOCKET_ARG:-}" ]; then extra+=("-S" "$SOCKET_ARG"); fi
    "$MYSQL_BIN" -u "$USER_ARG" "${extra[@]}" -N -B -e "SELECT VERSION();" || die "연결 실패"
fi
# exit 0
echo "연결 테스트 성공"
# fi

db_checklist                                      # SQL 전용 체크리스트 수행
# echo                                              # 요약 출력
echo "요약"
echo "  프로세스명   : ${PROC_NAME}"
echo "  PID          : ${PID}"
echo "  DB_CONFIG    : ${DB_CONFIG:-<미탐지>}"
if [ -n "$TEMP_CNF" ]; then
    echo "  임시 인증파일: ${TEMP_CNF} (종료 시 자동 삭제)"
else
    echo "  임시 인증파일: <생성 안 됨>"
fi
echo "  mysql 경로   : ${MYSQL_BIN}"
