#!/usr/bin/env bash
# =============================================================================
#  cbi-check-lib.sh — ฟังก์ชันกลางของชุดสคริปต์ตรวจความพร้อม CUBIKA / Portal / DB / Enforcer / Proxy
#  ไม่ต้องรันไฟล์นี้เอง — สคริปต์ check-*.sh จะ source ไฟล์นี้ (ต้องอยู่โฟลเดอร์เดียวกัน)
#
#  หลักการ : อ่านอย่างเดียว ไม่หยุด/start/แก้ไฟล์ของระบบ ; ไม่พิมพ์ password / secret
# =============================================================================

LIB_VERSION="3.2.8"
set -o pipefail

# ---------- สี / ตัวนับ ----------
if [ -t 1 ]; then R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[36m'; N=$'\e[0m'; else R=; G=; Y=; B=; N=; fi
NPASS=0; NWARN=0; NFAIL=0
ASSUME_YES="${ASSUME_YES:-0}"
NO_NET="${NO_NET:-0}"              # 1 = ไม่เปิด connection ใด ๆ ออกไป (ข้าม url_check / tcp_check)
# รูปแบบชื่อ jar (รองรับชื่อที่ตั้งใหม่ เช่น dataguard-policy.jar / dataguard-proxy.jar บน SPW)
ENFORCER_PAT="${ENFORCER_PAT:-dataguard-policy-enforcer|dataguard-policy[^/ ]*\.jar}"
PROXY_PAT="${PROXY_PAT:-db-security-proxy|dataguard-proxy[^/ ]*\.jar}"      # 1 = ไม่ถาม ใช้ค่า default / ค่าจาก environment

CUR_SECTION=""; RESULTS=""; EVID=""
section() { CUR_SECTION="$1"; printf '\n%s== %s ==%s\n' "$B" "$1" "$N"; }
# _m : ปิดค่าลับในข้อความก่อนแสดง / บันทึก (เรียก perl เฉพาะเมื่อข้อความมีคำที่น่าสงสัย)
_m() { local l="${1,,}"; l=${l//passthrough/}; if [[ "$l" =~ (pass|pwd|secret|token|credential|private|apikey|api_key|bearer|eyj|://[^/[:space:]]*@) ]]; then printf '%s' "$1" | mask_text; else printf '%s' "$1"; fi; }
# _rec STATUS ข้อความ ได้ ดูต่อ → เพิ่มแถวใน results.csv (ทุกผลการตรวจถูกเก็บเป็นไฟล์)
csvq() { local v="${1//\"/\"\"}"; printf '"%s"' "$v"; }
_rec() {
  [ -n "$RESULTS" ] || return 0
  { csvq "$(date '+%F %T')"; printf ','; csvq "$CHECK_NAME"; printf ','; csvq "$CUR_SECTION"; printf ','
    csvq "$1"; printf ','; csvq "$2"; printf ','; csvq "${3:-}"; printf ','; csvq "${4:-}"; printf '\n'; } >> "$RESULTS"
}
_out() {   # _out STATUS สี ข้อความ ได้ ดูต่อ
  local m g; m=$(_m "$3"); g=$(_m "${4:-}")
  printf '%s[%s]%s %s\n' "$2" "$1" "$N" "$m"; [ -n "$g" ] && printf '       ได้  : %s\n' "$g"; [ -n "${5:-}" ] && printf '       ดูต่อ: %s\n' "$5"
  _rec "$1" "$m" "$g" "${5:-}"; return 0
}
pass()  { NPASS=$((NPASS+1)); _out PASS "$G" "$1" "${2:-}"; }
warn()  { NWARN=$((NWARN+1)); _out WARN "$Y" "$1" "${2:-}" "${3:-}"; }
fail()  { NFAIL=$((NFAIL+1)); _out FAIL "$R" "$1" "${2:-}" "${3:-}"; }
info()  { local m; m=$(_m "$1"); printf '[INFO] %s\n' "$m"; _rec INFO "$m"; }
skip()  { printf '[SKIP] %s\n' "$1"; _rec SKIP "$1"; }
have()  { command -v "$1" >/dev/null 2>&1; }

# ---------- argument กลาง ----------
parse_common_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -y|--yes) ASSUME_YES=1; shift ;;
      -n|--no-network) NO_NET=1; shift ;;
      -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
      *) echo "ไม่รู้จัก argument: $1 (ใช้ -y = ไม่ถาม, -n = ไม่ทดสอบเครือข่าย, -h = ช่วยเหลือ)"; exit 2 ;;
    esac
  done
}

# ---------- ถามค่า / path จากผู้รัน ----------
# ask VAR "คำถาม" "ค่า default" TYPE
#   TYPE : dir | file | dir? | file? | text | text?    (? = เว้นว่างได้)
ask() {
  local var="$1" q="$2" def="$3" type="${4:-text}" cur ans opt=0
  cur="${!var-$def}"
  if [ -z "${_ASK_HINT:-}" ] && [ "$ASSUME_YES" != "1" ]; then _ASK_HINT=1; echo "(ค่าที่แสดงไว้แล้ว : Enter = ใช้ค่านั้น ; ต้องการพิมพ์ใหม่ กด Ctrl+U ลบก่อน)"; fi
  case "$type" in *\?) opt=1; type="${type%\?}";; esac
  while :; do
    if [ "$ASSUME_YES" = "1" ] || [ ! -r /dev/tty ]; then
      ans="$cur"
    else
      read -r -e -i "$cur" -p "$q : " ans </dev/tty || ans="$cur"
    fi
    ans="${ans/#\~/$HOME}"; ans="${ans%/}"; [ "$ans" = "" ] && [ "$cur" = "/" ] && ans="/"
    if [ -z "$ans" ]; then
      [ "$opt" = "1" ] && break
      echo "  ต้องระบุค่า"; [ "$ASSUME_YES" = "1" ] && { echo "  (-y) ไม่มีค่า: $var"; exit 2; }; continue
    fi
    case "$type" in
      dir)  [ -d "$ans" ] && break; _nf "ไม่พบโฟลเดอร์" "$ans" ;;
      file) [ -f "$ans" ] && break; _nf "ไม่พบไฟล์" "$ans" ;;
      *) break ;;
    esac
    if [ "$opt" = "1" ] && [ "$ASSUME_YES" != "1" ]; then
      echo "  (ข้อนี้เว้นว่างได้ — ลบข้อความด้วย Ctrl+U แล้วกด Enter)"; cur=""; continue
    fi
    if [ "$ASSUME_YES" = "1" ]; then
      if [ "$opt" = "1" ]; then echo "  (-y) ไม่พบ $ans — ข้าม $var"; ans=""; break; fi
      echo "  (-y) path ไม่ถูกต้อง: $var=$ans"; exit 2
    fi
    read -r -p "  ใช้ค่านี้ต่อทั้งที่ไม่พบ? (y/N) " yn </dev/tty; [ "$yn" = "y" ] && break
  done
  printf -v "$var" '%s' "$ans"
  ANSWERS+=("$var=$ans")
}
ANSWERS=()
_nf() { case "$2" in /*|./*|../*) echo "  $1: $2" ;; *) echo "  $1 (ค่าที่ใส่ไม่ใช่ path — ใส่ path เต็ม เช่น /home/... )" ;; esac; }

# ---------- รายงาน / ไฟล์ผลการตรวจ ----------
# start_report "ชื่อการตรวจ"
#   สร้างโฟลเดอร์ <โฟลเดอร์ที่รันสคริปต์>/<ชื่อ>_<host>_<เวลา>/ แล้วเก็บทุกอย่างไว้ในนั้น :
#     report.log    ทุกบรรทัดที่แสดงบนจอ (ไม่มีรหัสสี)
#     results.csv   ผลการตรวจทีละข้อ (เวลา, ส่วน, PASS/WARN/FAIL/INFO/SKIP, ข้อความ, ได้, ดูต่อ) — เปิดด้วย Excel ได้
#     answers.txt   ค่า / path ที่ผู้รันระบุ
#     host.txt      ข้อมูลเครื่องที่ตรวจ
#     evidence/     หลักฐานดิบ : config (ซ่อนค่าลับ), log ช่วงที่ตรวจ, process, สิทธิ์ไฟล์, URL, port ฯลฯ
#     summary.txt   สรุปจำนวน PASS/WARN/FAIL
#   และเพิ่ม 1 แถวใน <โฟลเดอร์ที่รันสคริปต์>/cbi-check-history.csv (ประวัติการตรวจทุกครั้ง)
start_report() {
  CHECK_NAME="$1"
  RUN_HOST=$(hostname 2>/dev/null || echo host)
  RUN_TS=$(date +%Y%m%d_%H%M%S)
  RUN_START_EPOCH=$(date +%s)
  REPORT_DIR="${REPORT_DIR:-$PWD}"
  # กันการเขียนผลลงโฟลเดอร์ของระบบ (เช่น webapps/ — Tomcat จะ deploy โฟลเดอร์ใหม่เป็นแอป)
  local rd; rd=$(readlink -f -- "$REPORT_DIR" 2>/dev/null)
  [ -n "$rd" ] && [ -d "$rd" ] || { echo "ไม่พบโฟลเดอร์เก็บผล $REPORT_DIR"; exit 2; }
  [ -w "$rd" ] || { echo "เขียนโฟลเดอร์ $rd ไม่ได้ ($(stat -c '%U:%G %a' "$rd")) — รันจากโฟลเดอร์ของตัวเอง เช่น ~/check"; exit 2; }
  REPORT_DIR="$rd"
  case "$rd/" in
    */webapps/*|*/work/Catalina/*|*/temp/*|*/conf/*|*/WEB-INF/*|*/dataguard/*|*/pending-jobs/*|*/policycached/*|*/dataconnector/*|*/cred/*|/etc/*|/proc/*|/sys/*|/)
      echo "ห้ามเก็บผลการตรวจใน $rd (เป็นโฟลเดอร์ของระบบ / agent) — cd ไปโฟลเดอร์อื่น เช่น ~/check แล้วรันใหม่"; exit 2 ;;
  esac
  umask 077
  OUT_DIR="$REPORT_DIR/${CHECK_NAME}_${RUN_HOST}_${RUN_TS}"
  mkdir -p "$OUT_DIR/evidence" || { echo "สร้างโฟลเดอร์ $OUT_DIR ไม่ได้ (สิทธิ์?) — รันจากโฟลเดอร์ที่เขียนได้ หรือตั้ง REPORT_DIR=/path"; exit 2; }
  EVID="$OUT_DIR/evidence"
  REPORT="$OUT_DIR/report.log"; RESULTS="$OUT_DIR/results.csv"
  printf '\xEF\xBB\xBF"time","check","section","status","message","got","next"\n' > "$RESULTS"
  exec > >(tee >(sed -u 's/\x1b\[[0-9;]*m//g' > "$REPORT")) 2>&1
  section "ข้อมูลการตรวจ"
  info "สคริปต์        : $0  (lib v$LIB_VERSION)"
  info "เริ่มตรวจ       : $(date '+%Y-%m-%d %H:%M:%S %Z (UTC%z)')"
  info "hostname      : $RUN_HOST"
  info "FQDN          : $(hostname -f 2>/dev/null || echo '-')"
  info "IP ของเครื่อง    : $(ip -o -4 addr 2>/dev/null | awk '{print $2"="$4}' | tr '\n' ' ')"
  info "OS            : $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-?}") / kernel $(uname -r)"
  info "timezone      : $(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo '?')"
  info "uptime        : $(uptime -p 2>/dev/null || uptime)"
  info "ผู้รัน          : $(id -un) (uid $(id -u))"
  info "โฟลเดอร์ที่รัน   : $PWD"
  info "ผลการตรวจเก็บที่ : $OUT_DIR/"
  { echo "check      : $CHECK_NAME"; echo "script     : $0 (lib v$LIB_VERSION)"; echo "start      : $(date '+%F %T %z')"
    echo "hostname   : $RUN_HOST"; echo "fqdn       : $(hostname -f 2>/dev/null)"; echo "run_dir    : $PWD"; echo "user       : $(id -un) (uid $(id -u))"
    echo; echo "--- ip addr"; ip -o -4 addr 2>/dev/null; echo; echo "--- os"; cat /etc/os-release 2>/dev/null; uname -a
    echo; echo "--- time"; timedatectl 2>/dev/null || date; echo; echo "--- uptime"; uptime
    echo; echo "--- df -h"; df -h 2>/dev/null; echo; echo "--- free -m"; free -m 2>/dev/null; } > "$OUT_DIR/host.txt" 2>&1
  tz=$(date +%z); [ "$tz" = "+0700" ] || warn "timezone ของเครื่องไม่ใช่ UTC+07:00 ($tz)" "" "เวลาใน log จะไม่ตรงกับเวลาผู้ใช้ — ตั้ง timedatectl set-timezone Asia/Bangkok"
}

print_answers() {
  section "ค่าที่ผู้รันระบุ"
  local a; for a in "${ANSWERS[@]}"; do info "$a"; done
  printf '%s\n' "${ANSWERS[@]}" > "$OUT_DIR/answers.txt"
}

end_report() {
  section "สรุป — $CHECK_NAME"
  local dur=$(( $(date +%s) - RUN_START_EPOCH )) result="OK"
  [ "$NWARN" -gt 0 ] && result="WARN"; [ "$NFAIL" -gt 0 ] && result="FAIL"
  info "ตรวจเสร็จ       : $(date '+%Y-%m-%d %H:%M:%S %Z (UTC%z)')  (ใช้เวลา ${dur} วินาที)"
  printf '%sPASS %d%s  %sWARN %d%s  %sFAIL %d%s\n' "$G" "$NPASS" "$N" "$Y" "$NWARN" "$N" "$R" "$NFAIL" "$N"
  [ -n "${MANUAL_CHECKS:-}" ] && { echo "ต้องตรวจที่หน้าจอเพิ่ม :"; printf '%s\n' "$MANUAL_CHECKS" | sed 's/^/  - /'; }
  {
    echo "check    : $CHECK_NAME"; echo "host     : $RUN_HOST"; echo "start    : $(date -d "@$RUN_START_EPOCH" '+%F %T %z')"
    echo "end      : $(date '+%F %T %z') (${dur}s)"; echo "result   : $result  (PASS $NPASS / WARN $NWARN / FAIL $NFAIL)"
    echo; echo "--- FAIL"; grep '^"[^"]*","[^"]*","[^"]*","FAIL"' "$RESULTS" | cut -d, -f3- ; echo
    echo "--- WARN"; grep '^"[^"]*","[^"]*","[^"]*","WARN"' "$RESULTS" | cut -d, -f3-
    [ -n "${MANUAL_CHECKS:-}" ] && { echo; echo "--- ต้องตรวจที่หน้าจอเพิ่ม"; printf '%s\n' "$MANUAL_CHECKS"; }
  } > "$OUT_DIR/summary.txt"
  local H="$REPORT_DIR/cbi-check-history.csv"
  [ -f "$H" ] || printf '\xEF\xBB\xBF"start","end","check","host","user","result","pass","warn","fail","folder"\n' > "$H"
  printf '"%s","%s","%s","%s","%s","%s",%d,%d,%d,"%s"\n' "$(date -d "@$RUN_START_EPOCH" '+%F %T')" "$(date '+%F %T')" \
    "$CHECK_NAME" "$RUN_HOST" "$(id -un)" "$result" "$NPASS" "$NWARN" "$NFAIL" "$OUT_DIR" >> "$H"
  chmod -R go-rwx "$OUT_DIR" 2>/dev/null
  echo
  echo "ผลการตรวจทั้งหมดเก็บที่ : $OUT_DIR/"
  echo "   report.log  results.csv  summary.txt  answers.txt  host.txt  evidence/ ($(find "$EVID" -type f | wc -l) ไฟล์)"
  echo "ประวัติการตรวจ       : $H"
  sleep 0.3
  [ "$NFAIL" -gt 0 ] && exit 1 || exit 0
}

# ---------- หลักฐาน (evidence) — ทุกไฟล์ผ่าน mask_text ก่อนบันทึก ----------
SECRET_WORD_RE='pass|pwd|secret|token|credential|private|apikey|api_key|encrypt'
# การปิดค่าลับ : MASK_MODE=partial (ค่าเริ่มต้น) = ปิดบางส่วน ให้เทียบค่าจริงได้ ; MASK_MODE=full = ซ่อนทั้งหมด
#   ยาว ≥16 ตัว : 4 ตัวแรก + *** + 4 ตัวท้าย (ความยาว)    เช่น fd64***a147(36)
#   ยาว 8–15   : 2 ตัวแรก + *** + 2 ตัวท้าย (ความยาว)    เช่น Ab***9x(10)
#   ยาว <8     : ***(ความยาว) — สั้นเกินจะเปิดบางส่วนได้อย่างปลอดภัย
MASK_MODE="${MASK_MODE:-partial}"
pmask() {   # pmask ค่า → ค่าที่ปิดบางส่วน (ใช้ใน shell)
  local v="$1" n=${#1}
  [ "$n" -eq 0 ] && return 0
  if [ "$MASK_MODE" = "full" ] || [ "$n" -lt 8 ]; then printf '***(%d)' "$n"
  elif [ "$n" -lt 16 ]; then printf '%s***%s(%d)' "${v:0:2}" "${v: -2}" "$n"
  else printf '%s***%s(%d)' "${v:0:4}" "${v: -4}" "$n"; fi
}
# mask_text : ปิดค่าลับในข้อความ (key=value / key value ที่ชื่อ key มีคำลับ, user:pass@ ใน URL, password=… ใน log, JWT, Bearer)
mask_text() {
  if have perl; then
    MASK_MODE="$MASK_MODE" SECRET_WORD_RE="$SECRET_WORD_RE" perl -CSDA -pe '
      BEGIN { $re = $ENV{SECRET_WORD_RE}; $re =~ s/\bpass\b/pass(?!through)/; $full = ($ENV{MASK_MODE} eq "full"); }   # passthrough ไม่ใช่ค่าลับ ; -CSDA = นับตัวอักษรแบบ UTF-8 (ไม่ตัดภาษาไทยกลางตัว)
      sub pm { my $v = shift; my $n = length $v; return $v if $n == 0 || $v =~ /\*\*\*/ || $v !~ /[A-Za-z0-9]/;   # ข้ามค่าที่ปิดแล้ว / ข้อความสถานะภาษาไทย เช่น (ว่าง)
               return "***($n)" if $full || $n < 8;
               return substr($v,0,2)."***".substr($v,-2)."($n)" if $n < 16;
               return substr($v,0,4)."***".substr($v,-4)."($n)"; }
      s{(://[^/:@\s]+:)([^/@\s]+)@}{$1.pm($2)."@"}ge;
      if (/^\s*[^#!\s=:]*(?:$re)[^\s=:]*\s*[=:\s]\s*\S/i) {
        s{^(\s*[^#!\s=:]*(?:$re)[^\s=:]*\s*[=:\s]\s*["\x27]?)(.*?)(["\x27]?[,;\}\]]*\s*)$}{$1.pm($2).$3}ie;
      } else {
        s#((?:password|passwd|pwd|secret|token)["\x27]?\s*[=:]\s*["\x27]?)([^"\x27&\s,\}]+)#$1.pm($2)#gie;
      }
      s{eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]*}{pm($&)}ge;
      s{(Bearer\s+)([A-Za-z0-9._~+/=-]{8,})}{$1.pm($2)}gie;
    '
  else   # ไม่มี perl → ซ่อนทั้งหมด
    sed -E \
     -e 's#(://)[^/@[:space:]]+@#\1***@#g' \
     -e "s#^([[:space:]]*[^\#![:space:]=:]*(${SECRET_WORD_RE})[^[:space:]=:]*[[:space:]]*[=:[:space:]][[:space:]]*)[^[:space:]].*\$#\1***(ซ่อน)#I" \
     -e "s#((password|passwd|pwd|secret|token)[\"']?[[:space:]]*[=:][[:space:]]*[\"']?)[^\"'&[:space:],}]+#\1***#Ig" \
     -e 's#eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]*#<jwt-ซ่อน>#g' \
     -e 's#(Bearer[[:space:]]+)[A-Za-z0-9._~+/=-]+#\1***#Ig'
  fi
}
# ev_save NAME            : stdin → evidence/NAME (ซ่อนค่าลับ)
ev_save() { [ -n "$EVID" ] || { cat >/dev/null; return 0; }; mkdir -p "$(dirname "$EVID/$1")"; mask_text > "$EVID/$1"; }
# ev_cmd NAME คำสั่ง…      : รันคำสั่ง (อ่านอย่างเดียว) แล้วเก็บผล
ev_cmd()  { local n="$1"; shift; { echo "# $(date '+%F %T') \$ $*"; "$@" 2>&1; } | ev_save "$n"; }
# ev_conf SRC [NAME]      : copy config (ซ่อนค่าลับ) → evidence/config/NAME + บรรทัด stat
ev_conf() {
  local src="$1" n="${2:-$(basename "$1")}"
  [ -n "$src" ] && [ -r "$src" ] || return 0
  { echo "# source : $src"; echo "# stat   : $(stat -c '%U:%G %a %s bytes, แก้ล่าสุด %y' "$src" 2>/dev/null)"
    echo "# sha256 : $(sha256sum "$src" 2>/dev/null | cut -c1-64)  (ของไฟล์จริง ก่อนซ่อนค่า)"; echo "# ---"; cat "$src"; } | ev_save "config/$n"
}
# ev_row FILE col1 col2 … : เพิ่มแถว TSV ใน evidence/FILE
ev_row()  { [ -n "$EVID" ] || return 0; local f="$EVID/$1"; shift; (IFS=$'\t'; echo "$*") | mask_text >> "$f"; }

# ---------- อ่านไฟล์ properties (key=value หรือ key value) ----------
prop_get() {
  local f="$1" k="$2" ke
  [ -r "$f" ] || return 1
  ke=$(printf '%s' "$k" | sed 's/[.[\*^$]/\\&/g')
  grep -E "^[[:space:]]*${ke}[[:space:]]*[=:[:space:]]" "$f" 2>/dev/null | tail -1 \
    | sed -E "s/^[[:space:]]*${ke}[[:space:]]*[=:]?[[:space:]]*//; s/[[:space:]]+$//"
}
is_secret_key() { local k="${1,,}"; k=${k//passthrough/}; echo "$k" | grep -qiE "$SECRET_WORD_RE"; }
# safe_val KEY VALUE : ค่าลับ → ปิดบางส่วน (+ sha256 8 ตัวแรก เมื่อยาว ≥16 ใช้เทียบว่าตรงกันทุกตัวอักษร)
safe_val() {
  if is_secret_key "$1"; then
    [ -z "$2" ] && { echo "(ว่าง)"; return; }
    local fp=""; [ "${#2}" -ge 16 ] && [ "$MASK_MODE" != "full" ] && fp=" sha256:$(printf '%s' "$2" | sha256sum | cut -c1-8)"
    echo "$(pmask "$2")$fp"
  else echo "$2"; fi
}
mask_url() { mask_text; }

count_in_file() { grep -ac -- "$2" "$1" 2>/dev/null || echo 0; }
match_expect()  { local got="$1" exp="$2"; if [ "$exp" = ">0" ]; then [ "${got:-0}" -gt 0 ] 2>/dev/null; else [ "$got" = "$exp" ]; fi; }

# ---------- สิทธิ์ไฟล์ ----------
# perm_check PATH OWNER SECRET(yes/no) WRITE(yes/no) [คำอธิบาย]
perm_check() {
  local p="$1" own="$2" sec="$3" wr="$4" desc="${5:-$1}" st u g m
  if [ ! -e "$p" ]; then ev_row permissions.tsv "$(date '+%F %T')" "$p" - - - - "ไม่พบ"; fail "ไม่พบ $desc" "$p"; return; fi
  st=$(stat -c '%U %G %a' "$p" 2>/dev/null); read -r u g m <<<"$st"
  local msg="$desc  ($u:$g $m)"
  local bad=""
  [ -n "$own" ] && [ "$u" != "$own" ] && bad="${bad}owner ไม่ใช่ $own ; "
  if [ "$sec" = "yes" ] && [ $(( 8#$m & 8#004 )) -ne 0 ]; then bad="${bad}มี secret แต่ผู้ใช้อื่นอ่านได้ (o+r) ; "; fi
  if [ "$wr" = "yes" ]; then
    if [ "$(id -un)" = "$own" ]; then [ -w "$p" ] || bad="${bad}$own เขียนไม่ได้ ; "
    elif [ "$u" = "$own" ] && [ $(( 8#$m & 8#200 )) -eq 0 ]; then bad="${bad}$own เขียนไม่ได้ ; "
    elif [ "$u" != "$own" ] && [ $(( 8#$m & 8#002 )) -eq 0 ]; then bad="${bad}$own อาจเขียนไม่ได้ (owner คนอื่น) ; "; fi
  fi
  ev_row permissions.tsv "$(date '+%F %T')" "$p" "$u" "$g" "$m" "$(stat -c '%F' "$p" 2>/dev/null)" "${bad:-OK}"
  if [ -z "$bad" ]; then pass "สิทธิ์ $msg"
  else warn "สิทธิ์ $msg" "$bad" "chown $own / chmod (ไฟล์ที่มี secret ควรเป็น 600 หรือ 640)"; fi
}

# ---------- URL ----------
extract_urls() {   # extract_urls FILE…  → รายการ URL (ซ่อน credential)
  grep -ahoE '(https?|jdbc:[a-z]+(:[a-z]+)?)://[^][:space:]"'"'"'<>,]+' "$@" 2>/dev/null | mask_url | sort -u
}
url_check() {      # url_check URL "คำอธิบาย" [warn = ต่อไม่ได้เป็นแค่ WARN]
  local u="$1" d="${2:-$1}" lvl="${3:-fail}" out code t
  [ "$NO_NET" = 1 ] && { skip "ไม่ทดสอบ (-n) : $d → $u"; ev_row urls_tested.tsv "$(date '+%F %T')" "$d" "$u" "-n" "-"; return; }
  have curl || { skip "ทดสอบ URL $u (ไม่มี curl)"; return; }
  local ef="${EVID:-/tmp}/.curl_err.$$" rc err
  out=$(curl -sSk -o /dev/null --connect-timeout 8 -m 15 -w '%{http_code} %{time_total}' "$u" 2>"$ef"); rc=$?
  err=$(head -1 "$ef" 2>/dev/null | cut -c1-160); rm -f "$ef"
  code=${out%% *}; t=${out#* }
  [ -n "$code" ] || { code=000; t="-"; }   # curl ไม่ตอบอะไรเลย = ถือว่าต่อไม่ได้
  ev_row urls_tested.tsv "$(date '+%F %T')" "$d" "$u" "$code" "${t}s" "curl rc=$rc" "$err"
  [ "$code" = 000 ] && [ -n "$err" ] && u="$u  ($err)"
  case "$code" in
    2??|3??) pass "$d ตอบ HTTP $code (${t}s)" "$u" ;;
    401|403) pass "$d ตอบ HTTP $code (${t}s — ต่อได้ ต้อง login)" "$u" ;;
    000)     if [ "$lvl" = warn ]; then warn "$d ต่อไม่ได้" "$u" "DNS / firewall / service ไม่รัน / certificate — ถ้า key นี้ไม่ได้ใช้บนเครื่องนี้ ข้ามได้"
             else fail "$d ต่อไม่ได้" "$u" "DNS / firewall / service ไม่รัน / certificate"; fi ;;
    *)       warn "$d ตอบ HTTP $code (${t}s)" "$u" "ดู log ของปลายทาง" ;;
  esac
}
tcp_check() {      # tcp_check HOST PORT "คำอธิบาย"  — เปิด TCP แล้วปิดทันที ไม่ส่งข้อมูล / ไม่ login
  [ "$NO_NET" = 1 ] && { skip "ไม่ทดสอบ (-n) : ${3:-} → $1:$2"; ev_row tcp_tested.tsv "$(date '+%F %T')" "${3:-}" "$1" "$2" "-n"; return; }
  local r=fail; timeout 6 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null && r=ok
  ev_row tcp_tested.tsv "$(date '+%F %T')" "${3:-}" "$1" "$2" "$r"
  if [ "$r" = ok ]; then pass "${3:-$1:$2} ต่อได้ ($1:$2)"
  else fail "${3:-$1:$2} ต่อไม่ได้ ($1:$2)" "" "firewall / DNS / ปลายทางปิด"; fi
}
port_listening() { ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$1\$"; }

# ---------- process ----------
proc_java_version() {   # proc_java_version PID
  local exe; exe=$(readlink "/proc/$1/exe" 2>/dev/null) || return 1
  "$exe" -version 2>&1 | head -1
}
# java_pids PATTERN : PID ของ process java ที่ cmdline ตรง PATTERN (ไม่นับ shell / grep / tail ที่มีข้อความเดียวกัน)
java_pids() {
  local p a0
  for p in $(pgrep -f -- "$1"); do
    [ "$p" = "$$" ] && continue
    a0=$(tr '\0' '\n' < "/proc/$p/cmdline" 2>/dev/null | head -1); a0=${a0%% *}
    [ "${a0##*/}" = java ] && echo "$p"
  done
}
proc_start() { ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//'; }
# proc_detach_check PID ชื่อ : process ผูกกับ terminal ไหม (ปิด session แล้ว process จะหยุด) — อ่าน /proc อย่างเดียว
proc_detach_check() {
  local p="$1" n="$2" out ign sys=""
  out=$(readlink "/proc/$p/fd/1" 2>/dev/null)
  ign=$(awk '/^SigIgn:/{print $2}' "/proc/$p/status" 2>/dev/null)
  have systemctl && sys=$(cat "/proc/$p/cgroup" 2>/dev/null | grep -oE '[^/]+\.service' | head -1)
  info "$n : stdout → ${out:-?} ; cgroup ${sys:-ไม่ใช่ systemd service}"
  case "$out" in
    /dev/pts/*|/dev/tty*)
      if [ -n "$ign" ] && [ $(( 16#$ign & 1 )) -eq 1 ]; then
        warn "$n เขียน log ออก terminal ($out) — ไม่มีไฟล์ log ให้ย้อนดู" "" "start ใหม่ด้วย nohup … >> <ไฟล์ log> 2>&1 &"
      else
        fail "$n ผูกกับ terminal ($out) — ปิดหน้าต่าง / หลุด session แล้ว process จะหยุด" "" "start ใหม่ด้วย nohup … >> <ไฟล์ log> 2>&1 & (หรือทำ systemd service)"
      fi ;;
    "") warn "อ่าน stdout ของ $n ไม่ได้ (คนละ user?)" ;;
    *) case "$sys" in ""|session-*|user@*) [ -n "$ign" ] && [ $(( 16#$ign & 1 )) -eq 0 ] && [ -z "$sys" ] && info "$n ไม่ได้ ignore SIGHUP (ไม่ได้ start ด้วย nohup) แต่ stdout ไม่ใช่ terminal";; esac ;;
  esac
}
proc_user()  { local u; u=$(ps -o user= -p "$1" 2>/dev/null | tr -d ' '); [ -n "$u" ] || u=$(stat -c %U "/proc/$1" 2>/dev/null); echo "$u"; }

# ---------- log : ช่วงตั้งแต่บรรทัดที่ตรงรูปแบบครั้งสุดท้าย ----------
# log_rot_file FILE PATTERN : ไฟล์ที่มี PATTERN ครั้งล่าสุด — ไฟล์ปัจจุบัน หรือไฟล์ที่ถูก rotate (.1 / -YYYYMMDD / .gz / catalina.YYYY-MM-DD.log)
log_rot_file() {
  local f="$1" pat="$2" c
  grep -q -- "$pat" "$f" 2>/dev/null && { echo "$f"; return 0; }
  for c in $(ls -1t "$f".* "$f"-* "$(dirname "$f")/$(basename "$f" .out)".*.log* 2>/dev/null); do
    [ "$c" = "$f" ] && continue
    zgrep -q -- "$pat" "$c" 2>/dev/null && { echo "$c"; return 0; }
  done
  return 1
}
log_since_last() {   # log_since_last FILE PATTERN [ย้อนกลับ N บรรทัด] — ตามไปไฟล์ที่ถูก rotate ถ้าไฟล์ปัจจุบันไม่มี PATTERN
  local f="$1" pat="$2" back="${3:-0}" l src x
  src=$(log_rot_file "$f" "$pat") || src="$f"
  l=$(zcat -f -- "$src" 2>/dev/null | grep -n -- "$pat" | tail -1 | cut -d: -f1)
  [ -z "$l" ] && l=1
  l=$(( l > back ? l - back : 1 ))
  {
    zcat -f -- "$src" 2>/dev/null | sed -n "${l},\$p"
    if [ "$src" != "$f" ]; then   # ไฟล์ที่ rotate หลังจากนั้น (เก่า → ใหม่) แล้วต่อด้วยไฟล์ปัจจุบัน
      for x in $(ls -1tr "$f".* "$f"-* "$(dirname "$f")/$(basename "$f" .out)".*.log* 2>/dev/null); do
        [ "$x" = "$src" ] || [ "$x" = "$f" ] && continue; [ "$x" -nt "$src" ] && zcat -f -- "$x" 2>/dev/null
      done
      cat -- "$f" 2>/dev/null
    fi
  } | head -n "${LOG_MAX_LINES:-300000}"   # จำกัดขนาดในหน่วยความจำ
}
