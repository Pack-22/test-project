# Appendix (A–E)

## Appendix A — Log retention standards

**The guide's default = 90 days** compared to common standards:

| Standard | Minimum retention | Is 90 days enough |
|---|---|---|
| **Thai Computer Crime Act §26** | ≥ 90 days (extendable to 2 years) | ✅ passes |
| **PCI-DSS** (if touching card/financial data) | 1 year (3 months readily available online) | ⚠️ must archive more to reach 1 year |
| **ISO 27001** | self-defined per risk/law | must have a written policy |
| **PDPA (Thailand)** | no fixed number | keep enough to investigate / per org policy |

> ⚠️ **For financial systems (e.g. linebot-finance / cbi_platform):** likely in PCI-DSS scope → keep 90 days online on the machine **+ ship logs to central/archive to reach 1 year or more**

**Standards require more than just retention — check these 5:**

1. ✅ **Synced time (NTP)** — accurate timestamps (section 3.7) · PCI req. 10.6
2. ✅ **Tamper/delete protection (integrity)** — restrict read access (app-logview read-only, auditd) + **ship logs to central** so local root can't erase tracks
3. ✅ **Capture all key events** — login, privilege use (sudo), data access, config changes, deploys → auditd (3.6) + access logs (5.9, 6.4) cover these
4. ⬜ **Regular review** — someone/a tool (SIEM) must review logs on a cycle, not just store them
5. ✅ **Central log server** — the forwarding method is in **Appendix C** (the destination server, e.g. Graylog/ELK/Loki, is separate work)

> ⚠️ **Always confirm the numbers/requirements with your compliance / legal team first** — standards get revised and each org/industry has extra obligations; this guide sets a good baseline but doesn't replace a compliance certification

---

## Appendix B — Per-log details

Every log in this system: what it does, what it captures, and where retention is set

| Log | Path | Role | What it captures | Retention set in |
|---|---|---|---|---|
| **Nginx access** | `/var/log/nginx/access.log` | every external web request (the primary "who came in") | real client IP · time · `"METHOD /path HTTP/x"` · status · bytes · referer · user-agent | 6.4 (logrotate) |
| **Nginx error** | `/var/log/nginx/error.log` | Nginx's own problems | bad config · upstream (Tomcat) down · TLS/cert errors · timeout | 6.4 (logrotate) |
| **Tomcat access** | `/opt/tomcat/logs/access.<date>.log` | app-level requests (supplements Nginx) | real IP (via RemoteIpValve) · time · request · status · response time (ms) | 5.9 (`maxDays`) |
| **catalina.out** | `/opt/tomcat/logs/catalina.out` | Tomcat + app stdout/stderr | start/stop logs · exceptions/stack traces · app `System.out` | 5.8 (logrotate) |
| **catalina.\<date\>** | `/opt/tomcat/logs/catalina.<date>.log` | Tomcat core events (JULI) | component start/stop · deploy/undeploy · container warnings | 5.8 (`maxDays`) |
| **localhost.\<date\>** | `/opt/tomcat/logs/localhost.<date>.log` | uncaught web-app errors | exceptions that reach the container · app lifecycle | 5.8 (`maxDays`) |
| **GC log** | `/opt/tomcat/logs/gc.log` | the JVM's Garbage Collector behavior | every GC cycle · pause time · heap before/after · GC cause | 5.8 (daily logrotate) |
| **auth.log** | `/var/log/auth.log` | login / sudo / SSH (the primary "who accessed the host") | SSH login success/failure + key fingerprint · every sudo command + who ran it · su | logrotate (OS default) |
| **audit.log** | `/var/log/audit/audit.log` | auditd — kernel-level evidence | `execve` (commands run) · touches of watched files (webapps/conf/passwd/sudoers) · identity changes | 3.6 (daily, keep 90) |
| **MySQL error** | `/var/log/mysql/error.log` | MySQL's problems | start/stop · crash · connection/auth issues · warnings | logrotate (mysql default) |
| **journald** | `journalctl` (binary) | combined log of all systemd services | output of `tomcat`, `worker`, timers etc. · boot log | `journald.conf` (daily, 90, see below) |

> 💡 **journald — keep daily for 90 days** edit `/etc/systemd/journald.conf`:
> ```
> [Journal]
> # store persistently on disk (/var/log/journal), not just RAM
> Storage=persistent
> # use up to 2GB of disk
> SystemMaxUse=2G
> # close the journal file every day (1 file = 1 day, easy to trace)
> MaxFileSec=1day
> # delete journals older than 90 days
> MaxRetentionSec=90day
> ```
> then `sudo systemctl restart systemd-journald` · check current size: `journalctl --disk-usage` · view a specific day: `journalctl --since "2026-10-17" --until "2026-10-18"`

> 💡 **Map to "who came in":** host access → `auth.log` + `audit.log` · web visits → Nginx `access.log` · app level → Tomcat `access` · app username → the app writes its own

---

## Appendix C — Ship logs to a central server

Keeping logs only on the machine isn't enough for compliance because (1) whoever gets root can erase tracks, (2) long retention (e.g. 1 year) eats machine disk · the standard approach is to **forward to a central log server** (rsyslog / Graylog / ELK / Loki — the server itself is separate work)

**Caution first:** open UFW outbound to the log server on only the ports used, and **use TLS** to prevent interception in transit

### C.1 syslog + auth.log → rsyslog forward (simplest, built in)

`/etc/rsyslog.d/90-forward.conf`:
```
# send all syslog (including auth) to the log server over TCP/TLS
*.*  action(type="omfwd"
            target="logserver.internal" port="6514" protocol="tcp"
            StreamDriver="gtls" StreamDriverMode="1" StreamDriverAuthMode="x509/name"
            queue.type="linkedList" queue.filename="fwdq"   # a queue to avoid loss if the server is down
            action.resumeRetryCount="-1")
```
```bash
sudo systemctl restart rsyslog
```

### C.2 Nginx/Tomcat log files → use rsyslog imfile or a log shipper

These files don't go through syslog, so you need something to tail and send them:
```
# /etc/rsyslog.d/91-appfiles.conf — have rsyslog read the files and forward
module(load="imfile")
input(type="imfile" File="/var/log/nginx/access.log" Tag="nginx-access")
input(type="imfile" File="/opt/tomcat/logs/catalina.out" Tag="tomcat-out")
input(type="imfile" File="/opt/tomcat/logs/access.*.log" Tag="tomcat-access")
```
> 💡 A more popular option for app files: a **log shipper** — Promtail (→ Loki), Filebeat (→ Elasticsearch), or Fluent Bit · installed as a lightweight service, it tails files and sends them to a destination with easier search/dashboards than raw syslog

### C.3 audit.log → audisp-remote (auditd's dedicated channel)

```bash
sudo apt install -y audispd-plugins
```
Enable the plugin in `/etc/audit/plugins.d/au-remote.conf` (`active = yes`) then set the destination in `/etc/audit/audisp-remote.conf`:
```
remote_server = logserver.internal
port = 60
transport = tcp
# enable TLS/Kerberos as your log server supports
enable_krb5 = no
```
```bash
sudo systemctl restart auditd
```
> 💡 **Explain:** auditd has its own forward channel (audisp), separate from syslog, to preserve the integrity of the audit trail · the destination must run `auditd` in receive mode (`au-remote`) or a SIEM that supports it

> ⚠️ **After forwarding, the machine can keep short retention** (e.g. 90 days), with long retention (1 year+) living on the central server — matching what Appendix A requires

---

## Appendix D — Troubleshooting runbook (where to trace, in order)

> 💡 **Troubleshooting principle:** a request travels **Client → Nginx → Tomcat → app → MySQL** · trace the logs **along this path, layer by layer**, and find where the problem stops (the layer where errors first appear = the root cause is near there)

**Always check overall health first:**
```bash
systemctl status nginx tomcat mysql     # which service is down
df -h ; free -h                         # is disk/RAM full
ss -tulpn                               # ports that should be listening (443 nginx, 8080/3306 localhost)
```

### D.1 Site unreachable / shows 502 or 503

Trace from outside in:
1. `curl -I https://yourdomain.com` — what status (no connection at all = network/firewall/nginx down)
2. `systemctl status nginx` — is nginx running · `sudo nginx -t` — is the config valid
3. `sudo tail /var/log/nginx/error.log` — **502/503 are usually logged here** (e.g. `connect() failed ... upstream`) = nginx can't reach Tomcat
4. `systemctl status tomcat` — is Tomcat running · `ss -tulpn | grep 8080` — is it listening
5. `tail /opt/tomcat/logs/catalina.out` — did Tomcat fail to start / crash

### D.2 Error 500 (app broken)

1. `grep ' 500 ' /var/log/nginx/access.log` — which endpoint is failing
2. `tail -f /opt/tomcat/logs/catalina.out` + `localhost.<date>.log` — **the stack trace is here** (exception name + code file)
3. if the stack points to the DB → go to D.5 · if it points to config → check the app's config file

### D.3 Site slow

1. `/var/log/nginx/access.log` look at `$request_time` — which layer is slow (high = slow from the upstream already)
2. Tomcat access log `%D` (ms) — which endpoint is slow
3. `tail /opt/tomcat/logs/gc.log` — frequent/long GC pauses (tight heap → go to D.4)
4. `top` / `free -h` — CPU/RAM maxed, or swapping
5. if queries are slow → enable the MySQL slow query log and inspect

### D.4 Tomcat dies and restarts / OutOfMemory

1. `journalctl -u tomcat --since today` — see restart cycles
2. `grep -i outofmemory /opt/tomcat/logs/catalina.out` — confirm OOM
3. a heap dump exists in `/opt/tomcat/logs/*.hprof` → open with Eclipse MAT to find which objects eat memory
4. `gc.log` — heap fills fast / GC too frequent → raise `-Xmx` (see 5.7 sizing table) or find a memory leak in the app

### D.5 App can't connect to the DB

1. app log / `catalina.out` — what error (`Communications link failure` = can't connect · `Access denied` = user/password · `Public Key Retrieval` / auth = caching_sha2 → see 4)
2. `systemctl status mysql` + `sudo tail /var/log/mysql/error.log`
3. `ss -tulpn | grep 3306` — is MySQL listening on `127.0.0.1` · `mysql -u app -p -h 127.0.0.1 appdb` — try connecting as the app user
4. check grants: `SHOW GRANTS FOR 'app'@'127.0.0.1';`

### D.6 Can't SSH in

1. `ssh -v user@host` on the client — see where it hangs (auth fail / connection refused)
2. (if another session still has access) `sudo tail /var/log/auth.log` — the reason for refusal
3. check `AllowUsers` includes the user · key perms `~/.ssh` = 700, `authorized_keys` = 600
4. `sudo fail2ban-client status sshd` — is the IP banned → `sudo fail2ban-client set sshd unbanip <ip>`

### D.7 Disk full

1. `df -h` — which partition is full
2. `sudo du -xh / | sort -rh | head` — which folder is consuming it
3. `du -sh /opt/tomcat/logs /var/log/* ; journalctl --disk-usage` — is a log abnormally large (retention not working?)
4. quick fix: delete/compress old logs · long-term fix: check logrotate/maxDays (5.8) and `logrotate -f` to run it now

### D.8 HTTPS error / expired cert

1. `curl -vI https://yourdomain.com` — see the TLS error
2. `sudo certbot certificates` — expiry date
3. `sudo certbot renew --dry-run` — can it renew · `/var/log/letsencrypt/` for the cause (e.g. port 80 blocked / DNS changed)

### D.9 Deployed but the app doesn't come up

1. `tail -f /opt/tomcat/logs/catalina.out` while dropping the war — see `Deployment ... has finished` or an error
2. file permissions: `tomcat` must be able to read the war (`ls -l /opt/tomcat/webapps/` — group `tomcat` + readable) see 7.1
3. filename = context path correct (`app.war` → `/app`) · is autoDeploy enabled

### D.10 Machine hangs after reboot (LUKS)

The machine hangs waiting for the passphrase before boot → SSH into initramfs then `cryptroot-unlock` (see 2.1) · if dropbear is unreachable = the static IP in initramfs is wrong → you need a monitor on the machine

> 💡 **Keep this runbook somewhere reachable when the system is down** (central wiki / phone), not only on the machine you might not be able to reach

---

## Appendix E — Preventive maintenance (routine upkeep)

> 💡 **Concept:** check before it breaks · regular routine work keeps small issues from snowballing (disk full, expired cert, pending patches, broken backups)

### Monitoring (set automatic alerts — most important)

Set up monitoring (e.g. Prometheus/Zabbix/Netdata, or cron + alerts) to warn when:

| Alert when | Threshold | Why |
|---|---|---|
| Disk full | > 80% | prevents the system/logs being unable to write (see D.7) |
| Service down | nginx/tomcat/mysql not active | know before users report it |
| RAM/Swap | swap starts being used heavily | heap/MySQL over-consuming (see 5.7) |
| Cert near expiry | < 30 days | prevent HTTPS outage (certbot usually renews, but watch it) |
| 5xx rate spike | abnormal vs baseline | app/DB problem |
| Failed logins spike | frequent SSH failures | under attack (fail2ban should handle it) |
| Backup | a backup job failed | avoid discovering a broken backup when you need it |

### Review cadence

| Cadence | Work |
|---|---|
| **Daily** (automated + eyes) | check service health, disk/RAM, scan error logs, confirm backups succeeded |
| **Weekly** | review abnormal logs (auth fails, 5xx) · verify log retention works (`du -sh` not growing abnormally) · review fail2ban bans · watch disk trend |
| **Monthly** | install security patches (staging→prod per 3.1) · **test a backup restore** (not just backing up) · review users/groups, remove leavers · check cert auto-renew · review audit logs |
| **Quarterly** | **test reboot + LUKS unlock** · review firewall rules · review JVM heap/GC against real load · update Tomcat/Java minor versions · run a DR drill |
| **Yearly** | rotate credentials/SSH keys · full DR drill · review the whole config against the baseline + compliance standards |

### Commonly forgotten points (preventable breakage)

- ⚠️ **Never testing a restore** — you have backups but can't actually recover · once a month try restoring to a test machine
- ⚠️ **Not testing LUKS unlock after network/initramfs changes** — you reboot for real and can't get in
- ⚠️ **Letting the disk grow silently** — set an 80% alert, don't wait until it's full
- ⚠️ **Not removing users who left the team** — review `getent group` every month
- ⚠️ **Letting patches pile up** — old vulnerabilities accumulate · keep a regular patch cycle

> 💡 **Automate these routines as much as possible** — systemd timers (disk/health checks), a monitoring tool (alerts), and a documented checklist for the human tasks (restore test, DR drill)

---

---

**Must not miss:** store the LUKS passphrase somewhere other than the machine · **test remote unlock before going live** · keep a session open while editing SSH/firewall · encrypt backups that leave the machine · always test in staging first

_Supported: Ubuntu 24.04 LTS (recommended) / 22.04 LTS · Nginx 1.24+ · Tomcat 9.0.x · MySQL 8.0 · Java 11/17/21 — verify package names/directives/paths match what you actually installed_
