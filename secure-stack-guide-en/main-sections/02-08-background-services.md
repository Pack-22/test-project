## 8. Services / other background jobs (if any)

The same pattern applies to every service — 4 principles:

1. **1 service = 1 dedicated user (nologin), not shared** — if one service is breached it doesn't spread to the others
2. **Run via a hardened systemd** — not as root and not left running in screen/tmux
3. **network service → bind `127.0.0.1`** and keep the port closed in UFW (talk only via Nginx/localhost)
4. **scheduled jobs → use a systemd timer** (better than cron: logs centralized in journald, control over user/permissions)

**Create a user + place files**
```bash
sudo useradd --system --create-home --home-dir /opt/worker \
     --shell /usr/sbin/nologin worker
sudo chown -R worker:worker /opt/worker
```

**systemd unit (hardened template)** — `/etc/systemd/system/worker.service`
```ini
[Unit]
Description=Background worker
# wait for the network before starting
After=network.target

[Service]
# run as a dedicated user (nologin), not root
User=worker
Group=worker
WorkingDirectory=/opt/worker
ExecStart=/opt/worker/run.sh
# dies abnormally → restart
Restart=on-failure

# --- hardening ---
# forbid the process escalating its own privileges
NoNewPrivileges=true
# the whole filesystem is read-only to this process
ProtectSystem=strict
# can't see /home
ProtectHome=true
# its own private /tmp (other processes can't see it)
PrivateTmp=true
# writable only in this folder (an exception to ProtectSystem)
ReadWritePaths=/opt/worker/data
# drop all special capabilities (bind port<1024, change system time, etc.) — add back only what's needed
CapabilityBoundingSet=

[Install]
WantedBy=multi-user.target
```
```bash
sudo systemctl daemon-reload && sudo systemctl enable --now worker
```
> 💡 **Explain — hardening directives:** `ProtectSystem=strict` + `ReadWritePaths` = the process can write only in allowed folders, so even if breached it can't modify system files · `PrivateTmp` = prevents temp-file leakage between processes · an empty `CapabilityBoundingSet=` = drops all special privileges (e.g. binding port < 1024, changing system time)

**Scheduled jobs (instead of cron)** — `.service` (Type=oneshot) + `.timer`
```ini
# /etc/systemd/system/cleanup.service — the job the timer calls
[Service]
# runs once then exits
Type=oneshot
# run as the same service user
User=worker
ExecStart=/opt/worker/cleanup.sh
```
```ini
# /etc/systemd/system/cleanup.timer — the schedule
[Timer]
# every day at 02:00
OnCalendar=*-*-* 02:00:00
# if the machine was off at that time, run it on next boot
Persistent=true

[Install]
WantedBy=timers.target
```
```bash
sudo systemctl enable --now cleanup.timer
systemctl list-timers          # see all scheduled jobs + next run
```

**Restart / view logs** — grant via group `app-deploy` for those commands only (add to the existing sudoers line)
```
%app-deploy ALL=(root) NOPASSWD: /bin/systemctl restart worker, /bin/systemctl status worker
```
```bash
sudo systemctl restart worker
```

**A service's logs — go to journald automatically**

A service run via systemd **needs no log setup of its own** — everything ExecStart prints to stdout/stderr is captured by journald · retention = `journald.conf` (daily, 90 days, set in Appendix B) covers it
```bash
journalctl -u worker -f                              # watch logs live
journalctl -u worker --since today                   # today only
journalctl -u worker --since "2026-10-17" --until "2026-10-18"   # a day back
journalctl -u worker -p err                          # error level only
```
> 💡 **Why you don't see a log file:** these services don't write files in `/var/log/` like Nginx/Tomcat — they log into **journald** (binary), viewed with `journalctl -u <name>` · it has retention and lets you search by day/level out of the box
> 💡 **If a service writes its own log file** (e.g. `/opt/worker/logs/app.log`) → add logrotate like 5.8 to rotate daily, keep 90:
> ```
> /opt/worker/logs/*.log {
>     daily
>     rotate 90
>     compress
>     missingok
>     notifempty
>     copytruncate
>     su worker worker
> }
> ```

> 💡 If a service needs MySQL → create a separate DB user granting only the db/tables it uses (like section 4); don't reuse the main app's user

---
