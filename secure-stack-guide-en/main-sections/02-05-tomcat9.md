## 5. Install & configure Tomcat 9 (download from apache) [Critical]

> 💡 The app supports **Tomcat 9** — install directly from apache's tarball (not apt) to control the version yourself

### 5.1 Install Java + create a user

```bash
sudo apt install -y default-jre
java -version                        # confirm Java is installed (Tomcat 9 needs Java 8+)
readlink -f $(which java)            # find Java's real path to set JAVA_HOME in step 5.6
sudo useradd --system --home-dir /opt/tomcat --shell /usr/sbin/nologin tomcat
```
> ⚠️ **Check JAVA_HOME:** Java's path varies by version (e.g. `/usr/lib/jvm/java-21-openjdk-amd64`) — note the value from `readlink` above and put it in the systemd unit (5.6); don't use a hardcoded value without checking

### 5.2 Download Tomcat 9 from apache

Check the latest 9.x version at https://tomcat.apache.org/download-90.cgi then replace `VER` with the real number
```bash
cd /tmp
VER=9.0.98                           # ← change to the latest 9.0.x version
wget https://dlcdn.apache.org/tomcat/tomcat-9/v${VER}/bin/apache-tomcat-${VER}.tar.gz
# verify file integrity (guard against incomplete/tampered downloads):
wget https://downloads.apache.org/tomcat/tomcat-9/v${VER}/bin/apache-tomcat-${VER}.tar.gz.sha512
sha512sum -c apache-tomcat-${VER}.tar.gz.sha512
sudo mkdir -p /opt/tomcat
sudo tar xzf apache-tomcat-${VER}.tar.gz -C /opt/tomcat --strip-components=1
sudo chown -R tomcat:tomcat /opt/tomcat
```
> 💡 `--strip-components=1` = extract while stripping the top-level folder, so files land directly in `/opt/tomcat` instead of nesting as `/opt/tomcat/apache-tomcat-9.x.x/`

### 5.3 Remove unused default apps

```bash
sudo rm -rf /opt/tomcat/webapps/{examples,docs,ROOT,host-manager,manager}
```
> 💡 **Explain:** examples/docs have old vulnerabilities and expose version info · remove manager/host-manager because we deploy by file-drop and don't use them (see 5.5) — everything removed = reduced attack surface

### 5.4 Edit `server.xml` (`/opt/tomcat/conf/server.xml`)

- **Disable/remove the AJP connector** `<Connector port="8009" ... />` — prevents **Ghostcat (CVE-2020-1938)** which can read files in the app via AJP · if you don't use AJP, delete it
- **Bind HTTP to localhost** `<Connector port="8080" address="127.0.0.1" ... />` — only local Nginx can connect; external clients can't reach 8080 directly
- **Disable the shutdown port** set `<Server port="-1" ...>` — closes the shutdown-via-port channel
- **Hide the version** add inside `<Host>`: `<Valve className="org.apache.catalina.valves.ErrorReportValve" showServerInfo="false" showReport="false"/>` — error pages won't show the Tomcat version

### 5.5 Manager / tomcat-users.xml — unused

We deploy by file-drop (see section 7), so **don't enable the manager webapp and don't set up accounts in tomcat-users.xml** (manager was removed in 5.3) — manager accounts are a popular attack target, so cutting them is safer

### 5.6 File permissions + systemd service

Run as the `tomcat` user, not root:
```bash
sudo chmod -R o-rwx /opt/tomcat/conf      # stop "others" reading config (has passwords/secrets)
```
Create `/etc/systemd/system/tomcat.service` — explanations are in the per-line comments (set `JAVA_HOME` to the value from 5.1):
```ini
[Unit]
Description=Apache Tomcat 9
# wait for the network before starting
After=network.target

[Service]
# startup.sh forks to background then the parent exits → let systemd track the PID from the file (CATALINA_PID)
Type=forking
# run as the tomcat account (nologin), not root — if breached, the attacker only gets tomcat's rights
User=tomcat
Group=tomcat
# point at the Java to run — must match the value from `readlink` in 5.1
Environment=JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
# the Tomcat install folder
Environment=CATALINA_HOME=/opt/tomcat
# PID file — required for Type=forking so systemd tracks/stops the right process
Environment=CATALINA_PID=/opt/tomcat/temp/tomcat.pid
# Tomcat's start/stop scripts
ExecStart=/opt/tomcat/bin/startup.sh
ExecStop=/opt/tomcat/bin/shutdown.sh
# forbid the process escalating its own privileges (e.g. via setuid) — prevents privilege escalation
NoNewPrivileges=true
# new files/logs are 640 (group-readable, outsiders can't see) — lets app-logview read logs
UMask=0027
# process dies abnormally (crash/OOM) → restart (pairs with ExitOnOutOfMemoryError in 5.7)
Restart=on-failure
# wait 5s before restarting (avoids rapid restart loops on repeated failures)
RestartSec=5

[Install]
# enable so it auto-starts at boot
WantedBy=multi-user.target
```
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now tomcat
sudo systemctl status tomcat               # should show active (running)
```
> ⚠️ **systemd does not support end-of-line comments** — `#` must always be on its own line · if you write `Environment=JAVA_HOME=/path # comment` the word comment becomes part of JAVA_HOME's value and breaks it
> 💡 **Why systemd:** it ensures Tomcat always runs as the `tomcat` user, restarts itself on crash, and collects logs in journald (`journalctl -u tomcat`) — better than leaving startup.sh running by hand

Let the `app-logview` group read logs (read-only); group members = people who can view logs:
```bash
sudo setfacl -R  -m g:app-logview:rX /opt/tomcat/logs     # read current logs
sudo setfacl -R -d -m g:app-logview:rX /opt/tomcat/logs   # new (daily) log files inherit read access
```
> 💡 `UMask=0027` + default ACL = new daily log files Tomcat creates (`catalina.YYYY-MM-DD.log`) are automatically readable by `app-logview` · group members can `tail -f /opt/tomcat/logs/catalina.out` or `less` to view, but can't edit/delete

### 5.7 Tune JVM heap / GC [High]

Set JVM options in `/opt/tomcat/bin/setenv.sh` (Tomcat loads it automatically — **don't edit `catalina.sh`**):
```bash
sudo -u tomcat tee /opt/tomcat/bin/setenv.sh >/dev/null <<'EOF'
#!/bin/sh
CATALINA_OPTS="$CATALINA_OPTS -server"
# --- Heap: set Xms = Xmx on a dedicated machine to avoid pauses when the heap grows ---
CATALINA_OPTS="$CATALINA_OPTS -Xms2g -Xmx2g"
# --- GC: G1 (default since Java 9) suits general workloads ---
CATALINA_OPTS="$CATALINA_OPTS -XX:+UseG1GC -XX:MaxGCPauseMillis=200"
# --- cap Metaspace so it can't grow unbounded ---
CATALINA_OPTS="$CATALINA_OPTS -XX:MaxMetaspaceSize=256m"
# --- on OutOfMemory, dump + exit (systemd will restart) ---
CATALINA_OPTS="$CATALINA_OPTS -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/opt/tomcat/logs"
CATALINA_OPTS="$CATALINA_OPTS -XX:+ExitOnOutOfMemoryError"
# --- GC log for troubleshooting (Java 11+) — write one file, rotated daily by logrotate (see 5.8) ---
CATALINA_OPTS="$CATALINA_OPTS -Xlog:gc*:file=/opt/tomcat/logs/gc.log:time,uptime"
export CATALINA_OPTS
EOF
sudo chmod 750 /opt/tomcat/bin/setenv.sh
sudo systemctl restart tomcat
```

**Appropriate heap size** — this machine also runs MySQL, so split RAM for MySQL + OS and don't let Tomcat take it all:

| Machine RAM | Tomcat `-Xmx` | Reserve for MySQL + OS + off-heap |
|---|---|---|
| 4 GB | 1.5–2 GB | ~2 GB |
| 8 GB | 3–4 GB | ~4 GB |
| 16 GB | 6–8 GB | the remainder |

**Each flag explained in detail:**

**`-server`** — picks the "server" HotSpot that optimizes harder (more JIT compilation), suited to long-running processes like Tomcat · it's already the default on 64-bit machines; included for clarity

**`-Xms2g` / `-Xmx2g` — initial heap / maximum heap**
- `-Xmx` = the heap ceiling the app can use to hold objects; exceed it → `OutOfMemoryError`
- `-Xms` = the heap reserved at start · **set it equal to `-Xmx`** on a dedicated machine because: if they differ the JVM gradually grows the heap under load, each growth incurring a pause and wasted CPU · setting them equal = reserve it all upfront, heap size stays steady, no resize pauses
- **How to tune:** use the table above by RAM · start in the middle, then watch the GC log / `free -h` for headroom and adjust

**`-XX:+UseG1GC` — choose G1 as the Garbage Collector** — GC reclaims memory from unused objects · **G1 (Garbage-First)** is the default since Java 9; it splits the heap into regions and collects piece by piece, keeping pauses short and predictable — good for web apps that must answer requests quickly · alternative: **ZGC** (`-XX:+UseZGC`, Java 15+) has very low pauses (<1ms), suited to large heaps >8–16 GB but with more CPU/memory overhead — for this heap size G1 is plenty

**`-XX:MaxGCPauseMillis=200` — target maximum pause (milliseconds)** — tells G1 to "try" to keep each GC cycle under 200ms · it's a **goal, not a guarantee** · set too low (e.g. 50) → collects more often, throughput drops · 200ms is a good middle value for web apps

**`-XX:MaxMetaspaceSize=256m` — Metaspace ceiling** — Metaspace holds **class metadata** (not objects — a different area from the heap), outside the heap · without a cap it can keep growing until it eats all machine RAM (e.g. an app that leaks classes/reloads often) · capping it makes it fail fast and visibly instead of spreading
- ⚠️ **How to tune:** large apps / many libraries may need **384–512m** · if you hit `OutOfMemoryError: Metaspace` = set too low, increase it

**`-XX:+HeapDumpOnOutOfMemoryError` + `-XX:HeapDumpPath=/opt/tomcat/logs`** — on OOM, have the JVM **write a heap dump** (a snapshot of all memory) to a file before dying · open it with Eclipse MAT / VisualVM to see which objects filled memory — essential for chasing memory leaks
- ⚠️ a heap dump is as large as the heap (e.g. 2GB) → make sure `/opt/tomcat/logs` has enough disk

**`-XX:+ExitOnOutOfMemoryError`** — normally on OOM the app may be **left half-alive** (some threads dead, some still up), looking like it's running but unable to answer requests · this flag tells the JVM to **exit immediately** on OOM → systemd (`Restart=on-failure` in the unit, 5.6) sees the process die and restarts it, restoring service quickly

**`-Xlog:gc*:file=...:time,uptime:filecount=5,filesize=10M` — GC log** — records every GC cycle to a file (Java 11+ uses the `-Xlog` format) · `time,uptime` = include wall-clock time + time since start · `filecount=5,filesize=10M` = rotate across 5 files of 10MB each (keeps the log from ballooning) · take gc.log for analysis (e.g. GCeasy, GCViewer) to see whether GC is too frequent/too long or the heap is tight

> ⚠️ **Must not miss — don't set `-Xmx` near the machine's total RAM:** the JVM uses memory **outside the heap** too (Metaspace, thread stacks, direct buffers, code cache), and this machine also runs **MySQL + OS page cache** needing RAM · if Tomcat takes almost all of it the system starts to **swap** (much slower) or Linux's **OOM killer** kills a process · always reserve RAM for the rest per the table

**Verify the values the JVM actually took** after restart:
```bash
sudo -u tomcat jcmd $(pgrep -f catalina) VM.flags          # show all flags the JVM is using
sudo -u tomcat jcmd $(pgrep -f catalina) GC.heap_info       # show current heap usage
```

### 5.8 Log rotation & retention [High]

> ⚠️ **A trap many people miss:** Tomcat does split log files daily, but **by default it doesn't delete old ones**, and `catalina.out` is **never rotated** — it grows as a single file until the disk fills

| File | Split daily? | Delete old (default) | What to do |
|---|---|---|---|
| `catalina.<date>.log`, `localhost.*`, access | ✅ (JULI) | ❌ keep forever | set `maxDays` |
| `catalina.out` | ❌ never split | ❌ grows unbounded | logrotate daily |
| `gc.log` | ✅ daily (via logrotate) | logrotate | logrotate daily |

**1) Tomcat's daily files — set `maxDays`** in `/opt/tomcat/conf/logging.properties`:
```properties
1catalina.org.apache.juli.AsyncFileHandler.maxDays = 90
2localhost.org.apache.juli.AsyncFileHandler.maxDays = 90
3manager.org.apache.juli.AsyncFileHandler.maxDays = 90
4host-manager.org.apache.juli.AsyncFileHandler.maxDays = 90
```
> 💡 `maxDays = 90` = keep 90 days then delete automatically (≤0 = keep forever, which is the default) · restart tomcat to apply

**2) catalina.out + gc.log — rotate daily with logrotate** create `/etc/logrotate.d/tomcat`:
```
/opt/tomcat/logs/catalina.out
/opt/tomcat/logs/gc.log {
    daily               # split daily (1 file = 1 day, easy to trace)
    rotate 90           # keep 90 days
    compress            # compress old files to save disk
    delaycompress
    missingok
    notifempty
    copytruncate        # empty the file without restarting Tomcat (Tomcat/JVM keeps it open)
    su tomcat tomcat
}
```
```bash
sudo logrotate -d /etc/logrotate.d/tomcat      # -d = dry-run to check first (deletes nothing)
```
> 💡 **`copytruncate`** is needed because Tomcat/JVM keeps the file open the whole time — logrotate copies the contents out then truncates the original to empty, instead of moving the file (which would make the process write to a now-moved file) · old files are named `gc.log.1`, `catalina.out.1` … by day

**3) gc.log** — size-rotation was cut in 5.7 (write a single file) → rotated daily by the logrotate above alongside catalina.out

> 💡 **How much retention:** 90 days is a common middle value · adjust per policy/compliance (e.g. PCI-DSS minimum 1 year with 3 months kept online) · **if you must keep it long, ship logs to a central log server** and keep only as much on the machine as disk allows

### 5.9 Access log — record who hits the app [High]

Records every request to the app (IP, time, URL, status, response time) · enable it in `/opt/tomcat/conf/server.xml` inside `<Host>`:
```xml
<!-- read the real client IP from the X-Forwarded-For Nginx sends (must come before AccessLogValve) -->
<Valve className="org.apache.catalina.valves.RemoteIpValve"
       remoteIpHeader="X-Forwarded-For"
       protocolHeader="X-Forwarded-Proto" />

<Valve className="org.apache.catalina.valves.AccessLogValve"
       directory="logs" prefix="access" suffix=".log"
       pattern="%a %t &quot;%r&quot; %s %b %D &quot;%{Referer}i&quot; &quot;%{User-Agent}i&quot; %S"
       rotatable="true" maxDays="90" />
```
Example resulting line:
```
203.0.113.5 [17/Oct/2026:19:40:12 +0700] "POST /app/orders/create HTTP/1.1" 200 512 48 "https://site/app/orders" "Mozilla/5.0 ..." A1B2C3D4E5
```
**Each field:** `%a` real IP · `%t` time · `"%r"` **request line = method + page/endpoint** (e.g. `POST /app/orders/create`) · `%s` HTTP status · `%b` bytes · `%D` response time (ms) · `"%{Referer}i"` **which page it came from** · `"%{User-Agent}i"` browser/device · `%S` **session id** (trace which requests are the same person)

> 💡 **Why RemoteIpValve:** Tomcat sits behind Nginx → every request comes from `127.0.0.1` · RemoteIpValve reads `X-Forwarded-For` (set in 6.1) and replaces `%a` with the **user's real IP** · it must be placed **before** AccessLogValve
> 💡 `maxDays="90"` = 90-day retention (JULI splits daily already) · restart tomcat to apply
> ⚠️ **the access log tells you only "which page + method":** it does not see the **POST body** (what was filled in) · it does not see the **logged-in username** (session login → `%u` is `-`; use `%S` to trace by session instead) · it doesn't know the **business action** — to audit "which user actually did what," **the app must write its own log**

---
