## 5. ติดตั้ง & ตั้งค่า Tomcat 9 (โหลดจากเว็บ apache) [Critical]

> 💡 แอปรองรับ **Tomcat 9** — ติดตั้งจาก tarball ของ apache โดยตรง (ไม่ใช้ apt) เพื่อคุมเวอร์ชันเอง

### 5.1 ติดตั้ง Java + สร้าง user

```bash
sudo apt install -y default-jre
java -version                        # ตรวจว่า Java ลงแล้ว (Tomcat 9 ต้องการ Java 8 ขึ้นไป)
readlink -f $(which java)            # หา path จริงของ Java ไว้ตั้ง JAVA_HOME ในขั้น 5.6
sudo useradd --system --home-dir /opt/tomcat --shell /usr/sbin/nologin tomcat
```
> ⚠️ **ตรวจ JAVA_HOME:** path ของ Java ต่างกันตามเวอร์ชัน (เช่น `/usr/lib/jvm/java-21-openjdk-amd64`) — จดค่าจาก `readlink` ข้างบน เอาไปใส่ใน systemd unit (5.6) อย่าใช้ค่าตายตัวโดยไม่ตรวจ

### 5.2 ดาวน์โหลด Tomcat 9 จากเว็บ apache

เช็กเวอร์ชันล่าสุดของสาย 9 ที่ https://tomcat.apache.org/download-90.cgi แล้วแทน `VER` ด้วยเลขจริง
```bash
cd /tmp
VER=9.0.98                           # ← แก้เป็นเวอร์ชันล่าสุดของสาย 9.0.x
wget https://dlcdn.apache.org/tomcat/tomcat-9/v${VER}/bin/apache-tomcat-${VER}.tar.gz
# ตรวจความถูกต้องของไฟล์ (กันโหลดมาไม่ครบ/โดนสลับ):
wget https://downloads.apache.org/tomcat/tomcat-9/v${VER}/bin/apache-tomcat-${VER}.tar.gz.sha512
sha512sum -c apache-tomcat-${VER}.tar.gz.sha512
sudo mkdir -p /opt/tomcat
sudo tar xzf apache-tomcat-${VER}.tar.gz -C /opt/tomcat --strip-components=1
sudo chown -R tomcat:tomcat /opt/tomcat
```
> 💡 `--strip-components=1` = แตกไฟล์โดยตัดโฟลเดอร์ชั้นบนสุดออก ให้ไฟล์ไปอยู่ `/opt/tomcat` ตรงๆ ไม่ซ้อนเป็น `/opt/tomcat/apache-tomcat-9.x.x/`

### 5.3 ลบ default app ที่ไม่ใช้

```bash
sudo rm -rf /opt/tomcat/webapps/{examples,docs,ROOT,host-manager,manager}
```
> 💡 **อธิบาย:** พวก examples/docs มีช่องโหว่เก่าและเปิดข้อมูลเวอร์ชัน · ลบ manager/host-manager เพราะเรา deploy แบบ file-drop ไม่ใช้ (ดู 5.5) — ทุกอันที่ลบ = ลด attack surface

### 5.4 แก้ `server.xml` (`/opt/tomcat/conf/server.xml`)

- **ปิด/ลบ AJP connector** `<Connector port="8009" ... />` — ป้องกัน **Ghostcat (CVE-2020-1938)** ที่อ่านไฟล์ในแอปได้ผ่าน AJP · ถ้าไม่ได้ใช้ AJP ลบทิ้งเลย
- **bind HTTP ที่ localhost** `<Connector port="8080" address="127.0.0.1" ... />` — ให้เฉพาะ Nginx ในเครื่องต่อได้ ภายนอกต่อ 8080 ตรงไม่ได้
- **ปิด shutdown port** ตั้ง `<Server port="-1" ...>` — ปิดช่องสั่ง shutdown ผ่าน port
- **ซ่อน version** เพิ่มใน `<Host>`: `<Valve className="org.apache.catalina.valves.ErrorReportValve" showServerInfo="false" showReport="false"/>` — หน้า error ไม่โชว์เวอร์ชัน Tomcat

### 5.5 Manager / tomcat-users.xml — ไม่ใช้

deploy ด้วยวิธี file-drop (ดูหัวข้อ 7) จึง **ไม่เปิด manager webapp และไม่ตั้งบัญชีใน tomcat-users.xml** (ลบ manager ออกแล้วใน 5.3) — บัญชี manager เป็นเป้าโจมตียอดนิยม ตัดทิ้งเลยปลอดภัยกว่า

### 5.6 สิทธิ์ไฟล์ + systemd service

รันด้วย user `tomcat` ไม่ใช่ root:
```bash
sudo chmod -R o-rwx /opt/tomcat/conf      # ปิดไม่ให้ "คนอื่น" อ่าน config (มีรหัส/ค่าลับ)
```
สร้าง `/etc/systemd/system/tomcat.service` — คำอธิบายอยู่ในคอมเมนต์แต่ละบรรทัด (แก้ `JAVA_HOME` ให้ตรงค่าจาก 5.1):
```ini
[Unit]
Description=Apache Tomcat 9
# รอให้ network พร้อมก่อนค่อยสตาร์ท
After=network.target

[Service]
# startup.sh fork เป็น background แล้ว parent ออก → ให้ systemd ตาม PID จากไฟล์ (CATALINA_PID)
Type=forking
# รันด้วยบัญชี tomcat (nologin) ไม่ใช่ root — โดนเจาะก็ได้สิทธิ์แค่ tomcat
User=tomcat
Group=tomcat
# ชี้ Java ที่ใช้รัน — ต้องตรงกับค่าจาก `readlink` ใน 5.1
Environment=JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
# โฟลเดอร์ติดตั้ง Tomcat
Environment=CATALINA_HOME=/opt/tomcat
# ไฟล์เก็บ PID — จำเป็นสำหรับ Type=forking ให้ systemd ตาม/สั่ง stop ถูกตัว
Environment=CATALINA_PID=/opt/tomcat/temp/tomcat.pid
# สคริปต์ start/stop ของ Tomcat
ExecStart=/opt/tomcat/bin/startup.sh
ExecStop=/opt/tomcat/bin/shutdown.sh
# ห้าม process ยกระดับสิทธิ์ตัวเอง (เช่นผ่าน setuid) — กัน privilege escalation
NoNewPrivileges=true
# ไฟล์/log ใหม่เป็น 640 (group อ่านได้ คนนอกไม่เห็น) — ให้ app-logview อ่าน log ได้
UMask=0027
# process ตายผิดปกติ (crash/OOM) → สตาร์ทใหม่ (คู่กับ ExitOnOutOfMemoryError ใน 5.7)
Restart=on-failure
# รอ 5 วิก่อนสตาร์ทใหม่ (กันวน restart รัวตอนพังซ้ำ)
RestartSec=5

[Install]
# enable แล้วสตาร์ทอัตโนมัติตอนบูต
WantedBy=multi-user.target
```
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now tomcat
sudo systemctl status tomcat               # ต้องขึ้น active (running)
```
> ⚠️ **systemd ไม่รองรับคอมเมนต์ท้ายบรรทัด** — `#` ต้องขึ้นบรรทัดใหม่เสมอ · ถ้าเขียน `Environment=JAVA_HOME=/path # comment` คำว่า comment จะกลายเป็นส่วนหนึ่งของค่า JAVA_HOME ทำให้พัง
> 💡 **ทำไมใช้ systemd:** คุมให้ Tomcat รันด้วย user `tomcat` เสมอ, รีสตาร์ทเองเมื่อ crash, และเก็บ log รวมใน journald (`journalctl -u tomcat`) — ดีกว่ารันค้างด้วย startup.sh เอง

ให้ group `app-logview` อ่าน log ได้อย่างเดียว (สมาชิกกลุ่มนี้ = คนที่ดู log ได้):
```bash
sudo setfacl -R  -m g:app-logview:rX /opt/tomcat/logs     # อ่าน log ปัจจุบัน
sudo setfacl -R -d -m g:app-logview:rX /opt/tomcat/logs   # log ไฟล์ใหม่ (รายวัน) สืบทอดสิทธิ์อ่าน
```
> 💡 `UMask=0027` + ACL default = ไฟล์ log รายวันที่ Tomcat สร้างใหม่ (`catalina.YYYY-MM-DD.log`) จะให้ `app-logview` อ่านได้อัตโนมัติ · คนในกลุ่มใช้ `tail -f /opt/tomcat/logs/catalina.out` หรือ `less` ดูได้ แต่แก้/ลบไม่ได้

### 5.7 ปรับ JVM heap / GC [High]

ตั้งค่า JVM ผ่านไฟล์ `/opt/tomcat/bin/setenv.sh` (Tomcat โหลดอัตโนมัติ — **ไม่ต้องแก้ `catalina.sh`**):
```bash
sudo -u tomcat tee /opt/tomcat/bin/setenv.sh >/dev/null <<'EOF'
#!/bin/sh
CATALINA_OPTS="$CATALINA_OPTS -server"
# --- Heap: ตั้ง Xms = Xmx บนเครื่อง dedicated เพื่อตัด pause ตอนขยาย heap ---
CATALINA_OPTS="$CATALINA_OPTS -Xms2g -Xmx2g"
# --- GC: G1 (default ตั้งแต่ Java 9) เหมาะกับงานทั่วไป ---
CATALINA_OPTS="$CATALINA_OPTS -XX:+UseG1GC -XX:MaxGCPauseMillis=200"
# --- คุม Metaspace ไม่ให้โตไม่จำกัด ---
CATALINA_OPTS="$CATALINA_OPTS -XX:MaxMetaspaceSize=256m"
# --- เจอ OutOfMemory ให้ dump + ออก (systemd จะ restart ให้) ---
CATALINA_OPTS="$CATALINA_OPTS -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/opt/tomcat/logs"
CATALINA_OPTS="$CATALINA_OPTS -XX:+ExitOnOutOfMemoryError"
# --- GC log ไว้ไล่ปัญหา (Java 11+) — เขียนไฟล์เดียว แล้วหมุนรายวันด้วย logrotate (ดู 5.8) ---
CATALINA_OPTS="$CATALINA_OPTS -Xlog:gc*:file=/opt/tomcat/logs/gc.log:time,uptime"
export CATALINA_OPTS
EOF
sudo chmod 750 /opt/tomcat/bin/setenv.sh
sudo systemctl restart tomcat
```

**ขนาด heap ที่เหมาะสม** — เครื่องนี้มี MySQL อยู่ด้วย ต้องแบ่ง RAM ให้ MySQL + OS อย่าให้ Tomcat กินหมด:

| RAM เครื่อง | `-Xmx` Tomcat | เผื่อ MySQL + OS + off-heap |
|---|---|---|
| 4 GB | 1.5–2 GB | ~2 GB |
| 8 GB | 3–4 GB | ~4 GB |
| 16 GB | 6–8 GB | ส่วนที่เหลือ |

**อธิบายแต่ละ flag โดยละเอียด:**

**`-server`** — เลือก HotSpot แบบ "server" ที่ optimize แรงกว่า (JIT compile มากขึ้น) เหมาะกับ process ที่รันยาวอย่าง Tomcat · บนเครื่อง 64-bit เป็น default อยู่แล้ว ใส่ไว้เพื่อความชัดเจน

**`-Xms2g` / `-Xmx2g` — heap เริ่มต้น / heap สูงสุด**
- `-Xmx` = เพดาน heap ที่แอปใช้เก็บ object ได้ ถ้าเกินนี้ → `OutOfMemoryError`
- `-Xms` = heap ที่จองตอนเริ่ม · **ตั้งให้เท่ากับ `-Xmx`** บนเครื่อง dedicated เพราะ: ถ้าตั้งต่างกัน JVM จะค่อยๆ ขยาย heap ตอน load เพิ่ม ซึ่งแต่ละครั้งมี pause และ CPU ที่เสียไป · ตั้งเท่ากัน = จองเต็มตั้งแต่แรก ขนาด heap นิ่ง ไม่มี pause จากการ resize
- **ปรับยังไง:** ดูตารางข้างบนตาม RAM · เริ่มกลางๆ แล้วดู GC log / `free -h` ว่าเหลือ headroom แค่ไหน ค่อยปรับ

**`-XX:+UseG1GC` — เลือก Garbage Collector เป็น G1** — GC คือตัวเก็บกวาด object ที่ไม่ใช้แล้วคืน memory · **G1 (Garbage-First)** เป็น default ตั้งแต่ Java 9 แบ่ง heap เป็นส่วนย่อยแล้วเก็บทีละส่วน ทำให้ pause สั้นและคาดเดาได้ เหมาะกับ web app ที่ต้องตอบ request เร็ว · ทางเลือกอื่น: **ZGC** (`-XX:+UseZGC`, Java 15+) pause ต่ำมาก (<1ms) เหมาะ heap ใหญ่ >8–16 GB แต่กิน CPU/memory overhead มากกว่า — heap ขนาดนี้ G1 พอแล้ว

**`-XX:MaxGCPauseMillis=200` — เป้าหมาย pause สูงสุด (มิลลิวินาที)** — บอก G1 ว่า "พยายาม" ให้แต่ละรอบ GC หยุดแอปไม่เกิน 200ms · เป็น **เป้าหมาย ไม่ใช่การรับประกัน** · ตั้งต่ำเกิน (เช่น 50) → เก็บถี่ขึ้น throughput ลด · 200ms เป็นค่ากลางที่ดีสำหรับ web app

**`-XX:MaxMetaspaceSize=256m` — เพดาน Metaspace** — Metaspace คือที่เก็บ **metadata ของ class** (ไม่ใช่ object — คนละส่วนกับ heap) อยู่นอก heap · ถ้าไม่ตั้งเพดาน มันโตได้เรื่อยๆ จนกิน RAM เครื่องหมด (เช่น แอป leak class/reload บ่อย) · ตั้งเพดานไว้ให้ fail เร็วและเห็นชัดแทนที่จะลาม
- ⚠️ **ปรับยังไง:** แอปใหญ่/library เยอะอาจต้อง **384–512m** · ถ้าเจอ `OutOfMemoryError: Metaspace` = ตั้งน้อยไป ให้เพิ่ม

**`-XX:+HeapDumpOnOutOfMemoryError` + `-XX:HeapDumpPath=/opt/tomcat/logs`** — ตอนแอป OOM ให้ JVM **เขียน heap dump** (snapshot ของ memory ทั้งหมด) ลงไฟล์ไว้ก่อนตาย · เอาไปเปิดด้วย Eclipse MAT / VisualVM ดูได้ว่า object อะไรกิน memory จนเต็ม — จำเป็นมากตอนไล่ memory leak
- ⚠️ heap dump ใหญ่เท่าขนาด heap (เช่น 2GB) → ดูพื้นที่ ดิสก์ ใน `/opt/tomcat/logs` ให้พอ

**`-XX:+ExitOnOutOfMemoryError`** — ปกติเมื่อ OOM แอปอาจ **ค้างครึ่งๆ กลางๆ** (บาง thread ตาย บางตัวยังอยู่) ดูเหมือนรันอยู่แต่ตอบ request ไม่ได้ · flag นี้สั่งให้ JVM **ออกทันที** เมื่อ OOM → systemd (`Restart=on-failure` ใน unit 5.6) เห็นว่า process ตายแล้วปลุกใหม่ให้ กลับมาให้บริการได้เร็ว

**`-Xlog:gc*:file=...:time,uptime:filecount=5,filesize=10M` — GC log** — บันทึกทุกรอบ GC ลงไฟล์ (Java 11+ ใช้รูปแบบ `-Xlog`) · `time,uptime` = ใส่เวลาจริง+เวลาตั้งแต่เริ่ม · `filecount=5,filesize=10M` = หมุนไฟล์ 5 ไฟล์ ไฟล์ละ 10MB (ไม่ให้ log บวม) · เอา gc.log ไปวิเคราะห์ (เช่น GCeasy, GCViewer) ดูว่า GC ถี่ไป/นานไป/heap ตึงไหม

> ⚠️ **ห้ามพลาด — อย่าตั้ง `-Xmx` ใกล้ RAM ทั้งเครื่อง:** JVM กิน memory **นอก heap** อีกหลายส่วน (Metaspace, thread stack, direct buffer, code cache) และเครื่องนี้ยังมี **MySQL + OS page cache** ต้องใช้ RAM ด้วย · ถ้า Tomcat กินเกือบหมด ระบบจะเริ่ม **swap** (ช้าลงมาก) หรือโดน **OOM killer** ของ Linux ฆ่า process ทิ้ง · เผื่อ RAM ให้ส่วนอื่นตามตารางเสมอ

**ตรวจค่าที่ JVM รับจริง** หลัง restart:
```bash
sudo -u tomcat jcmd $(pgrep -f catalina) VM.flags          # ดู flag ทั้งหมดที่ JVM ใช้
sudo -u tomcat jcmd $(pgrep -f catalina) GC.heap_info       # ดูการใช้ heap ปัจจุบัน
```

### 5.8 Log rotation & retention [High]

> ⚠️ **กับดักที่หลายคนพลาด:** Tomcat ตัดไฟล์ log รายวันก็จริง แต่ **default ไม่ลบของเก่าให้** และ `catalina.out` **ไม่ rotate เลย** โตไฟล์เดียวจน ดิสก์ เต็ม

| ไฟล์ | ตัดรายวัน? | ลบของเก่า (default) | ต้องทำ |
|---|---|---|---|
| `catalina.<date>.log`, `localhost.*`, access | ✅ (JULI) | ❌ เก็บตลอดไป | ตั้ง `maxDays` |
| `catalina.out` | ❌ ไม่ตัด | ❌ โตไม่จำกัด | logrotate รายวัน |
| `gc.log` | ✅ รายวัน (ผ่าน logrotate) | logrotate | logrotate รายวัน |

**1) ไฟล์รายวันของ Tomcat — ตั้ง `maxDays`** ใน `/opt/tomcat/conf/logging.properties`:
```properties
1catalina.org.apache.juli.AsyncFileHandler.maxDays = 90
2localhost.org.apache.juli.AsyncFileHandler.maxDays = 90
3manager.org.apache.juli.AsyncFileHandler.maxDays = 90
4host-manager.org.apache.juli.AsyncFileHandler.maxDays = 90
```
> 💡 `maxDays = 90` = เก็บ 90 วันแล้วลบอัตโนมัติ (ตั้ง ≤0 = เก็บตลอดไป ซึ่งเป็น default) · restart tomcat ให้มีผล

**2) catalina.out + gc.log — หมุนรายวันด้วย logrotate** สร้าง `/etc/logrotate.d/tomcat`:
```
/opt/tomcat/logs/catalina.out
/opt/tomcat/logs/gc.log {
    daily               # ตัดไฟล์รายวัน (1 ไฟล์ = 1 วัน ไล่ง่าย)
    rotate 90           # เก็บ 90 วัน
    compress            # บีบอัดไฟล์เก่า ประหยัด disk
    delaycompress
    missingok
    notifempty
    copytruncate        # ตัดไฟล์ให้ว่างโดยไม่ต้อง restart Tomcat (Tomcat/JVM เปิดไฟล์ค้างไว้)
    su tomcat tomcat
}
```
```bash
sudo logrotate -d /etc/logrotate.d/tomcat      # -d = dry-run ตรวจก่อน (ไม่ลบจริง)
```
> 💡 **`copytruncate`** จำเป็นเพราะ Tomcat/JVM เปิดไฟล์ค้างไว้ตลอด — logrotate คัดลอกเนื้อหาออกแล้วตัดไฟล์เดิมให้ว่าง แทนที่จะย้ายไฟล์ (ซึ่งจะทำให้ process เขียนลงไฟล์ที่ถูกย้ายไปแล้ว) · ไฟล์เก่าจะชื่อ `gc.log.1`, `catalina.out.1` … ตามวัน

**3) gc.log** — ตัด size-rotation ใน 5.7 แล้ว (ให้เขียนไฟล์เดียว) → หมุนรายวันโดย logrotate ข้างบนพร้อม catalina.out

> 💡 **retention เท่าไรดี:** 90 วันเป็นค่ากลางที่ใช้บ่อย · ปรับตามนโยบาย/compliance (เช่น PCI-DSS ขั้นต่ำ 1 ปี โดยเก็บ online 3 เดือน) · **ถ้าต้องเก็บยาว ให้ ship log ออก central log server** แล้วในเครื่องเก็บสั้นเท่าที่ ดิสก์ ไหว

### 5.9 Access log — บันทึกว่าใครเข้าแอป [High]

บันทึกทุก request ที่เข้าแอป (IP, เวลา, URL, status, เวลาตอบ) · เปิดใน `/opt/tomcat/conf/server.xml` ภายใน `<Host>`:
```xml
<!-- อ่าน client IP จริงจาก X-Forwarded-For ที่ Nginx ส่งมา (ต้องมาก่อน AccessLogValve) -->
<Valve className="org.apache.catalina.valves.RemoteIpValve"
       remoteIpHeader="X-Forwarded-For"
       protocolHeader="X-Forwarded-Proto" />

<Valve className="org.apache.catalina.valves.AccessLogValve"
       directory="logs" prefix="access" suffix=".log"
       pattern="%a %t &quot;%r&quot; %s %b %D &quot;%{Referer}i&quot; &quot;%{User-Agent}i&quot; %S"
       rotatable="true" maxDays="90" />
```
ตัวอย่างบรรทัดที่ได้:
```
203.0.113.5 [17/Oct/2026:19:40:12 +0700] "POST /app/orders/create HTTP/1.1" 200 512 48 "https://site/app/orders" "Mozilla/5.0 ..." A1B2C3D4E5
```
**แต่ละ field:** `%a` IP จริง · `%t` เวลา · `"%r"` **request line = method + หน้า/endpoint** (เช่น `POST /app/orders/create`) · `%s` HTTP status · `%b` bytes · `%D` เวลาตอบ (ms) · `"%{Referer}i"` **มาจากหน้าไหน** · `"%{User-Agent}i"` browser/device · `%S` **session id** (ไล่ได้ว่า request ไหนเป็นคนเดียวกัน)

> 💡 **ทำไมต้องมี RemoteIpValve:** Tomcat อยู่หลัง Nginx → ทุก request มาจาก `127.0.0.1` · RemoteIpValve อ่าน `X-Forwarded-For` (ตั้งใน 6.1) แล้วแทน `%a` ด้วย **IP จริงของผู้ใช้** · ต้องวาง **ก่อน** AccessLogValve
> 💡 `maxDays="90"` = retention 90 วัน (JULI ตัดรายวันให้อยู่แล้ว) · restart tomcat ให้มีผล
> ⚠️ **access log บอกได้แค่ "หน้าไหน + method":** ไม่เห็น **POST body** (เนื้อหาที่กรอก) · ไม่เห็น **username ที่ login** (session login → `%u` เป็น `-`; ใช้ `%S` ไล่ตาม session แทน) · ไม่รู้ **business action** — ถ้าต้อง audit "user ชื่ออะไรทำอะไรจริง" **แอปต้องเขียน log เอง**

---
