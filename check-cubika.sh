#!/usr/bin/env bash
# =============================================================================
#  check-cubika.sh — ตรวจความพร้อมของ CUBIKA platform (WAR บน Tomcat)
#
#  ถามก่อนเริ่ม : Tomcat home, ชื่อ context, path ของ WAR ที่วาง, WAR ต้นฉบับ (ถ้ามี),
#                 โฟลเดอร์ config ต้นทาง, user ที่รัน Tomcat, URL ที่ผู้ใช้เข้า
#  ตรวจ        : hostname/เวลา, process + Java, สิทธิ์ไฟล์, sha256, เวอร์ชันของ build,
#                 config ที่ใช้งานจริง + URL ที่ใช้จริง, catalina.out รอบ start ล่าสุด, ทดสอบ URL
#
#  ใช้   : ./check-cubika.sh          (ถามทีละข้อ — กด Enter = ใช้ค่าในวงเล็บ)
#          ./check-cubika.sh -y       (ไม่ถาม ใช้ค่า default / environment)
#  ผล   : <โฟลเดอร์ที่รันสคริปต์>/cubika_<host>_<เวลา>/  (report.log, results.csv, summary.txt, evidence/ …)
#  อ่านอย่างเดียว — ไม่หยุด/start/แก้ไฟล์ใด ๆ
# =============================================================================
SCRIPT_DIR=$(dirname "$(readlink -f -- "$0")")
. "$SCRIPT_DIR/cbi-check-lib.sh" || { echo "ไม่พบ cbi-check-lib.sh ใน $SCRIPT_DIR"; exit 2; }
REPORT_DIR="${REPORT_DIR:-$PWD}"     # ผลการตรวจเก็บในโฟลเดอร์ที่รันสคริปต์
parse_common_args "$@"

# ---------- ค่าที่คาดหวังของ release (แก้เมื่อ release เปลี่ยน) ----------
EXPECT_WAR_SHA="${EXPECT_WAR_SHA:-af219d8eb1517ea92addba40e5c98c292d91a880283d80068c6fced8028e98f2}"   # sha ของไฟล์ต้นฉบับ RC07
EXPECT_CHANGELOG_FILE="${EXPECT_CHANGELOG_FILE:-WEB-INF/classes/prop/changelog-9.0.1.txt}"
EXPECT_CHANGELOG_TEXT="${EXPECT_CHANGELOG_TEXT:-RC07 - 2026-10-28}"
EXPECT_CONNECTOR="${EXPECT_CONNECTOR:-cbi-connector-2.10.2-0503.jar}"
EXPECT_CONNECTOR_SHA="${EXPECT_CONNECTOR_SHA:-c1b739de6d10d7f1729cc4d03f30bc1f9b49543a27d4dfcfbd82d454d033cdba}"
MARKERS=(
  "WEB-INF/classes/com/ddlg/cubika/dataguard/logic/DataguardUserDeployLogic.class|Earlier in this deploy the role|>0"
  "WEB-INF/classes/com/ddlg/cubika/dataguard/util/DataguardPasswordRules.class|must not contain a backslash|>0"
  "dataguard/scripts/dgMaskingMethod.js|bannerNotRunningLead|2"
  "dataguard/styles/dg-masking-method.css|mm-banner-btn|1"
  "WEB-INF/classes/com/ddlg/cubika/web/api/datamarket/DataMarketAPI.class|DS-COLLECTION|>0"
  "dataguard/scripts/CB330201_v9.js|minTableWidth|2"
  "WEB-INF/classes/com/ddlg/cubika/dataguard/logic/DataguardAccountAdminLogic.class|orgIdOf|>0"
)
CONFIG_FILES=( "WEB-INF/classes/hibernate.properties" "WEB-INF/classes/system.properties"
               "WEB-INF/classes/prop/app.properties" "WEB-INF/classes/prop/authentication.properties" "WEB-INF/classes/prop/ui.properties" )
MANUAL_CHECKS="หน้าเวอร์ชัน (กระดิ่ง) : Build / Revision / Status ตรง release
Data Guard → Deploy Queue : last reported ไม่กี่วินาที
Masking Policy ของ datasource แบบ Gateway : banner ส้ม/แดงตามสถานะจริง"

# ---------- ถาม path ----------
echo "=== ตรวจ CUBIKA platform — ระบุ path (Enter = ใช้ค่าที่แสดง) ==="
ask TOMCAT_HOME   "Tomcat home"                                          "/app/cbi/server/tomcat9" dir
ask CTX           "ชื่อ context ของ CUBIKA"                                "cubika_9x0" text
ask WAR_DEPLOYED  "WAR ที่วางใน webapps"                                    "$TOMCAT_HOME/webapps/$CTX.war" file
ask WAR_ORIGINAL  "WAR ต้นฉบับของ release (ว่าง = ข้าม)"                     "" "file?"
ask CONFIG_SRC    "โฟลเดอร์ config ต้นทางที่สคริปต์ deploy copy มา (ว่าง = ข้าม)" "" "dir?"
ask SVC_USER      "user ที่รัน Tomcat"                                      "$(stat -c %U "$TOMCAT_HOME/webapps" 2>/dev/null || echo cbiaccess)" text
ask BASE_URL      "URL ที่ผู้ใช้เข้า CUBIKA (เช่น https://host/$CTX ; ว่าง = ข้าม)" "" "text?"
W="$TOMCAT_HOME/webapps/$CTX"
CATALINA="$TOMCAT_HOME/logs/catalina.out"

start_report "cubika"
print_answers

# -----------------------------------------------------------------------------
section "1. Process / Java / service"
TPID=$(java_pids "catalina.base=$TOMCAT_HOME" | head -1)
if [ -n "$TPID" ]; then
  pass "Tomcat รันอยู่ PID $TPID (user $(proc_user "$TPID"), start $(proc_start "$TPID"))"
  [ "$(proc_user "$TPID")" = "$SVC_USER" ] || warn "Tomcat รันด้วย user $(proc_user "$TPID") ไม่ใช่ $SVC_USER" "" "ไฟล์ที่ Tomcat สร้างจะเป็นของ user อื่น — ตรวจ service / คำสั่ง start"
  info "Java ของ Tomcat : $(proc_java_version "$TPID")"
else fail "Tomcat ไม่รัน" "" "systemctl status tomcat9 / tail $CATALINA"; fi
ev_cmd process_java.txt ps -o pid,ppid,user,lstart,etime,rss,args -C java
[ -n "$TPID" ] && tr '\0' '\n' < "/proc/$TPID/cmdline" 2>&1 | ev_save process_tomcat_cmdline.txt
if have systemctl; then
  s=$(systemctl list-units --type=service --all 2>/dev/null | grep -iE "tomcat" | awk '{print $1" "$3" "$4}' | head -3)
  [ -n "$s" ] && info "systemd : $s" || info "ไม่พบ systemd service ของ Tomcat (start ด้วย startup.sh)"
  ev_cmd systemd_tomcat.txt systemctl status tomcat9 --no-pager -n 0
fi

# -----------------------------------------------------------------------------
section "2. สิทธิ์ไฟล์ / โฟลเดอร์"
perm_check "$TOMCAT_HOME/webapps" "$SVC_USER" no  yes "webapps/"
perm_check "$WAR_DEPLOYED"        ""          no  no  "WAR ที่วาง"
perm_check "$W"                   "$SVC_USER" no  yes "โฟลเดอร์ $CTX ที่ explode"
for d in work temp logs; do perm_check "$TOMCAT_HOME/$d" "$SVC_USER" no yes "$d/"; done
perm_check "$CATALINA"            ""          no  no  "catalina.out"
for f in "${CONFIG_FILES[@]}"; do [ -e "$W/$f" ] && perm_check "$W/$f" "$SVC_USER" yes no "$f"; done
# ไฟล์ที่ไม่ควรอยู่ใน webapps (Tomcat จะ deploy เป็นแอปเพิ่ม)
odd=$(ls -1 "$TOMCAT_HOME/webapps" 2>/dev/null | grep -vE '^(ROOT|docs|examples|manager|host-manager)$' \
      | grep -E '\.(bk|bak|old|orig|zip)|\.war\..+|_bk|backup' | tr '\n' ' ')
[ -z "$odd" ] && pass "ไม่มีไฟล์ backup ค้างใน webapps/" || warn "พบไฟล์ backup ใน webapps/" "$odd" "ย้ายไป /app/cbi/backup — ไฟล์ .war หรือโฟลเดอร์จะถูก deploy เป็นแอปเพิ่ม"
info "webapps/ : $(ls -1 "$TOMCAT_HOME/webapps" 2>/dev/null | tr '\n' ' ')"
ev_cmd ls_webapps.txt ls -la --time-style=+%F_%T "$TOMCAT_HOME/webapps"
ev_cmd ls_tomcat.txt ls -la --time-style=+%F_%T "$TOMCAT_HOME" "$TOMCAT_HOME/work" "$TOMCAT_HOME/temp" "$TOMCAT_HOME/logs"
ev_cmd disk.txt df -h "$TOMCAT_HOME" "$(dirname "$W")"
for d in "$TOMCAT_HOME" "$(dirname "$W")"; do
  use=$(df -P "$d" | awk 'NR==2{gsub("%","",$5); print $5}'); av=$(df -Ph "$d" | awk 'NR==2{print $4}')
  if [ "$use" -ge 95 ]; then fail "ดิสก์ $d ใช้ ${use}% (เหลือ $av)" "" "WAR ~620 MB + backup ต่อรอบ"
  elif [ "$use" -ge 80 ]; then warn "ดิสก์ $d ใช้ ${use}% (เหลือ $av)"; else pass "ดิสก์ $d ใช้ ${use}% (เหลือ $av)"; fi
  break
done

# -----------------------------------------------------------------------------
section "3. WAR / เวอร์ชันของ build"
info "WAR ที่วาง : $(ls -l --time-style='+%F %T' "$WAR_DEPLOYED" 2>/dev/null | awk '{print $6" "$7"  "$5" bytes"}')"
info "sha256 WAR ที่วาง : $(sha256sum "$WAR_DEPLOYED" 2>/dev/null | cut -c1-64)  (ใส่ config ของ env แล้ว จึงไม่ตรงกับต้นฉบับ = ปกติ)"
if [ -n "$WAR_ORIGINAL" ]; then
  s=$(sha256sum "$WAR_ORIGINAL" | cut -c1-64)
  [ "$s" = "$EXPECT_WAR_SHA" ] && pass "sha256 WAR ต้นฉบับตรงกับ release" "$s" || fail "sha256 WAR ต้นฉบับไม่ตรง" "$s (คาดหวัง $EXPECT_WAR_SHA)" "ไฟล์อัปโหลดไม่ครบ / ไม่ใช่ release นี้"
fi
if [ -d "$W" ]; then
  info "โฟลเดอร์ $CTX สร้างเมื่อ : $(stat -c '%y' "$W" | cut -d. -f1)"
  n=$(count_in_file "$W/$EXPECT_CHANGELOG_FILE" "$EXPECT_CHANGELOG_TEXT")
  [ "$n" -ge 1 ] && pass "changelog มี \"$EXPECT_CHANGELOG_TEXT\"" || fail "changelog ไม่มี \"$EXPECT_CHANGELOG_TEXT\"" "" "WAR ที่ explode ไม่ใช่ release นี้"
  mapfile -t CONN < <(ls "$W/WEB-INF/lib" 2>/dev/null | grep -E '^cbi-connector-[0-9]')
  if [ "${#CONN[@]}" -eq 1 ] && [ "${CONN[0]}" = "$EXPECT_CONNECTOR" ]; then
    pass "connector ใน WAR : ${CONN[0]} (ตัวเดียว)"
    s=$(sha256sum "$W/WEB-INF/lib/$EXPECT_CONNECTOR" | cut -c1-64)
    [ "$s" = "$EXPECT_CONNECTOR_SHA" ] && pass "sha256 connector ตรง" || fail "sha256 connector ไม่ตรง" "$s"
  else fail "connector ใน WAR ไม่ถูกต้อง (คาดหวัง $EXPECT_CONNECTOR ตัวเดียว)" "${CONN[*]:-ไม่มี}" "หลายตัว = โฟลเดอร์เดิมไม่ถูกลบก่อน explode ; ผิดเวอร์ชัน = WAR ไม่ใช่ release นี้"; fi
  ev_cmd changelog.txt head -60 "$W/$EXPECT_CHANGELOG_FILE"
  ev_cmd ls_web-inf_lib.txt ls -la --time-style=+%F_%T "$W/WEB-INF/lib"
  { echo "# $(date '+%F %T') sha256"; sha256sum "$WAR_DEPLOYED" ${WAR_ORIGINAL:+"$WAR_ORIGINAL"} "$W"/WEB-INF/lib/cbi-connector-*.jar 2>&1; } | ev_save sha256.txt
  for m in "${MARKERS[@]}"; do
    f=${m%%|*}; r=${m#*|}; pat=${r%|*}; exp=${r##*|}
    ev_row markers.tsv "$f" "$pat" "$exp" "$(count_in_file "$W/$f" "$pat")"
    [ -e "$W/$f" ] || { fail "ไม่พบ $f" "" "WAR ไม่ครบ / ไม่ใช่ release นี้"; continue; }
    n=$(count_in_file "$W/$f" "$pat")
    match_expect "$n" "$exp" && pass "$(basename "$f") : \"$pat\" = $n" || fail "$(basename "$f") : \"$pat\" = $n (คาด $exp)" "" "WAR ไม่ใช่ release นี้"
  done
else fail "ไม่พบโฟลเดอร์ $W" "" "WAR ยังไม่ explode / context ผิด"; fi

# -----------------------------------------------------------------------------
section "4. Config ที่ใช้งานจริง + URL ที่ใช้จริง"
H="$W/WEB-INF/classes/hibernate.properties"
if [ -r "$H" ]; then
  url=$(prop_get "$H" hibernate.connection.url); usr=$(prop_get "$H" hibernate.connection.username); ddl=$(prop_get "$H" hibernate.hbm2ddl.auto)
  info "hibernate.connection.url      = $(echo "$url" | mask_url)"
  info "hibernate.connection.username = $usr"
  info "hibernate.connection.password = $(safe_val password "$(prop_get "$H" hibernate.connection.password)")"
  info "hibernate.hbm2ddl.auto        = ${ddl:-(ไม่ได้ตั้ง)}"
  if echo "$url" | grep -qE 'localhost/cubika(\?|$)' || [ "$usr" = "root" ]; then
    fail "hibernate ยังเป็นค่า default ของ build (localhost/cubika / root)" "" "copy hibernate.properties ของ environment แล้ว restart"
  else pass "hibernate ชี้ DB ของ environment"; fi
  [ "$ddl" = "update" ] || warn "hbm2ddl.auto ไม่ใช่ update" "${ddl:-(ไม่ได้ตั้ง)}" "คอลัมน์ใหม่ของ release จะไม่ถูกสร้างเอง"
  dbhp=$(echo "$url" | sed -nE 's#jdbc:[a-z]+://([^/:?]+)(:([0-9]+))?.*#\1 \3#p'); read -r dh dp <<<"$dbhp"
  if [ -n "$dh" ]; then dp=${dp:-3306}
    # ดู connection ที่ Tomcat เปิดอยู่แล้ว (ไม่เปิด connection ใหม่ — MySQL นับ connection ที่ไม่ login เป็น error และอาจ block host)
    ips=$(case "$dh" in *[!0-9.]*) getent ahostsv4 "$dh" 2>/dev/null | awk '{print $1}' | sort -u;; *) echo "$dh";; esac; [ "$dh" = localhost ] && echo 127.0.0.1)
    nc=0; for ip in $ips; do n=$(ss -Htn state established 2>/dev/null | awk '{print $4}' | sed 's/^\[::ffff://; s/\]//' | grep -cxF "$ip:$dp"); nc=$((nc+n)); done
    ev_cmd db_connections.txt ss -tnp state established "( dport = :$dp )"
    if [ "$nc" -gt 0 ]; then pass "มี connection ไป DB $dh:$dp อยู่ $nc เส้น (Tomcat ต่อ DB ได้)"
    elif [ -n "$TPID" ]; then fail "Tomcat รันอยู่แต่ไม่มี connection ไป DB $dh:$dp" "" "ดู catalina.out (Access denied / Communications link failure) / firewall"
    else skip "connection ไป DB (Tomcat ไม่รัน)"; fi
  fi
else fail "อ่าน $H ไม่ได้" "" "webapp ยังไม่ explode / สิทธิ์"; fi
for f in "${CONFIG_FILES[@]}"; do ev_conf "$W/$f" "deployed_$(basename "$f")"; [ -n "$CONFIG_SRC" ] && ev_conf "$CONFIG_SRC/$f" "source_$(basename "$f")"; done
for f in "${CONFIG_FILES[@]}"; do [ -r "$W/$f" ] && extract_urls "$W/$f" | sed "s#^#$(basename "$f")\t#"; done | ev_save urls_in_config.tsv
[ -n "$CONFIG_SRC" ] && for f in "${CONFIG_FILES[@]}"; do [ -r "$CONFIG_SRC/$f" ] && diff "$CONFIG_SRC/$f" "$W/$f"; done 2>&1 | ev_save config_diff_source_vs_deployed.txt
echo "       URL ทั้งหมดที่อยู่ใน config ของ $CTX (ซ่อน credential):"
for f in "${CONFIG_FILES[@]}"; do
  [ -r "$W/$f" ] || continue
  extract_urls "$W/$f" | sed "s#^#         $(basename "$f") : #"
done
if [ -n "$CONFIG_SRC" ]; then
  for f in "${CONFIG_FILES[@]}"; do
    [ -r "$CONFIG_SRC/$f" ] || continue
    diff -q "$W/$f" "$CONFIG_SRC/$f" >/dev/null 2>&1 && pass "$f ตรงกับไฟล์ต้นทาง" || warn "$f ต่างจากไฟล์ต้นทาง" "" "deploy ครั้งหน้าจะถูกทับด้วย $CONFIG_SRC/$f"
  done
  [ -n "$WAR_ORIGINAL" ] && have unzip && for f in "${CONFIG_FILES[@]}"; do
    [ -r "$CONFIG_SRC/$f" ] || continue
    newk=$(comm -23 <(unzip -p "$WAR_ORIGINAL" "$f" 2>/dev/null | grep -oE '^[[:space:]]*[A-Za-z0-9_.-]+' | sed 's/^ *//' | sort -u) \
                    <(grep -oE '^[[:space:]]*[A-Za-z0-9_.-]+' "$CONFIG_SRC/$f" | sed 's/^ *//' | sort -u) | tr '\n' ' ')
    [ -z "$newk" ] && pass "$f : ไม่มี key ใหม่ใน release ที่ไฟล์ต้นทางขาด" || warn "$f : release มี key ที่ไฟล์ต้นทางไม่มี" "$newk" "เติม key เหล่านี้ในไฟล์ต้นทางถ้าจำเป็น (ถาม dev)"
  done
fi

# -----------------------------------------------------------------------------
section "5. catalina.out — รอบ start ล่าสุด"
if [ -r "$CATALINA" ]; then
  info "catalina.out : $(ls -lh --time-style='+%F %T' "$CATALINA" | awk '{print $5", แก้ล่าสุด "$6" "$7}')"
  LOGP=$(log_since_last "$CATALINA" "Starting service \[Catalina\]")
  printf '%s\n' "$LOGP" | tail -n 20000 | ev_save catalina_since_last_start.log
  printf '%s\n' "$LOGP" | grep -E "Exception|SEVERE|ERROR" | ev_save catalina_errors_since_last_start.log
  st=$(echo "$LOGP" | head -1 | awk '{print $1" "$2}')
  up=$(echo "$LOGP" | grep -m1 "Server startup in" | grep -oE '\[[0-9]+\] milliseconds')
  [ -n "$up" ] && pass "start เมื่อ $st ; startup $up" || fail "ยังไม่มี \"Server startup in\" หลัง $st" "" "รอแล้วรันใหม่ ; เกิน 5 นาที ดู tail -200"
  sc=$(echo "$LOGP" | grep -m1 "\[DataguardPolicy\] schema check")
  case "$sc" in *"schema check OK"*) pass "Data Guard schema check OK";;
               "") fail "ไม่พบ [DataguardPolicy] schema check" "" "แอปยัง start ไม่เสร็จ / ต่อ DB ไม่ได้";;
               *) fail "schema check ไม่ผ่าน" "$sc" "DB ยังไม่ได้รัน SQL ของ DEV05 / ต่อ DB ผิดตัว";; esac
  PAT='SCHEMA CHECK FAILED|JasperException|Unable to compile class for JSP|ClassNotFoundException|NoClassDefFoundError|NoSuchMethodError|Unknown ordinal value|Access denied for user|Unknown database|Communications link failure'
  e=$(echo "$LOGP" | grep -cE "$PAT")
  [ "$e" -eq 0 ] && pass "ไม่มี error ร้ายแรงตอน start" || fail "error ร้ายแรง $e บรรทัด" "$(echo "$LOGP" | grep -m3 -E "$PAT" | cut -c1-200)" \
    "JasperException=ลบ work/ ; ClassNotFound/NoSuchMethod=WAR ไม่ครบ/jar ซ้ำ ; Access denied/Unknown database=hibernate.properties"
  k=$(echo "$LOGP" | grep -c "Specified key was too long")
  info "Specified key was too long = $k ครั้ง (ของเดิม ~93 บน cbi-dev — ถ้ามากขึ้นจากรอบก่อนให้ส่ง dev)"
  x=$(echo "$LOGP" | grep -E "Exception|SEVERE" | grep -vc "Specified key was too long")
  info "Exception/SEVERE อื่นหลัง start = $x บรรทัด"
  echo "$LOGP" | grep -E "Exception|SEVERE" | grep -v "Specified key was too long" | cut -c1-180 | sort | uniq -c | sort -rn | head -5 | sed 's/^/         /'
else fail "อ่าน $CATALINA ไม่ได้" "" "สิทธิ์ไฟล์"; fi

# -----------------------------------------------------------------------------
section "6. ทดสอบ URL"
if [ -n "$BASE_URL" ]; then
  url_check "$BASE_URL/" "CUBIKA ($BASE_URL)"
  url_check "$BASE_URL/authentication/login.action" "หน้า login"
  h=$(echo "$BASE_URL" | sed -E 's#^[a-z]+://([^/:]+).*#\1#')
  have getent && info "$h resolve → $(getent ahostsv4 "$h" | awk '{print $1}' | sort -u | tr '\n' ' ')"
else skip "ทดสอบ URL (ไม่ได้ระบุ)"; fi
ev_cmd ports_listen.txt ss -ltnp
lp=$(ss -ltnp 2>/dev/null | grep "pid=$TPID," | awk '{print $4}' | sed 's/.*://' | sort -un | tr '\n' ' ')
info "port ที่ Tomcat listen : ${lp:-(อ่านไม่ได้ — ลองรันด้วย user เดียวกับ Tomcat หรือ sudo)}"

end_report
