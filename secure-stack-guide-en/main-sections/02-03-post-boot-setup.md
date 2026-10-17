## 3. Post-boot setup [Critical]

### 3.1 Update the system (manually controlled — no auto-update)

```bash
sudo apt update && sudo apt full-upgrade -y     # first update right after install
```
> 💡 **Explain — why not enable auto-update:** `unattended-upgrades` installs security updates on its own in the middle of the night, which sometimes bumps a library/JVM/MySQL that affects the app with nobody aware, and the app breaks by morning · we choose to **patch manually on a schedule + test in staging first** to control what gets updated and when

```bash
# regular patch cycle (e.g. monthly):
sudo apt update && apt list --upgradable        # see what's available to upgrade
sudo apt install --only-upgrade <package>        # upgrade only what you've verified in staging
```
> 💡 To know whether security updates are pending without installing them automatically: `unattended-upgrades --dry-run -d` (just shows, doesn't install)

### 3.2 Create role groups by permission, then create users and add them to groups

> 💡 **Concept (RBAC):** define "permissions" on the **group**, not on the person — real permissions (sudo, file read/write) are bound to the group once · adding a teammate = create a user then `usermod -aG <group>` · removing someone = drop them from the group — never edit per-person permissions

**Step 1 — create role groups (define permissions)**
```bash
sudo groupadd app-deploy      # permission: drop war + restart tomcat
sudo groupadd app-logview     # permission: read tomcat logs only
# admin uses the existing `sudo` group (full sudo) · the service account `tomcat` (runs the app) is created in section 5
```

**Step 2 — bind permissions to the groups**
```bash
# app-deploy: restart/status tomcat via sudo, those commands only (visudo guards against syntax errors)
sudo visudo -f /etc/sudoers.d/app-deploy
#   %app-deploy ALL=(root) NOPASSWD: /bin/systemctl restart tomcat, /bin/systemctl status tomcat

echo "umask 027" | sudo tee -a /etc/profile   # new files are group-readable, outsiders can't see them
```
> 💡 The "write war" permission for `app-deploy` and "read log" for `app-logview` are **ACLs on folders**, set after Tomcat is installed — app-deploy → **section 7.1**, app-logview → **section 5.6** (here we just create the groups first)

**Step 3 — a reusable function to create users** — login by SSH key, no password
```bash
create_user() {                                  # usage: create_user <name>  (needs file <name>.pub in cwd)
  U=$1
  sudo adduser --disabled-password "$U"
  sudo -u "$U" mkdir -p /home/$U/.ssh
  sudo -u "$U" tee /home/$U/.ssh/authorized_keys < ${U}.pub
  sudo chmod 700 /home/$U/.ssh && sudo chmod 600 /home/$U/.ssh/authorized_keys
}
```

**Step 4 — create users and add them to groups by permission**
```bash
create_user somchai   && sudo usermod -aG sudo        somchai    # admin (full sudo)
create_user deployer  && sudo usermod -aG app-deploy  deployer   # deploy war + restart
create_user logviewer && sudo usermod -aG app-logview logviewer  # view logs only

# one person can hold several permissions = add to several groups, e.g. both deploy and log view:
#   sudo usermod -aG app-deploy,app-logview someone
```
> 💡 **Summary:** `sudo` = full admin · `app-deploy` = drop war + restart · `app-logview` = read logs only · put each person in the group they need — add/remove people later at the group, never touch permissions
> 💡 **Why `visudo`:** it checks syntax before saving and warns on typos — if the sudoers file breaks, `sudo` stops working machine-wide and is hard to recover
> ⚠️ **Service user for non-Tomcat work:** if you have a background process that isn't the WAR, create a separate service user (nologin) per section 8 — for this stack `tomcat` (section 5) is already the service account running the app

### 3.3 SSH hardening

Edit `/etc/ssh/sshd_config`:
```
# forbid direct root login
PermitRootLogin no
# disable passwords, keys only
PasswordAuthentication no
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 3
# allow only the listed users (include everyone who needs access)
AllowUsers somchai deployer logviewer
```
> ⚠️ sshd_config also **does not support end-of-line comments** — appending `# ...` after `AllowUsers` would be counted as an extra username · comments must be on their own line
```bash
# open a NEW terminal and confirm you can ssh in with your key BEFORE restarting (avoid locking yourself out)
sudo systemctl restart ssh
```
> ⚠️ **Avoid locking yourself out:** if `AllowUsers` doesn't include the user you're on, or you haven't installed their key, the moment you restart you'll never SSH in again — **keep one logged-in session open** and test thoroughly first

### 3.4 UFW firewall

```bash
sudo ufw default deny incoming       # deny all inbound by default
sudo ufw default allow outgoing      # allow outbound (so apt/certbot work)
sudo ufw allow 22/tcp                # SSH — can restrict to office IPs: ufw allow from <ip> to any port 22
sudo ufw allow 80,443/tcp            # web, via Nginx
sudo ufw enable
```
> 💡 **Explain:** least-exposure principle — open only the ports that must accept external traffic (22/80/443), close the rest · **MySQL (3306) and Tomcat (8080/8009) stay closed** because they only talk internally over 127.0.0.1; even if you forget to bind them, the firewall still blocks them as a second layer

### 3.5 fail2ban + sysctl [Hardening]

```bash
sudo apt install -y fail2ban      # catches IPs that repeatedly fail SSH login and temporarily bans them
```
`/etc/sysctl.d/99-hardening.conf` (tune kernel/network parameters to be safer):
```
# prevent IP spoofing
net.ipv4.conf.all.rp_filter=1
# don't answer broadcast pings (prevent smurf)
net.ipv4.icmp_echo_ignore_broadcasts=1
# don't accept ICMP redirects (prevent MITM)
net.ipv4.conf.all.accept_redirects=0
# prevent SYN flood
net.ipv4.tcp_syncookies=1
# full ASLR (prevent memory exploits)
kernel.randomize_va_space=2
```
```bash
sudo sysctl --system      # load the new values immediately
```

### 3.6 Audit — trace retroactively who came in and did what [High]

Split into 3 layers: who logged in/out (login), who used sudo for what, and which commands/files were touched

**1) Login history (built in, nothing to install)**
```bash
last                               # who logged in/out, when, and from which IP
lastlog                            # last login per user
sudo grep sshd /var/log/auth.log   # SSH detail (success/failure + key fingerprint)
```

**2) sudo usage — recorded automatically**
```bash
sudo grep sudo /var/log/auth.log   # every sudo command + who ran it (e.g. when deployer restarted tomcat)
```

**3) auditd — record commands and touches of important files**
```bash
sudo apt install -y auditd audispd-plugins
```
Add rules to `/etc/audit/rules.d/hardening.rules`:
```
# record every executed command with the user
-a always,exit -F arch=b64 -S execve -k exec

# watch deploys / Tomcat file changes
-w /opt/tomcat/webapps/ -p wa -k tomcat_deploy
-w /opt/tomcat/conf/ -p wa -k tomcat_conf

# watch user/permission changes
-w /etc/passwd -p wa -k identity
-w /etc/sudoers.d/ -p wa -k sudoers
```
```bash
sudo augenrules --load && sudo systemctl restart auditd
```
Search retroactively:
```bash
sudo ausearch -ua deployer -i          # every event by user deployer (-i = human-readable)
sudo ausearch -k tomcat_deploy -i      # when the war was dropped/changed, and by whom
sudo aureport -u --summary             # activity summary per user
```

**Audit log retention — rotate daily, keep 90 days**

auditd has no built-in "rotate by day," but it rotates its file on a `SIGUSR1` signal — we send that signal once a day via a systemd timer and set `num_logs=90` = keep 90 files ≈ 90 days (one file per day, easy to trace)

`/etc/audit/auditd.conf`:
```
# keep 90 files (= 90 days when rotating daily)
num_logs = 90
# MB per file (safety cap against a day with an abnormal event spike)
max_log_file = 200
# if a single day's file exceeds the cap, rotate early
max_log_file_action = ROTATE
# disk left < 1000MB → warn
space_left = 1000
space_left_action = email
# disk will fill so audit can't write → go single-user (strict compliance uses halt)
admin_space_left_action = single
```
Daily rotation timer — `/etc/systemd/system/audit-rotate.service` + `.timer`:
```ini
# audit-rotate.service — signals auditd to rotate the log once a day
[Service]
# runs once then exits, doesn't stay as a daemon
Type=oneshot
# SIGUSR1 = tell auditd to rotate its log
ExecStart=/bin/systemctl kill -s SIGUSR1 auditd
```
```ini
# audit-rotate.timer — schedules the service above
[Timer]
# rotate at the start of every day (00:05)
OnCalendar=*-*-* 00:05:00
# if the machine was off at that time, run it on next boot
Persistent=true

[Install]
WantedBy=timers.target
```
```bash
sudo systemctl daemon-reload
sudo systemctl restart auditd
sudo systemctl enable --now audit-rotate.timer
```
> 💡 **Explain:** the systemd timer sends SIGUSR1 once a day so auditd rotates → you get `audit.log.1` … `audit.log.90` (90 days back, one file per day) · `max_log_file` is only a safety net for abnormal event spikes · if policy requires more than 90 days → ship to a central server (Appendix C)

> 💡 **Explain:** `ausearch -k <key>` searches by the tag set in a rule — `-k tomcat_deploy` answers "when was the war dropped, by which user," exactly what you want for deploy auditing · `ausearch -ua <user>` = everything that user did
> 💡 For an admin who wants to record **every keystroke/command**: add `session required pam_tty_audit.so enable=*` to `/etc/pam.d/sshd`
> ⚠️ **Stop attackers erasing their tracks:** you should also **ship logs off the machine** (central syslog/log server) — if logs live only on the machine, whoever gets root can delete them

### 3.7 Set timezone + keep time in sync (NTP) [High]

```bash
# 1) set the timezone
timedatectl list-timezones | grep Bangkok     # find the correct timezone name
sudo timedatectl set-timezone Asia/Bangkok     # or UTC (see note)

# 2) enable NTP so time syncs automatically
sudo timedatectl set-ntp true                  # enables systemd-timesyncd

# 3) verify
timedatectl                                    # you should see:
#   Time zone: Asia/Bangkok (+07, +0700)
#   System clock synchronized: yes
#   NTP service: active
```
> 💡 **Pick one standard timezone across the fleet:** many organizations set servers to **UTC** to avoid DST/timezone confusion when correlating logs across regions · if the team finds Thai time easier for reading logs you can use `Asia/Bangkok`, but **it must be identical on every machine** · changing the timezone affects timestamps of logs written **after that** (old ones don't change)
> 💡 **JVM/Tomcat** use the OS timezone already · to force it explicitly, add `-Duser.timezone=Asia/Bangkok` in `setenv.sh` (5.7)
> 💡 **Explain — why it matters for logs:** every log relies on timestamps · if the machine's clock is off you **can't correlate events across systems/machines** and logs can't be used as evidence · standards (e.g. PCI-DSS req. 10.6) **require** every machine to sync to the same time source · to point NTP at an internal org server, edit `NTP=` in `/etc/systemd/timesyncd.conf`

---
