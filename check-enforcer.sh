#!/usr/bin/env bash
# =============================================================================
#  check-enforcer.sh — ตรวจ Policy enforcer (Data Guard agent) และ Data Guard Gateway ที่ enforcer เปิด
#
#  ถามก่อนเริ่ม : โฟลเดอร์ที่วาง jar ของ enforcer, ชื่อ jar ที่คาดหวัง, cbi.home (~/cbi), ไฟล์ log,
#                 user ที่รัน, โดเมนที่ผู้ใช้ใช้ (ตรวจ advertisedHost)
#  ตรวจ        : hostname/เวลา, process ตัวเดียว + Java + cwd, sha256 + marker ใน jar, สิทธิ์ไฟล์,
#                 enforcer.properties, datastore ที่ serve + URL ของ catalog, log รอบ start ล่าสุด,
#                 pending-jobs / dead, Gateway (ลูก / กำพร้า / port), advertisedHost
#
#  ใช้   : ./check-enforcer.sh   |  ./check-enforcer.sh -y
#  ผล   : <โฟลเดอร์ที่รันสคริปต์>/enforcer_<host>_<เวลา>/  (report.log, results.csv, summary.txt, evidence/ …)
# =============================================================================
SCRIPT_DIR=$(dirname "$(readlink -f -- "$0")")
. "$SCRIPT_DIR/cbi-check-lib.sh" || { echo "ไม่พบ cbi-check-lib.sh ใน $SCRIPT_DIR"; exit 2; }
REPORT_DIR="${REPORT_DIR:-$PWD}"     # ผลการตรวจเก็บในโฟลเดอร์ที่รันสคริปต์
parse_common_args "$@"

EXPECT_JAR_SHA="${EXPECT_JAR_SHA:-7c4d4cf302ef49d905ca869f4738917e66857c0c86aed88d6de26d11b025dfb4}"
EXPECT_SETTINGS="${EXPECT_SETTINGS:-11}"
PROPS_EXPECT=( "dataguard.masking.dialect=auto" "dataguard.ddl.lock.wait.seconds=30" "dataguard.ddl.lock.retry.minutes=60" )
MARKERS=(
  "com/ddlg/cbi/connect/adapter/PgAnonMaskingSql.class|notOwner|1"
  "com/ddlg/cbi/connect/adapter/PgAnonMaskingSql.class|gucRefused|1"
  "com/ddlg/cbi/connect/adapter/PgAnonMaskingSql.class|maySetGuc|0"
  "com/cbi/agent/dataguard/proxy/ProxyDeployer.class|does reach this host|1"
)
MANUAL_CHECKS="Data Guard → Deploy Queue : Policy enforcer last reported ไม่กี่วินาที ; ไม่มี Applying ค้าง
Resource Policies → Verify Now 1 policy ของแต่ละ datastore
ยืนยันกับ QA ว่าไม่มี enforcer บนเครื่องอื่นชี้ datastore เดียวกัน"

echo "=== ตรวจ Policy enforcer — ระบุ path (Enter = ใช้ค่าที่แสดง) ==="
RUNPID=$(java_pids "dataguard-policy-enforcer" | head -1)
DEF_DIR=$(readlink "/proc/$RUNPID/cwd" 2>/dev/null || echo "$HOME/sw_install/agent-dataguard")
DEF_JAR=$(tr '\0' '\n' < "/proc/$RUNPID/cmdline" 2>/dev/null | grep -m1 'dataguard-policy-enforcer.*\.jar' | xargs -r basename)
ask AGENT_DIR "โฟลเดอร์ที่วาง jar ของ enforcer"          "$DEF_DIR" dir
ask JAR_NAME  "ชื่อ jar ที่ต้องรัน (release นี้)"           "${DEF_JAR:-dataguard-policy-enforcer-1.6.0-0150-SNAPSHOT.jar}" text
ask CBI_HOME  "cbi.home ของ agent"                          "$HOME/cbi" dir
DEF_LOG=$(readlink "/proc/$RUNPID/fd/1" 2>/dev/null); case "$DEF_LOG" in /*) ;; *) DEF_LOG="$AGENT_DIR/enforcer.log";; esac
ask ENF_LOG   "ไฟล์ log ของ enforcer"                       "$DEF_LOG" "file?"
ask SVC_USER  "user ที่รัน enforcer"                        "$(stat -c %U "$CBI_HOME" 2>/dev/null || id -un)" text
ask PUBLIC_HOST "โดเมนที่ผู้ใช้ใช้ / endpoint ของ Gateway (ว่าง = ข้าม)" "" "text?"
JAR="$AGENT_DIR/$JAR_NAME"; EP="$CBI_HOME/dataguard/enforcer.properties"; AP="$CBI_HOME/app.properties"

start_report "enforcer"
print_answers

# -----------------------------------------------------------------------------
section "1. Process / Java / service"
mapfile -t PIDS < <(java_pids "dataguard-policy-enforcer")
EPID=""
if [ "${#PIDS[@]}" -eq 0 ]; then fail "enforcer ไม่รัน" "" "tail $ENF_LOG แล้ว start (ควรเป็น systemd service)"
else
  [ "${#PIDS[@]}" -eq 1 ] && pass "enforcer รันอยู่ตัวเดียว" || fail "enforcer รัน ${#PIDS[@]} ตัว (ต้องมีตัวเดียวต่อ datastore)" "${PIDS[*]}" "kill -INT ตัวเก่า"
  for p in "${PIDS[@]}"; do
    j=$(tr '\0' '\n' < "/proc/$p/cmdline" | grep -m1 'dataguard-policy-enforcer.*\.jar'); c=$(readlink "/proc/$p/cwd")
    info "PID $p : user $(proc_user "$p") ; start $(proc_start "$p") ; cwd $c ; jar $j ; PPID $(ps -o ppid= -p "$p" | tr -d ' ')"
    info "         Java : $(proc_java_version "$p")"
    [ "$(basename "$j")" = "$JAR_NAME" ] && EPID="$p"
  done
  [ -n "$EPID" ] && pass "รัน $JAR_NAME (PID $EPID)" || fail "ไม่มี process ที่รัน $JAR_NAME" "" "ยังไม่ได้เปลี่ยน jar / start ผิดไฟล์"
  [ -n "$EPID" ] && [ "$(proc_user "$EPID")" != "$SVC_USER" ] && warn "enforcer รันด้วย user $(proc_user "$EPID") ไม่ใช่ $SVC_USER"
  [ -n "$EPID" ] && [ "$(readlink "/proc/$EPID/cwd")" != "$AGENT_DIR" ] && warn "enforcer รันจากโฟลเดอร์ $(readlink "/proc/$EPID/cwd") ไม่ใช่ $AGENT_DIR"
fi
ev_cmd process_java.txt ps -o pid,ppid,user,lstart,etime,rss,args -C java
for p in "${PIDS[@]}"; do { echo "# PID $p cwd=$(readlink /proc/$p/cwd) stdout=$(readlink /proc/$p/fd/1)"; tr '\0' '\n' < "/proc/$p/cmdline"; } 2>&1 | ev_save "process_enforcer_$p.txt"; done
if have systemctl; then
  s=$(systemctl list-units --type=service --all 2>/dev/null | grep -iE "enforcer|dataguard" | awk '{print $1" "$3" "$4}')
  [ -n "$s" ] && info "systemd : $s" || warn "ไม่ได้รันเป็น systemd service" "" "ถ้า process ถูก kill จะไม่ start เอง (เคยหายกลางคืน 27-ต.ค.) — แนะนำทำ service + Restart=on-failure"
fi

# -----------------------------------------------------------------------------
section "2. jar ของ release"
if [ -r "$JAR" ]; then
  info "jar : $(ls -l --time-style='+%F %T' "$JAR" | awk '{print $6" "$7"  "$5" bytes"}')"
  s=$(sha256sum "$JAR" | cut -c1-64)
  [ "$s" = "$EXPECT_JAR_SHA" ] && pass "sha256 jar ตรงกับ release" || fail "sha256 jar ไม่ตรง" "$s (คาดหวัง $EXPECT_JAR_SHA)" "ไฟล์อัปโหลดไม่ครบ / ไม่ใช่ release นี้"
  if have unzip; then for m in "${MARKERS[@]}"; do c=${m%%|*}; r=${m#*|}; pat=${r%|*}; exp=${r##*|}
    n=$(unzip -p "$JAR" "$c" 2>/dev/null | grep -ac -- "$pat")
    match_expect "$n" "$exp" && pass "$(basename "$c") : \"$pat\" = $n" || fail "$(basename "$c") : \"$pat\" = $n (คาด $exp)" "" "jar ไม่ใช่ release นี้"; done; fi
  { echo "# $(date '+%F %T') sha256"; sha256sum "$AGENT_DIR"/*.jar 2>&1; } | ev_save sha256.txt
  for m in "${MARKERS[@]}"; do c=${m%%|*}; r=${m#*|}; pat=${r%|*}; ev_row markers.tsv "$c" "$pat" "${r##*|}" "$(unzip -p "$JAR" "$c" 2>/dev/null | grep -ac -- "$pat")"; done
  ev_cmd ls_agent_dir.txt ls -la --time-style=+%F_%T "$AGENT_DIR"
  info "jar อื่นในโฟลเดอร์ : $(ls -1 "$AGENT_DIR"/dataguard-policy-enforcer-*.jar 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
else fail "ไม่พบ $JAR"; fi

# -----------------------------------------------------------------------------
section "3. สิทธิ์ไฟล์ / โฟลเดอร์"
perm_check "$AGENT_DIR" "$SVC_USER" no yes "โฟลเดอร์ agent"
perm_check "$CBI_HOME" "$SVC_USER" no yes "cbi.home"
perm_check "$EP" "$SVC_USER" yes yes "enforcer.properties (enforcer เขียน key ที่ขาดเอง)"
perm_check "$AP" "$SVC_USER" yes no "app.properties (การเชื่อมต่อ catalog)"
[ -d "$CBI_HOME/cred" ] && perm_check "$CBI_HOME/cred" "$SVC_USER" yes yes "cred/ (credential เข้ารหัส)"
perm_check "$CBI_HOME/dataguard/pending-jobs" "$SVC_USER" no yes "pending-jobs/"
[ -d "$CBI_HOME/dataconnector/policycached" ] && perm_check "$CBI_HOME/dataconnector/policycached" "$SVC_USER" no yes "policycached/ (ledger)"
[ -n "$ENF_LOG" ] && perm_check "$ENF_LOG" "$SVC_USER" no yes "log ของ enforcer"
ev_cmd ls_cbi_home.txt ls -laR --time-style=+%F_%T "$CBI_HOME/dataguard"
ev_cmd disk.txt df -h "$CBI_HOME" "$AGENT_DIR"
use=$(df -P "$CBI_HOME" | awk 'NR==2{gsub("%","",$5);print $5}')
[ "$use" -lt 90 ] && pass "ดิสก์ของ cbi.home ใช้ ${use}%" || fail "ดิสก์ของ cbi.home ใช้ ${use}%" "" "ดิสก์เต็ม = ledger / journal บันทึกไม่ได้"

# -----------------------------------------------------------------------------
section "4. config : enforcer.properties / app.properties"
for kv in "${PROPS_EXPECT[@]}"; do k=${kv%%=*}; e=${kv#*=}; v=$(prop_get "$EP" "$k")
  [ "$v" = "$e" ] && pass "$k = $v" || fail "$k = ${v:-(ไม่มี)} (คาดหวัง $e)" "" "แก้แล้ว restart ; retry.minutes ≠ 60 มักค้างจากการทดสอบของ QA"; done
ev_conf "$EP" enforcer.properties; ev_conf "$AP" app.properties
extract_urls "$AP" "$EP" | ev_save urls_in_config.txt
ADV=$(prop_get "$EP" dataguard.proxy.advertisedHost); info "dataguard.proxy.advertisedHost = ${ADV:-(ไม่ได้ตั้ง)}"
nk=$(grep -cE '^[[:space:]]*dataguard\.' "$EP" 2>/dev/null); info "จำนวน key dataguard.* ใน enforcer.properties = $nk"
DSL=$(prop_get "$AP" datacatalog.datastore); DSN=$(echo "$DSL" | tr ',' '\n' | grep -c .)
[ "$DSN" -gt 0 ] && pass "datacatalog.datastore = $DSN ตัว" "$DSL" || fail "ไม่มี datacatalog.datastore" "" "enforcer จะไม่ serve datastore ใด"
echo "       URL ที่ agent ใช้ (app.properties / enforcer.properties — ซ่อน credential):"
extract_urls "$AP" "$EP" | sed 's/^/         /'
for u in $(extract_urls "$AP" | grep -E '^https?://' | head -3); do url_check "$u" "catalog URL ที่ agent เรียก"; done

# -----------------------------------------------------------------------------
section "5. log ของ enforcer — รอบ start ล่าสุด"
if [ -r "$ENF_LOG" ]; then
  info "log : $(ls -lh --time-style='+%F %T' "$ENF_LOG" | awk '{print $5", แก้ล่าสุด "$6" "$7}')"
  LOGP=$(log_since_last "$ENF_LOG" "\[policy-sync\] agent" 40)
  printf '%s\n' "$LOGP" | tail -n 20000 | ev_save enforcer_since_last_start.log
  printf '%s\n' "$LOGP" | grep -E "ERROR|Exception|WARN|UnservedGroup" | ev_save enforcer_errors_since_last_start.log
  tail -n 300 "$ENF_LOG" | ev_save enforcer_tail300.log
  ag=$(echo "$LOGP" | grep -m1 "\[policy-sync\] agent")
  [ -n "$ag" ] && pass "$ag" || warn "ไม่พบบรรทัด [policy-sync] agent" "" "log อาจอยู่ไฟล์อื่น / enforcer เวอร์ชันเก่า"
  [ -n "$EPID" ] && ! echo "$ag" | grep -q "pid $EPID " && warn "บรรทัด agent ล่าสุดไม่ใช่ PID $EPID" "" "log นี้อาจไม่ใช่ของ process ที่รันอยู่"
  cf=$(echo "$LOGP" | grep "\[config\].*enforcer.properties --" | tail -1)
  case "$cf" in *"all $EXPECT_SETTINGS settings present"*) pass "[config] all $EXPECT_SETTINGS settings present";;
                *added*) warn "[config] เพิ่ม key ที่ขาดให้เอง" "$cf" "ปกติสำหรับ start ครั้งแรกของ build ใหม่";;
                *"could not write"*) fail "[config] เขียน enforcer.properties ไม่ได้" "$cf" "สิทธิ์ไฟล์ / ดิสก์";;
                *) warn "ไม่พบบรรทัด [config]";; esac
  cs=$(echo "$LOGP" | grep -c "\[cred-store\] bootstrap resolved datastore")
  [ "$cs" -eq "$DSN" ] && [ "$cs" -gt 0 ] && pass "[cred-store] resolve ครบ $cs/$DSN" || fail "[cred-store] resolve $cs/$DSN" "" "id ไม่มีใน catalog / ต่อ catalog ไม่ได้"
  echo "$LOGP" | grep "\[cred-store\] bootstrap resolved datastore" | sed -E 's/.*resolved datastore/         datastore/'
  for id in $(echo "$DSL" | tr ',' ' '); do echo "$LOGP" | grep -q "resolved datastore $id" || fail "datastore $id ไม่ถูก resolve"; done
  er=$(echo "$LOGP" | grep -E "ERROR|Exception|ClassNotFound|NoSuchMethodError|NoClassDefFound" | grep -v UnservedGroup)
  [ -z "$er" ] && pass "ไม่มี ERROR / Exception" || { warn "ERROR/Exception $(echo "$er" | grep -c .) บรรทัด" "" "relation does not exist=ตารางถูกลบ ; is locked by=session ถือตาราง (DWS) ; cannot mask=สิทธิ์ login (DBA)"; echo "$er" | cut -c1-200 | sort | uniq -c | sort -rn | head -5 | sed 's/^/         /'; }
  ug=$(echo "$LOGP" | grep -oE "Datastore id '[^']+'" | sort -u | tr '\n' ' ')
  [ -z "$ug" ] && pass "ไม่มีงานของ datastore ที่ไม่ได้ serve" || warn "มีงานของ datastore ที่ enforcer นี้ไม่ serve" "$ug" "เพิ่ม id ใน datacatalog.datastore ของ enforcer ที่ควร serve (ตัวเดียว)"
  info "รอบ policy-sync ล่าสุด : $(echo "$LOGP" | grep -E "\[policy-sync\] (cycle|tick)" | tail -1 | cut -c1-160)"
  la=$(stat -c %Y "$ENF_LOG"); age=$(( $(date +%s) - la ))
  [ "$age" -lt 600 ] && pass "log มีการเขียนเมื่อ $age วินาทีก่อน" || warn "log ไม่ถูกเขียนมา $age วินาที" "" "enforcer อาจค้าง / เขียน log ไปไฟล์อื่น"
else skip "log (อ่าน $ENF_LOG ไม่ได้)"; fi

# -----------------------------------------------------------------------------
section "6. งานค้าง (pending-jobs)"
PJ="$CBI_HOME/dataguard/pending-jobs"
if [ -d "$PJ" ]; then
  pn=$(find "$PJ" -maxdepth 1 -name 'job-*.json' 2>/dev/null | wc -l); dn=$(find "$PJ/dead" -name 'job-*.json' 2>/dev/null | wc -l)
  dt=$(find "$PJ/dead" -name 'job-*.json' -newermt "$(date +%F)" 2>/dev/null | wc -l)
  ev_cmd pending_jobs_ls.txt ls -la --time-style=+%F_%T "$PJ" "$PJ/dead"
  [ -f "$PJ/.vendor-gate-v2" ] && pass "มี .vendor-gate-v2 (ห้ามลบ)" || warn "ไม่มี .vendor-gate-v2"
  [ "$pn" -eq 0 ] && pass "ไม่มีงานค้าง" || warn "งานค้าง $pn งาน" "" "ดู Deploy Queue / log enforcer"
  info "งานใน dead/ ทั้งหมด $dn งาน (วันนี้ $dt งาน)"
  [ "$dt" -gt 0 ] && warn "มีงานเข้า dead/ วันนี้ $dt งาน" "$(ls -t "$PJ"/dead/job-*.json 2>/dev/null | head -3 | xargs -n1 basename | tr '\n' ' ')" "ดูเหตุผลใน log (UnservedGroup / attempt หมด) — ห้ามลบไฟล์เอง"
else warn "ไม่พบ $PJ"; fi

# -----------------------------------------------------------------------------
section "7. Data Guard Gateway (process ลูกของ enforcer)"
GW=0
while read -r pid ppid; do
  [ -z "$pid" ] && continue
  cfg=$(tr '\0' ' ' < "/proc/$pid/cmdline" | grep -oE -- '-Dproxy\.config=[^ ]+' | cut -d= -f2-)
  echo "$cfg" | grep -q "/dataguard/proxy/[^/]*/proxy.properties" || continue
  GW=$((GW+1)); id=$(echo "$cfg" | sed -E 's#.*/proxy/([^/]+)/proxy.properties#\1#')
  ports=$(ss -ltnp 2>/dev/null | grep "pid=$pid," | awk '{print $4}' | sed 's/.*://' | sort -un | tr '\n' ' ')
  if [ "$ppid" = "1" ]; then fail "Gateway $id (PID $pid) เป็นกำพร้า (PPID=1)" "" "kill $pid แล้ว restart enforcer"
  elif [ -n "$EPID" ] && [ "$ppid" != "$EPID" ]; then warn "Gateway $id (PID $pid) ไม่ใช่ลูกของ enforcer $EPID (PPID $ppid)"
  else pass "Gateway $id (PID $pid) เป็นลูกของ enforcer ; listen: ${ports:-ไม่มี}"; fi
  [ -z "$ports" ] && warn "Gateway $id ไม่ได้ listen" "" "ดู log enforcer ช่วง deploy Gateway"
  perm_check "$cfg" "$SVC_USER" yes no "config ของ Gateway $id"
  ev_conf "$cfg" "gateway_${id}_proxy.properties"
  ev_row gateways.tsv "$id" "$pid" "$ppid" "${ports:-}" "$cfg"
  for k in proxy.mysql.port proxy.postgresql.port proxy.sqlserver.port db.host db.port; do v=$(prop_get "$cfg" "$k"); [ -n "$v" ] && info "         $k = $v"; done
done < <(ps -eo pid=,ppid=,args= | grep "[d]b-security-proxy" | awk '{print $1,$2}')
info "จำนวน Gateway ที่รันอยู่ : $GW"
ev_cmd ports_listen.txt ss -ltnp

# -----------------------------------------------------------------------------
section "8. โดเมน / advertisedHost"
if [ -n "$PUBLIC_HOST" ] && have getent; then
  rip=$(getent ahostsv4 "$PUBLIC_HOST" | awk '{print $1}' | sort -u | tr '\n' ' ')
  lips=" $(ip -o -4 addr 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | tr '\n' ' ') "
  loc=no; for ip in $rip; do case "$ip" in 127.*) loc=yes;; esac; case "$lips" in *" $ip "*) loc=yes;; esac; done
  info "$PUBLIC_HOST → ${rip:-resolve ไม่ได้} ; IP เครื่อง:$lips"
  ev_cmd dns_public_host.txt getent ahosts "$PUBLIC_HOST"
  if [ -z "$rip" ]; then fail "resolve $PUBLIC_HOST ไม่ได้"
  elif [ "$loc" = yes ]; then pass "$PUBLIC_HOST resolve มาที่เครื่องนี้ — ไม่ต้องตั้ง advertisedHost"
  elif [ "$ADV" = "$PUBLIC_HOST" ]; then pass "$PUBLIC_HOST เป็น IP ภายนอก และตั้ง advertisedHost แล้ว"
  else fail "$PUBLIC_HOST เป็น IP ภายนอก แต่ advertisedHost = ${ADV:-(ไม่ได้ตั้ง)}" "" "ตั้ง dataguard.proxy.advertisedHost=$PUBLIC_HOST แล้ว restart — ไม่งั้น Deploy Gateway ล้ม"; fi
else skip "advertisedHost (ไม่ได้ระบุโดเมน)"; fi

end_report
