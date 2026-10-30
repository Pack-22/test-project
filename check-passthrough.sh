#!/usr/bin/env bash
# =============================================================================
#  check-passthrough.sh — ไล่ตรวจเส้นทาง Passthrough Authentication ทั้ง flow
#      ผู้ใช้ ─SSO─► Portal ─token─► CUBIKA ─TCP─► DB Proxy ─(Entra JWT + User Mapping)─► DWS
#
#  รันบนแต่ละเครื่องตามบทบาท (เครื่องเดียวมีหลายบทบาทได้ เช่น cbi-dev) :
#    agent    : เครื่องที่รัน DB Proxy (dataguard-proxy.jar / db-security-proxy-*.jar)
#    platform : เครื่องที่รัน CUBIKA (Tomcat) — เครื่องที่ต่อไป proxy
#    portal   : เครื่องที่รัน Data Service Portal (spwportal)
#
#  ถามก่อนเริ่ม : บทบาท (เดาจาก process / โฟลเดอร์ที่พบ), path ของ config / log, host:port ของ proxy,
#                 UPN ของผู้ทดสอบ (ใช้กรอง log เท่านั้น)
#  ตรวจ        : agent    — process / port / config ที่ใช้จริง (ค่าซ้ำ, auth.mode, db.user, Entra, usermapping,
#                              token ค่าตัวอย่าง, แก้ config หลัง start), DWS / Entra / CUBIKA ต่อได้, log
#                 platform — proxy host ชี้ตัวเองหรือไม่, IP ต้นทาง (สำหรับขอ firewall), ต่อ proxy ได้, log ดาวน์โหลด
#                 portal   — aad.proxy.scope, offline_access, key DATA-MARKET-ACCESS, ไฟล์ต้นทาง, log AADSTS
#
#  ใช้   : ./check-passthrough.sh        (ถาม)
#          ./check-passthrough.sh -y     (ไม่ถาม — ใช้ค่าที่เดาได้ / environment)
#          ./check-passthrough.sh -n     (ไม่เปิด connection ออกไปไหนเลย — ตรวจเฉพาะไฟล์ / process / log)
#  ผล   : <โฟลเดอร์ที่รันสคริปต์>/passthrough_<host>_<เวลา>/ (report.log, results.csv, summary.txt, evidence/)
#
#  ไม่มีผลกระทบกับระบบ :
#    - ไม่ stop / start / kill / แก้ไฟล์ใด ๆ ของระบบ ; ไม่ใช้ sudo
#    - ไม่ login DB / proxy / Entra : การทดสอบ TCP เปิดแล้วปิดทันทีโดยไม่ส่งข้อมูล
#      (ไม่นับเป็น login ที่ล้ม จึงไม่ทำให้บัญชีใน DWS ถูกล็อก)
#    - HTTP เป็น GET ไม่มี credential : กุญแจสาธารณะของ Entra และ endpoint ของ User Mapping (คาดหวัง 401/403)
#    - อ่าน log เฉพาะท้ายไฟล์ (LOG_TAIL บรรทัด, ค่าเริ่มต้น 200000)
#    - ค่าลับถูกปิดบางส่วนทั้งบนจอและในไฟล์ผล ; MASK_MODE=full = ซ่อนทั้งหมด
# =============================================================================
SCRIPT_DIR=$(dirname "$(readlink -f -- "$0")")
. "$SCRIPT_DIR/cbi-check-lib.sh" || { echo "ไม่พบ cbi-check-lib.sh ใน $SCRIPT_DIR"; exit 2; }
REPORT_DIR="${REPORT_DIR:-$PWD}"     # ผลการตรวจเก็บในโฟลเดอร์ที่รันสคริปต์
parse_common_args "$@"

LOG_TAIL="${LOG_TAIL:-200000}"
GUID_RE='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
MANUAL_CHECKS="Entra : แอปของ proxy → Expose an API = api://<client id ของ proxy> และมี scope
Entra : แอปของ portal → API permissions → permission ไปยังแอปของ proxy + Grant admin consent
CUBIKA : Settings → DB Proxy = host/port ของ proxy, สวิตช์ SSL ตรงกับ ssl.enabled ของ proxy → Test connection ผ่าน
CUBIKA : User Mappings มี UPN ของผู้ทดสอบ (ตรงตัวพิมพ์) → DB user ที่ login DWS ได้จริง และ Enabled
CUBIKA : collection ที่ทดสอบ = Passthrough Authentication, dataset อยู่บน datasource ที่ตั้งใน DB Proxy, คำขออนุมัติแล้ว
ผู้ทดสอบ logout แล้ว login portal ใหม่หลังแก้ Entra / portal แล้วลองดาวน์โหลด แล้วรันสคริปต์นี้ซ้ำทุกเครื่อง"

# ---------- เดาบทบาทของเครื่อง ----------
PXPID=""; PXCFG=""
while read -r p; do
  [ -z "$p" ] && continue
  c=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -oE -- '-Dproxy\.config=[^ ]+' | cut -d= -f2-)
  echo "$c" | grep -q "/dataguard/proxy/[^/]*/proxy.properties" && continue     # ข้าม Gateway ของ enforcer
  PXPID="$p"; PXCFG="$c"; break
done < <(java_pids "$PROXY_PAT")
TCPID=$(java_pids "catalina.base=" | head -1)
TC_DEF=$(tr '\0' ' ' < "/proc/$TCPID/cmdline" 2>/dev/null | grep -oE -- '-Dcatalina\.base=[^ ]+' | head -1 | cut -d= -f2-)
[ -n "$TC_DEF" ] || TC_DEF="/app/cbi/server/tomcat9"
DET=""
{ [ -n "$PXPID" ] || [ -f "$HOME/cbi/dataguard/proxy.properties" ]; } && DET="agent"
ls -d "$TC_DEF"/webapps/cubika*/WEB-INF >/dev/null 2>&1 && DET="${DET:+$DET,}platform"
[ -d "$TC_DEF/webapps/spwportal/WEB-INF" ] && DET="${DET:+$DET,}portal"

echo "=== ตรวจ Passthrough — ระบุค่า ==="
echo "บทบาทที่พบบนเครื่องนี้ : ${DET:-(ไม่พบ — ระบุเอง)}"
ask ROLES "ตรวจบทบาทไหน (agent,platform,portal คั่นด้วย ,)" "$DET" text
has_role() { case ",$ROLES," in *",$1,"*) return 0;; esac; return 1; }

if has_role agent; then
  ask PROXY_CONF "ไฟล์ proxy.properties ที่ proxy ใช้" "${PXCFG:-$HOME/cbi/dataguard/proxy.properties}" file
  # log ของโปรแกรม (ไม่ใช่ audit log) : stdout ของ process → โฟลเดอร์ที่ process รัน → โฟลเดอร์ agent ที่พบบ่อย
  PXCWD=""; DEF_LOG=""
  if [ -n "$PXPID" ]; then
    PXCWD=$(readlink "/proc/$PXPID/cwd" 2>/dev/null)
    DEF_LOG=$(readlink "/proc/$PXPID/fd/1" 2>/dev/null); case "$DEF_LOG" in /*) [ -f "$DEF_LOG" ] || DEF_LOG="";; *) DEF_LOG="";; esac
  fi
  [ -z "$DEF_LOG" ] && DEF_LOG=$(ls -1t ${PXCWD:+"$PXCWD"/*proxy*.log} "$HOME"/sw_install/agent-dataguard/*proxy*.log "$HOME"/*proxy*.log 2>/dev/null | grep -v -- '-audit' | head -1)
  ask PROXY_LOG "ไฟล์ log ของ proxy — log ของโปรแกรม ไม่ใช่ proxy-audit.log (ว่าง = ข้าม)" "$DEF_LOG" "file?"
  # audit log (บันทึก login ที่ถูกปฏิเสธ) : ตาม audit.log.path ใน config (ถ้าเป็น path สัมพัทธ์ = เทียบกับโฟลเดอร์ที่ proxy รัน)
  AUD=$(prop_get "$PROXY_CONF" audit.log.path 2>/dev/null)
  case "$AUD" in ""|/*) ;; *) AUD="${PXCWD:-$(dirname "$PROXY_LOG" 2>/dev/null)}/$AUD";; esac
  [ -f "$AUD" ] || AUD=$(ls -1t ${PXCWD:+"$PXCWD"/*audit*.log} "$HOME"/sw_install/agent-dataguard/*audit*.log 2>/dev/null | head -1)
  [ "$PROXY_LOG" = "$AUD" ] && echo "  (ไฟล์นี้เป็น audit log — สคริปต์จะสรุปให้ในหัวข้อ audit แยก)"
fi
if has_role platform || has_role portal; then
  ask TOMCAT_HOME "Tomcat home" "$TC_DEF" dir
fi
if has_role platform; then
  DEF_CTX=$(ls -1d "$TOMCAT_HOME"/webapps/cubika*/ 2>/dev/null | head -1 | xargs -r basename)
  ask CTX "ชื่อ context ของ CUBIKA" "${DEF_CTX:-cubika}" text
  echo "  (ดู Proxy host / port ได้ที่หน้า Data Guard → Settings → DB Proxy ของ CUBIKA)"
  while :; do
    ask PROXY_HOST "Proxy host ที่ตั้งใน CUBIKA — ชื่อเครื่องหรือ IP" "${PROXY_HOST:-}" text
    [[ "$PROXY_HOST" =~ ^[A-Za-z0-9._-]+$ ]] && break
    echo "  ค่าที่ใส่ไม่ใช่ชื่อเครื่อง / IP (เช่น 10.10.1.26 หรือ dev.cbi-platform.com)"; PROXY_HOST=""; ANSWERS=("${ANSWERS[@]:0:${#ANSWERS[@]}-1}")
    [ "$ASSUME_YES" = 1 ] && { echo "  (-y) PROXY_HOST ไม่ถูกต้อง"; exit 2; }
  done
  while :; do
    ask PROXY_PORT "Proxy port ที่ตั้งใน CUBIKA" "${PROXY_PORT:-15432}" text
    [[ "$PROXY_PORT" =~ ^[0-9]{1,5}$ ]] && break
    echo "  port ต้องเป็นตัวเลข"; PROXY_PORT=""; ANSWERS=("${ANSWERS[@]:0:${#ANSWERS[@]}-1}")
    [ "$ASSUME_YES" = 1 ] && { echo "  (-y) PROXY_PORT ไม่ถูกต้อง"; exit 2; }
  done
fi
if has_role portal; then
  ask PCTX "ชื่อ context ของ portal" "spwportal" text
  ask CONFIG_SRC "โฟลเดอร์ config ต้นทางของสคริปต์ deploy portal (ว่าง = ข้าม)" "" "dir?"
  DEF_CID=""; [ -r "${PROXY_CONF:-$HOME/cbi/dataguard/proxy.properties}" ] && DEF_CID=$(prop_get "${PROXY_CONF:-$HOME/cbi/dataguard/proxy.properties}" azure.entra.client.id)
  ask PROXY_CID "client id ของแอป proxy ใน Entra (ว่าง = ไม่เทียบ)" "$DEF_CID" "text?"
fi
ask TEST_UPN "UPN ของผู้ทดสอบ (ใช้กรอง log เท่านั้น ; ว่าง = ทุกคน)" "" "text?"

start_report "passthrough"
print_answers
info "บทบาทที่ตรวจ : $ROLES ; ทดสอบเครือข่าย : $([ "$NO_NET" = 1 ] && echo 'ไม่ (-n)' || echo 'ใช่ (TCP เปิด-ปิด / HTTP GET ไม่มี credential)')"

logtail() { tail -n "$LOG_TAIL" -- "$1" 2>/dev/null; }
upn_filter() { if [ -n "${TEST_UPN:-}" ]; then grep -iF -- "$TEST_UPN"; else cat; fi; }
local_ips() { ip -o -4 addr 2>/dev/null | awk '{print $4}' | cut -d/ -f1; echo 127.0.0.1; }
resolve4() { case "$1" in *[!0-9.]*) getent ahostsv4 "$1" 2>/dev/null | awk '{print $1}' | sort -u;; *) echo "$1";; esac; }

# =============================================================================
if has_role agent; then
P="$PROXY_CONF"
ev_conf "$P" proxy.properties

section "A1. DB Proxy : process / port"
if [ -n "$PXPID" ]; then
  pass "proxy รันอยู่ PID $PXPID (user $(proc_user "$PXPID"), start $(proc_start "$PXPID"))"
  proc_detach_check "$PXPID" "proxy"
  { echo "# PID $PXPID cwd=$(readlink /proc/$PXPID/cwd) stdout=$(readlink /proc/$PXPID/fd/1)"; tr '\0' '\n' < "/proc/$PXPID/cmdline"; } 2>&1 | ev_save process_proxy.txt
  [ -z "$PXCFG" ] || [ "$PXCFG" = "$P" ] && pass "process ใช้ config ไฟล์นี้" "${PXCFG:-(ไม่ระบุ -Dproxy.config — ใช้ค่า default)}" \
    || warn "process ใช้ config $PXCFG ไม่ใช่ $P" "" "แก้ไฟล์ที่ process ใช้จริง หรือ restart ด้วย -Dproxy.config ที่ถูก"
  st=$(date -d "$(proc_start "$PXPID")" +%s 2>/dev/null); mt=$(stat -c %Y "$P" 2>/dev/null)
  if [ -n "$st" ] && [ -n "$mt" ] && [ "$mt" -gt "$st" ]; then
    warn "proxy.properties ถูกแก้หลัง proxy start ($(date -d "@$mt" '+%F %T')) — ค่าใหม่ยังไม่มีผล" "" "restart proxy ด้วยคำสั่งเดิม"
  else pass "config ไม่ถูกแก้หลัง proxy start"; fi
else fail "ไม่พบ process ของ DB Proxy (รูปแบบชื่อ: $PROXY_PAT)" "" "start proxy ; ถ้าชื่อ jar ต่างจากนี้ ตั้ง PROXY_PAT='ชื่อ' แล้วรันใหม่"; fi
PGP=$(prop_get "$P" proxy.postgresql.port); PGP=${PGP:-15432}
L=$(ss -ltnp 2>/dev/null | awk -v p=":$PGP\$" '$4 ~ p')
ss -ltnp 2>/dev/null | ev_save ports_listen.txt
if [ -z "$L" ]; then fail "port $PGP (proxy.postgresql.port) ไม่ได้ listen" "" "proxy ไม่ได้ start / start ไม่สำเร็จ — ดู log"
else
  bind=$(echo "$L" | awk '{print $4}' | head -1)
  case "$bind" in 127.*|"[::1]"*) fail "port $PGP listen เฉพาะ $bind — เครื่องอื่นต่อไม่ได้" "" "ให้ proxy bind 0.0.0.0";;
                  *) pass "port $PGP listen ที่ $bind";; esac
  [ -n "$PXPID" ] && ! echo "$L" | grep -q "pid=$PXPID," && warn "port $PGP ไม่ใช่ของ PID $PXPID" "$(echo "$L" | grep -oE 'pid=[0-9]+' | head -1)" "port ชน / มี proxy อีกตัว"
fi

section "A2. DB Proxy : config ที่มีผลจริง (Java properties — บรรทัดสุดท้ายของ key ซ้ำมีผล)"
dups=$(grep -oE '^[[:space:]]*[A-Za-z0-9_.-]+[[:space:]]*[=:]' "$P" 2>/dev/null | sed -E 's/[[:space:]=:]//g' | sort | uniq -d)
for k in $dups; do
  vals=$(grep -E "^[[:space:]]*${k//./\\.}[[:space:]]*[=:]" "$P" | sed -E 's/^[^=:]*[=:][[:space:]]*//' | sort -u)
  nl=$(grep -nE "^[[:space:]]*${k//./\\.}[[:space:]]*[=:]" "$P" | cut -d: -f1 | tr '\n' ',' | sed 's/,$//')
  if [ "$(echo "$vals" | grep -c .)" -gt 1 ]; then
    if [ "$k" = security.auth.mode ]; then fail "key ซ้ำค่าไม่ตรงกัน : $k (บรรทัด $nl) — มีผลจริง = $(prop_get "$P" "$k")" "" "ลบให้เหลือบรรทัดเดียว แล้ว restart proxy"
    else warn "key ซ้ำค่าไม่ตรงกัน : $k (บรรทัด $nl) — มีผลจริง = $(safe_val "$k" "$(prop_get "$P" "$k")")" "" "ลบบรรทัดที่ไม่ใช้"; fi
  else info "key ซ้ำแต่ค่าเดียวกัน : $k (บรรทัด $nl)"; fi
done
[ -z "$dups" ] && pass "ไม่มี key ซ้ำ"
MODE=$(prop_get "$P" security.auth.mode)
case "$MODE" in
  mixed)       pass "security.auth.mode = mixed (รับ token ของ Entra และ user/password)";;
  entra_jwt)   pass "security.auth.mode = entra_jwt (รับเฉพาะ token ของ Entra)";;
  passthrough) fail "security.auth.mode = passthrough — ไม่รับ token ของ Entra" "" "Passthrough ของ Data Service ต้องเป็น mixed";;
  token)       fail "security.auth.mode = token — ใช้ได้แค่ security.tokens ไม่รับ token ของ Entra" "" "ตั้ง security.auth.mode=mixed (บรรทัดเดียว) แล้ว restart";;
  "")          warn "ไม่ได้ตั้ง security.auth.mode" "" "ตั้ง mixed ให้ชัด";;
  *)           warn "security.auth.mode = $MODE (ไม่รู้จัก)";;
esac
DBU=$(prop_get "$P" db.user); DBPW=$(prop_get "$P" db.password)
if [ "$MODE" != token ]; then
  [ -z "$DBU" ] && [ -z "$DBPW" ] && pass "db.user / db.password ว่าง (ใช้ login ของผู้ใช้แต่ละคน)" \
    || fail "db.user / db.password มีค่า ในโหมด $MODE" "db.user=${DBU:-(ว่าง)} ; db.password=$(safe_val password "$DBPW")" "ต้องว่าง — ไม่งั้น proxy ไม่ยอม start และทุกคนจะใช้บัญชีเดียว"
fi
info "db.type=$(prop_get "$P" db.type) db.host=$(prop_get "$P" db.host) db.port=$(prop_get "$P" db.port) db.ssl=$(prop_get "$P" db.ssl)"
TID=$(prop_get "$P" azure.entra.tenant.id); CID=$(prop_get "$P" azure.entra.client.id)
[[ "$TID" =~ $GUID_RE ]] && pass "azure.entra.tenant.id = $TID" || fail "azure.entra.tenant.id ไม่ใช่ GUID" "${TID:-(ว่าง)}" "ใส่ Directory (tenant) ID"
[[ "$CID" =~ $GUID_RE ]] && pass "azure.entra.client.id = $CID (audience ของ token ที่รับ)" || fail "azure.entra.client.id ไม่ใช่ GUID" "${CID:-(ว่าง)}" "ใส่ Application (client) ID ของแอป proxy"
UME=$(prop_get "$P" usermapping.enabled); UMU=$(prop_get "$P" usermapping.api.url); UMP=$(prop_get "$P" usermapping.endpoint.path)
[ "$UME" = true ] && pass "usermapping.enabled = true" || fail "usermapping.enabled = ${UME:-(ว่าง)}" "" "ตั้ง true — ไม่งั้น Entra JWT path ไม่ทำงาน"
UMEFF=""
if [ -z "$UMU" ]; then fail "usermapping.api.url ว่าง" "" "ใส่ https://<host CUBIKA>/<context>"
else
  case "$UMU" in */cubikai/*|*/cubikai) warn "usermapping.api.url มี /cubikai/ — context น่าจะผิด" "$UMU" "ปกติ = https://<host>/cubika";; esac
  if [ -n "$UMP" ] && [[ "$UMU" != *"$UMP" ]]; then UMEFF="${UMU%/}$UMP"; else UMEFF="$UMU"; fi
  info "User Mapping URL ที่ proxy เรียกจริง = $UMEFF  (api.url + endpoint.path)"
fi
[ -n "$(prop_get "$P" usermapping.api.token)" ] && info "ตั้งค่า usermapping.api.token แล้ว" || info "ไม่ได้ตั้ง usermapping.api.token (ถ้า sync ได้ 401 ให้เทียบกับเครื่องที่ใช้ได้)"
SSLE=$(prop_get "$P" ssl.enabled); info "ssl.enabled = ${SSLE:-false} → สวิตช์ 'Use SSL to the proxy' ใน CUBIKA ต้อง$([ "$SSLE" = true ] && echo 'เปิด' || echo 'ปิด')"
[ "$SSLE" = true ] && { ks=$(prop_get "$P" ssl.keystore.path); [ -f "$ks" ] && pass "ssl.keystore.path มีไฟล์" || fail "ssl.enabled=true แต่ไม่พบ keystore" "$ks"; }
AT=$(prop_get "$P" admin.token); TK=$(prop_get "$P" security.tokens)
[ "$(prop_get "$P" admin.enabled)" = true ] && case "$AT" in *change-me*|"") warn "admin.enabled=true แต่ admin.token เป็นค่าตัวอย่าง / ว่าง" "" "openssl rand -hex 32 ; จำกัด firewall port $(prop_get "$P" admin.port)";; esac
case "$TK" in *change-me*) if [ "$MODE" = token ] || [ "$MODE" = mixed ]; then warn "ค่าใน security.tokens ยังเป็นค่าตัวอย่างของโปรแกรม" "" "เปลี่ยนเป็นค่าสุ่ม หรือลบถ้าไม่ใช้";fi;; esac
POWN=$(proc_user "${PXPID:-0}"); [ -n "$POWN" ] || POWN=$(stat -c %U "$P" 2>/dev/null)
perm_check "$P" "$POWN" yes no "proxy.properties"

section "A3. DB Proxy : ต่อปลายทางได้ (ไม่ login)"
DH=$(prop_get "$P" db.host); DP=$(prop_get "$P" db.port)
[ -n "$DH" ] && tcp_check "$DH" "${DP:-5432}" "DWS / DB ปลายทาง"
[[ "$TID" =~ $GUID_RE ]] && url_check "https://login.microsoftonline.com/$TID/discovery/v2.0/keys" "กุญแจตรวจ token ของ Entra (JWKS)"
[ -n "$UMEFF" ] && url_check "$UMEFF" "User Mapping API ของ CUBIKA (คาด 401/403 เพราะไม่ส่ง token)"

section "A4. DB Proxy : log"
if [ -n "${PROXY_LOG:-}" ] && [ -r "$PROXY_LOG" ]; then
  LG=$(log_since_last "$PROXY_LOG" "Loading config from" 2 | tail -n "$LOG_TAIL")
  printf '%s\n' "$LG" | tail -n 20000 | ev_save proxy_since_last_start.log
  lc=$(echo "$LG" | grep -m1 "Loading config from" | sed 's/.*Loading config from:* *//')
  [ -n "$lc" ] && info "รอบ start ล่าสุดโหลด : $lc"
  echo "$LG" | grep -iE 'auth[._ ]mode|entra|jwt path|user.?mapping.*(enabled|disabled)|Listening|refuses to start' | head -8 | while IFS= read -r l; do info "  $(echo "$l" | cut -c1-200)"; done
  um=$(echo "$LG" | grep '\[user-mapping\]' | grep -E 'Sync complete|Sync failed|disabled' | tail -1)
  case "$um" in *"Sync complete"*) pass "user-mapping sync ล่าสุดสำเร็จ" "$(echo "$um" | cut -c1-200)";;
                *"Sync failed"*)   fail "user-mapping sync ล่าสุดล้ม" "$(echo "$um" | cut -c1-200)" "401 = ต้องใช้ usermapping.api.token ; 404 = URL ; timeout = เครือข่าย";;
                *) warn "ไม่พบผล user-mapping หลัง start" "" "usermapping.enabled / URL / proxy ยังไม่ได้ restart";; esac
  J=$(echo "$LG" | grep '\[entra-jwt\]' | upn_filter)
  info "entra-jwt หลัง start${TEST_UPN:+ (เฉพาะ $TEST_UPN)} : Accepted $(echo "$J" | grep -c Accepted) ; Rejected $(echo "$J" | grep -c Rejected)"
  rj=$(echo "$J" | grep Rejected | tail -1)
  [ -n "$rj" ] && warn "มี token ถูกปฏิเสธ (ล่าสุด)" "$(echo "$rj" | cut -c1-220)" "audience = client id ไม่ตรงกับ aad.proxy.scope ; signature = portal ส่ง token ของ Graph ; expired = login ใหม่"
  echo "$J" | ev_save proxy_entra_jwt.log
  er=$(echo "$LG" | grep -E 'SEVERE|ERROR|Exception' | grep -v 'Read timed out')
  [ -z "$er" ] && pass "ไม่มี SEVERE / ERROR หลัง start" || { warn "SEVERE/ERROR $(echo "$er" | grep -c .) บรรทัด"; echo "$er" | cut -c1-180 | sort | uniq -c | sort -rn | head -5 | while IFS= read -r l; do info "  $l"; done; }
else skip "log ของ proxy (ไม่ได้ระบุ / อ่านไม่ได้)"; fi
if [ -n "${AUD:-}" ] && [ -r "$AUD" ]; then
  AL=$(logtail "$AUD" | upn_filter)
  echo "$AL" | tail -n 5000 | ev_save proxy_audit_tail.log
  info "audit log : $AUD (แก้ล่าสุด $(stat -c %y "$AUD" | cut -d. -f1))"
  af=$(echo "$AL" | grep -c 'AUTH_FAILED'); jr=$(echo "$AL" | grep -ci 'Entra JWT rejected')
  info "audit : AUTH_FAILED $af ครั้ง (Entra JWT rejected $jr) ; ล่าสุด : $(echo "$AL" | grep AUTH_FAILED | tail -1 | cut -c1-160)"
  [ "$jr" -gt 0 ] && echo "$AL" | grep -i 'Entra JWT rejected' | grep -oE 'from [0-9.]+' | cut -d' ' -f2 | sort | uniq -c | sort -rn | head -3 | while read -r n ip; do info "  จาก $ip : ถูกปฏิเสธ $n ครั้ง"; done
fi
fi

# =============================================================================
if has_role platform; then
section "C. CUBIKA → DB Proxy"
if [ -z "$PROXY_HOST" ]; then fail "ไม่ได้ระบุ Proxy host"
else
  pips=$(resolve4 "$PROXY_HOST"); lips=" $(local_ips | tr '\n' ' ') "
  info "$PROXY_HOST → ${pips:-resolve ไม่ได้}"
  self=no; for ip in $pips; do case "$lips" in *" $ip "*) self=yes;; esac; done
  if [ -z "$pips" ]; then fail "resolve $PROXY_HOST ไม่ได้" "" "ใช้ IP ของเครื่อง proxy"
  elif [ "$self" = yes ] && ! has_role agent; then fail "Proxy host ชี้มาที่เครื่อง CUBIKA เอง ($PROXY_HOST)" "" "ใส่ IP / ชื่อของเครื่องที่รัน DB Proxy"
  else pass "Proxy host ไม่ได้ชี้มาที่เครื่องนี้ (หรือเครื่องนี้รัน proxy เอง)"; fi
  for ip in $pips; do src=$(ip route get "$ip" 2>/dev/null | grep -oE 'src [0-9.]+' | cut -d' ' -f2); [ -n "$src" ] && info "IP ต้นทางที่ใช้ไปหา $ip = $src (ใช้เป็น Source ตอนขอ firewall)"; done
  if [ -r "${PROXY_CONF:-}" ]; then
    pp=$(prop_get "$PROXY_CONF" proxy.postgresql.port)
    [ -n "$pp" ] && { [ "$pp" = "$PROXY_PORT" ] && pass "Proxy port ใน CUBIKA ($PROXY_PORT) ตรงกับ proxy.postgresql.port" \
      || fail "Proxy port ใน CUBIKA ($PROXY_PORT) ไม่ตรงกับ proxy.postgresql.port ($pp) ของ proxy เครื่องนี้" "" "แก้ช่อง Proxy port ใน CUBIKA ให้ตรง (หรือมี proxy อีกตัวที่ port $PROXY_PORT — ตรวจ ss -ltnp)"; }
  fi
  tcp_check "$PROXY_HOST" "${PROXY_PORT:-15432}" "CUBIKA → DB Proxy"
fi
section "G. log การดาวน์โหลดของ CUBIKA (catalina.out ท้าย $LOG_TAIL บรรทัด)"
CAT="$TOMCAT_HOME/logs/catalina.out"
if [ -r "$CAT" ]; then
  D=$(logtail "$CAT" | grep -E '\[DataServiceDownload\]|testDbProxy|UNREACHABLE' | upn_filter)
  echo "$D" | ev_save platform_download.log
  info "DataServiceDownload${TEST_UPN:+ ($TEST_UPN)} : $(echo "$D" | grep -c 'DataServiceDownload') บรรทัด ; แยก route : $(echo "$D" | grep -oE 'route=[a-z]+' | sort | uniq -c | awk '{printf "%s×%s ",$2,$1}')"
  info "passthrough ที่ดาวน์โหลดสำเร็จ (result=200) = $(echo "$D" | grep 'route=passthrough' | grep -c 'result=200') ครั้ง ; ล่าสุด : $(echo "$D" | grep 'route=passthrough' | tail -1 | awk '{print $1" "$2}')"
  for pat in "no proxy token" "credential_rejected" "session_expired" "UNREACHABLE|ConnectException|Connection refused" "entitlement check answered"; do
    c=$(echo "$D" | grep -cE "$pat")
    [ "$c" -eq 0 ] && pass "ไม่มี \"$pat\"" || warn "\"$pat\" $c ครั้ง" "$(echo "$D" | grep -E "$pat" | tail -1 | cut -c1-220)" \
      "no proxy token/session_expired = portal/Entra ; credential_rejected = proxy (ดู log proxy) ; UNREACHABLE = host/firewall ; entitlement = คำขอ/key"
  done
  echo "$D" | grep 'route=passthrough' | tail -3 | while IFS= read -r l; do info "  $(echo "$l" | cut -c1-200)"; done
else skip "อ่าน $CAT ไม่ได้"; fi
fi

# =============================================================================
if has_role portal; then
section "F. Portal : config"
PP="$TOMCAT_HOME/webapps/$PCTX/WEB-INF/classes/prop"; A="$PP/authentication.properties"; AP="$PP/app.properties"
ev_conf "$A" portal_authentication.properties; ev_conf "$AP" portal_app.properties
if [ -r "$A" ]; then
  SC=$(prop_get "$A" aad.proxy.scope); AS=$(prop_get "$A" aad.scopes); AU=$(prop_get "$A" aad.authority)
  info "aad.clientId = $(prop_get "$A" aad.clientId) ; aad.authority = $AU"
  if [[ "$SC" =~ ^api://[0-9a-fA-F-]{36}/\.default$ ]]; then
    pass "aad.proxy.scope = $SC"
    sid=${SC#api://}; sid=${sid%%/*}
    [ -n "${PROXY_CID:-}" ] && { [ "$sid" = "$PROXY_CID" ] && pass "aad.proxy.scope ตรงกับ client id ของ proxy" || fail "aad.proxy.scope ($sid) ไม่ตรงกับ client id ของ proxy ($PROXY_CID)" "" "แก้ให้ตรง — ไม่งั้น proxy ปฏิเสธ (audience)"; }
  elif [ -z "$SC" ]; then fail "aad.proxy.scope ว่าง" "" "ใส่ api://<client id ของ proxy>/.default แล้ว restart portal"
  else fail "aad.proxy.scope รูปแบบไม่ถูก" "$SC" "ต้องเป็น api://<GUID>/.default"; fi
  echo "$AS" | grep -qw offline_access && pass "aad.scopes มี offline_access" || fail "aad.scopes ไม่มี offline_access" "$AS" "ไม่มี refresh token → session_expired"
  [ -n "${TID:-}" ] && { echo "$AU" | grep -q "$TID" && pass "aad.authority เป็น tenant เดียวกับ proxy" || warn "aad.authority ไม่มี tenant $TID ของ proxy" "$AU"; }
else fail "อ่าน $A ไม่ได้"; fi
if [ -r "$AP" ]; then
  KU=$(prop_get "$AP" app.datamarket.access.key.uuid); KS=$(prop_get "$AP" app.datamarket.access.key.secret); DMC=$(prop_get "$AP" app.datamarket.context)
  [ -n "$KU" ] && pass "app.datamarket.access.key.uuid = $KU" || fail "app.datamarket.access.key.uuid ว่าง"
  [ -n "$KS" ] && pass "app.datamarket.access.key.secret = $(safe_val key.secret "$KS")" || fail "app.datamarket.access.key.secret ว่าง"
  tr -d '\r' < "$AP" | grep -E '^app\.datamarket\.access\.key\.(uuid|secret)=.*[ \t]$' >/dev/null && warn "key มีช่องว่างท้ายบรรทัด (นับเป็นส่วนหนึ่งของค่า)" "" "ถ้า portal ใช้งานได้อยู่แล้ว ข้ามได้ ; ถ้า entitlement 401/403 ให้ลบช่องว่าง"
  grep -q $'\r' "$AP" && info "app.properties ของ portal ขึ้นบรรทัดแบบ Windows (CRLF) — Java อ่านได้ปกติ"
  info "app.datamarket.context = $DMC"
  [ -n "$DMC" ] && url_check "$DMC/" "CUBIKA ที่ portal เรียก"
fi
if [ -n "${CONFIG_SRC:-}" ]; then
  SA="$CONFIG_SRC/WEB-INF/classes/prop/authentication.properties"; SAP="$CONFIG_SRC/WEB-INF/classes/prop/app.properties"
  for kv in "$SA|aad.proxy.scope|$A" "$SA|aad.scopes|$A" "$SAP|app.datamarket.access.key.uuid|$AP" "$SAP|app.datamarket.access.key.secret|$AP"; do
    sf=${kv%%|*}; r=${kv#*|}; k=${r%%|*}; df=${r#*|}
    [ "$(prop_get "$sf" "$k")" = "$(prop_get "$df" "$k")" ] && pass "ไฟล์ต้นทาง $k ตรงกับที่ใช้จริง" || fail "ไฟล์ต้นทาง $k ไม่ตรงกับที่ใช้จริง" "" "แก้ไฟล์ต้นทางด้วย ไม่งั้น deploy รอบหน้าค่าจะเปลี่ยน"
  done
fi
section "F. Portal : log (catalina.out ท้าย $LOG_TAIL บรรทัด)"
CAT="$TOMCAT_HOME/logs/catalina.out"
if [ -r "$CAT" ]; then
  E=$(logtail "$CAT" | grep -E 'AADSTS|no proxy token|session_expired|MsalInteractionRequired|acquireProxyToken' | upn_filter)
  echo "$E" | ev_save portal_aad.log
  codes=$(echo "$E" | grep -oE 'AADSTS[0-9]+' | sort | uniq -c | sort -rn | awk '{printf "%s×%s ",$2,$1}')
  [ -z "$codes" ] && pass "ไม่มี AADSTS error" || warn "AADSTS : $codes" "$(echo "$E" | grep AADSTS | tail -1 | cut -c1-220)" \
    "65001 = ยังไม่ได้ admin consent ; 500011 = ไม่มี Application ID URI ; 70011 = scope ผิด"
  c=$(echo "$E" | grep -c 'no proxy token'); [ "$c" -eq 0 ] && pass "ไม่มี \"no proxy token\"" || warn "\"no proxy token\" $c ครั้ง" "" "consent / aad.proxy.scope / ผู้ใช้ต้อง login ใหม่"
else skip "อ่าน $CAT ไม่ได้"; fi
fi

end_report
