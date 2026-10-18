# Secure Stack Installation Guide

### Ubuntu · Nginx · Tomcat · MySQL

`Updated 2026-10-17`

A step-by-step installation guide from a bare machine to a running, secured system — follow sections 1 → 10 in order.

**Before you start**
- 🧪 Always test in **staging** before touching production
- 🔒 Do **not** skip **section 2** (disk encryption) — it cannot be done retroactively

**Severity labels** — `[Critical]` must not skip · `[High]` should do · `[Hardening]` optional extra

**How to read** — each section has 💡 **Explain** (why / how it works) and ⚠️ **Caution** (where it breaks) · replace `<...>` placeholders and sample names (`somchai`, `yourdomain.com`) with your real values

---

## Table of Contents

**Install & Configure**

| # | Section | Covers |
|---|---|---|
| 1 | Preparation | Ubuntu version, prerequisites |
| 2 | Install Ubuntu + LUKS | disk encryption, remote unlock |
| 3 | Post-boot setup | update, user/role groups, SSH, firewall, audit, NTP |
| 4 | MySQL | bind localhost, least-privilege user |
| 5 | Tomcat 9 | systemd, JVM heap/GC, logging + retention |
| 6 | Nginx + TLS | reverse proxy, security headers, access log |
| 7 | Deploy app (WAR) | file-drop, ACL permissions |
| 8 | Other services | systemd hardening, timers, logging |
| 9 | Edit WAR & share files | ACL, shared group |
| 10 | Post-install check | checklist |

**Appendix**

| | Section |
|---|---|
| A | Log retention standards |
| B | Per-log details |
| C | Ship logs to a central server |
| D | Troubleshooting runbook |
| E | Preventive maintenance |

---

## 1. Preparation

### 1.1 Supported Ubuntu versions

This guide is tested on **Ubuntu Server LTS** — use LTS only for production (long support, continuous patching).

| Version | Status | Recommended |
|---|---|---|
| **24.04 LTS** (Noble) | supported until 2029 (ESM 2034) | ✅ **Recommended** — newest proven release |
| **22.04 LTS** (Jammy) | supported until 2027 (ESM 2032) | ✅ Supported — if your existing systems use it |
| **20.04 LTS** (Focal) | standard support ended (ESM only) | ⚠️ Avoid for new installs |
| **26.04 LTS** (if released) | very new | ⚠️ Wait for the first patch round + verify packages are ready |
| non-LTS (e.g. 25.x) | only 9 months of support | ❌ Don't use on servers |

> 💡 Commands in this guide target **24.04 / 22.04** · on other versions, verify package names/paths (e.g. `default-jre`, the MySQL config path) match

### 1.2 Prerequisites

- Ubuntu Server ISO **24.04 LTS** (recommended) or **22.04 LTS**
- **An SSH key pair per person**, generated on their own machine (not on the server) with the command below. Keep the **private key only on that person's machine**; hand only the `.pub` file to the admin to install on the server

```bash
ssh-keygen -t ed25519 -C "somchai@company"      # produces ~/.ssh/id_ed25519 (private) + .pub (public)
```

- A domain name whose A record points to the server IP (required to obtain a TLS cert in section 6)
- Recommended minimum spec: 2 vCPU / 4 GB RAM / 40 GB disk or more (MySQL + Tomcat + JVM use a fair amount of RAM)
- Plan ahead: the disk passphrase and where it's stored (password manager / safe) — **somewhere other than the machine**

> 💡 **Explain — why SSH keys, not passwords:** a key is a long, random public/private pair that's practically impossible to guess or brute-force, unlike passwords that people set short and reuse · we disable all password login in section 3 to shut down password-guessing attacks

---

## 2. Install Ubuntu + disk encryption (LUKS) [Critical]

> ⚠️ Must be done during installation — once installed, encrypting later means wiping and reinstalling

1. Boot from the ISO → pick language / keyboard / network
2. On **"Guided storage configuration"** → choose **"Use an entire disk"**
3. Tick ✅ **"Encrypt the LVM group with LUKS"** and set the **disk passphrase**
4. Create the first admin account — **remember this username** (e.g. `somchai`); it becomes the main admin in section 3 and must be added to SSH's `AllowUsers`
5. On "SSH Setup" → enable the OpenSSH server (so you can SSH in right after install)
6. Finish installing and reboot (boot will prompt for the disk passphrase)

> 💡 **Explain — how LUKS works:** LUKS encrypts the whole partition with a master key locked by your passphrase · at boot you must enter the passphrase to unlock the disk before it can mount and continue booting · it protects against a **stolen disk/machine** — pull the disk, plug it into another machine, and it's unreadable · but it does **not** help while the machine is running or is breached over the network (the disk is unlocked then)

**Verify it's actually encrypted** — find the mapper name first (differs per machine):
```bash
lsblk -f | grep crypto_LUKS          # seeing type crypto_LUKS = the partition is encrypted
lsblk                                # look for the mapper name e.g. dm_crypt-0 or <disk>_crypt
sudo cryptsetup status <mapper-name> # replace <mapper-name> with what you saw → should show type: LUKS2
```

### 2.1 Remote unlock at reboot (headless machines) [High]

Every reboot the machine **waits for the passphrase before booting**. For a data-center machine with no monitor, set up a remote unlock method **before** going live.

**Option A — Dropbear (type the passphrase over SSH at boot)**
```bash
sudo apt install -y dropbear-initramfs
# 1) add the public key used for unlock (can be a different file from the normal authorized_keys)
sudo tee /etc/dropbear/initramfs/authorized_keys < unlock_key.pub
# 2) set a static IP for initramfs (required! otherwise you can't SSH in at boot)
#    edit /etc/initramfs-tools/initramfs.conf, add a line (IP=client::gateway:netmask::iface:off):
#    IP=10.0.0.10::10.0.0.1:255.255.255.0::eth0:off
sudo update-initramfs -u
```
At boot: SSH to the machine IP (the initramfs's port 22) and run the unlock command:
```bash
ssh -i unlock_key root@10.0.0.10
cryptroot-unlock          # enter the passphrase → the machine continues booting
```
> ⚠️ **Caution:** if you skip the static IP step the machine boots and hangs with SSH unreachable — you'd have to attach a physical monitor. **Test one reboot in staging** to be sure remote unlock works before going to production

**Option B — Clevis + TPM2 (auto-unlock via the TPM chip)**
```bash
sudo apt install -y clevis clevis-luks clevis-initramfs
lsblk                                        # find the crypto_LUKS partition, e.g. /dev/sda3
sudo clevis luks bind -d /dev/sda3 tpm2 '{}' # bind the key to this machine's TPM
sudo update-initramfs -u
```
> 💡 **Explain:** the TPM stores the key in a chip on the motherboard, so this machine can boot itself without typing a passphrase · but **move the disk to another machine and there's no TPM → it can't unlock** (which is exactly what we want) · suited to machines that reboot themselves often · **always keep a backup passphrase** in case the TPM/motherboard fails

> 💡 **Cloud (AWS/GCP/Azure):** you can skip section 2 entirely — enable the provider's disk encryption when creating the volume instead (EBS encryption / CMEK); it auto-unlocks via KMS with no dropbear/TPM to deal with

---

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

## 4. Install & configure MySQL [Critical]

```bash
sudo apt install -y mysql-server
sudo systemctl enable --now mysql
sudo mysql_secure_installation      # remove anonymous user, test db, disable remote root
```
> 💡 **Explain — what `mysql_secure_installation` does:** a wizard that removes risky defaults (anonymous accounts, the `test` database, remote root login) · you can answer Yes to all except "Validate Password Component," which enforces password complexity (choose per your team policy)

bind localhost — `/etc/mysql/mysql.conf.d/mysqld.cnf`:
```ini
[mysqld]
bind-address = 127.0.0.1       # accept connections only from the local machine — no external access
local_infile = 0               # disable LOAD DATA LOCAL (prevents reading client-side files via SQL)
skip_symbolic_links = 1        # prevent using symlinks to point across directories
```
```bash
sudo systemctl restart mysql
```

Create a database + a least-privilege user:
```bash
sudo mysql        # enter the MySQL shell as root (via socket, no password needed)
```
```sql
CREATE DATABASE appdb CHARACTER SET utf8mb4;
CREATE USER 'app'@'127.0.0.1' IDENTIFIED BY '<long random password>';
GRANT SELECT,INSERT,UPDATE,DELETE ON appdb.* TO 'app'@'127.0.0.1';   -- only what the app uses
-- never GRANT ALL / *.* / 'app'@'%'  (that becomes a god user that can connect from anywhere)
FLUSH PRIVILEGES;
```
> 💡 **Explain — DB least privilege:** the app should use a user that can only do CRUD on `appdb` · if the app is hit by SQL injection the attacker is confined to that scope — can't DROP tables, read other databases, or create new users
> ⚠️ **A common gotcha — caching_sha2_password:** MySQL 8 uses `caching_sha2_password` auth by default, which **old JDBC connectors (Connector/J < 8.0) can't connect with** and throw an auth error — fix by **using Connector/J 8.0+ in the app** (the right way), or if truly necessary change the user's auth: `ALTER USER 'app'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '<password>';`
> 💡 No encryption at MySQL — data on disk is already covered by LUKS · MySQL passwords are hashed automatically

---

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

## 6. Install & configure Nginx + TLS [Critical]

> 💡 **Explain — Nginx structure:** the config has 3 nested levels — **`http {}`** (settings for all servers), **`server {}`** (one site/domain), **`location {}`** (a URL path within the site) · each directive **must sit at the right level** or `nginx -t` fails

### 6.1 Install + set server_name first

```bash
sudo apt install -y nginx
sudo systemctl enable --now nginx
```
Edit the default site `/etc/nginx/sites-available/default` and set `server_name` to match the domain (certbot needs it to locate the block):
```nginx
server {
    listen 80;
    server_name yourdomain.com;        # ← change to the real domain
    location / {
        proxy_pass http://127.0.0.1:8080;        # forward to Tomcat
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```
```bash
sudo nginx -t && sudo systemctl reload nginx
```
> ⚠️ **Before requesting a cert, these must be set:** (1) the DNS A record for `yourdomain.com` points to the machine IP, (2) UFW has 80/443 open (section 3.4), (3) `server_name` matches — otherwise certbot can't obtain the cert

### 6.2 Obtain a TLS certificate (Let's Encrypt)

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d yourdomain.com     # certbot edits the server block to add listen 443 + cert + redirect automatically
```
> 💡 certbot adds `listen 443 ssl`, the cert paths, and the 80→443 redirect into the server block for you, and sets up automatic renewal (certs last 90 days)

### 6.3 Add security settings

Put **in `http {}`** of `/etc/nginx/nginx.conf` (applies to all sites):
```nginx
server_tokens off;                     # hide the Nginx version in headers / error pages
client_max_body_size 10m;              # limit request size (prevent upload floods)
client_body_timeout 10s;
client_header_timeout 10s;

# security headers (effective after HTTPS from 6.2)
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;  # force HTTPS
add_header X-Content-Type-Options "nosniff" always;                                  # prevent MIME sniffing
add_header X-Frame-Options "SAMEORIGIN" always;                                      # prevent clickjacking
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
```
certbot already set `ssl_protocols` / `ssl_ciphers` in `options-ssl-nginx.conf` — don't set them again
```bash
sudo nginx -t && sudo systemctl reload nginx
```
> 💡 **Explain — why Nginx in front of Tomcat:** Nginx terminates external HTTPS then proxies as HTTP to Tomcat on localhost — Tomcat is never exposed directly, cert/TLS is managed in one place, and requests can be filtered at the front (rate limit, body size)

### 6.4 Log & retention (Nginx) [High]

Nginx is the **primary record of who visits the site** because it's at the front and sees the **user's real IP** · two files:

| File | Records what |
|---|---|
| `/var/log/nginx/access.log` | every request: real IP, time, `"METHOD /path"`, status, bytes, referer, user-agent |
| `/var/log/nginx/error.log` | Nginx's own errors (bad config, upstream down, TLS problems) |

**Log format (complete, consistent with Tomcat 5.9):** the default `combined` is nearly complete but lacks response time — define your own format in `http {}` of `/etc/nginx/nginx.conf`:
```nginx
log_format rich '$remote_addr - $remote_user [$time_local] '
                '"$request" $status $body_bytes_sent $request_time '
                '"$http_referer" "$http_user_agent"';
access_log /var/log/nginx/access.log rich;
```
```
203.0.113.5 - - [17/Oct/2026:19:40:12 +0700] "POST /app/orders/create HTTP/1.1" 200 512 0.048 "https://site/app/orders" "Mozilla/5.0 ..."
```
**Each field:** `$remote_addr` real IP · `$remote_user` user from HTTP auth (session login = `-`) · `"$request"` **method + page/endpoint** · `$status` · `$body_bytes_sent` · `$request_time` **response time (seconds)** · `"$http_referer"` **which page it came from** · `"$http_user_agent"` browser · then `sudo nginx -t && sudo systemctl reload nginx` to apply

**Retention:** Ubuntu already ships logrotate for Nginx at `/etc/logrotate.d/nginx` (default `rotate 14` = keep 14 days) — adjust to match policy:
```bash
sudo sed -i 's/rotate 14/rotate 90/' /etc/logrotate.d/nginx   # keep 90 days to match the other logs
sudo logrotate -d /etc/logrotate.d/nginx                      # dry-run check
```
```bash
# watch live who's coming in:
sudo tail -f /var/log/nginx/access.log
# summarize the top IPs by hits:
sudo awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head
```
> 💡 **Summary of the "who came in" log layers:**
> - **SSH/host login** (sysadmins) → `last`, `/var/log/auth.log`, auditd (section 3.6)
> - **external web visits** (general users) → **Nginx access.log** (real IP + URL) — the primary source
> - **app level** (session, response time) → Tomcat access log (section 5.9)
> - **the logged-in username in the app** → the app must write its own log
> ⚠️ Set the access.log retention **long enough for audit** (e.g. 90 days+) because investigations usually need to look back at request logs

---

## 7. Deploy the app (WAR on Tomcat)

The app is a **WAR running inside Tomcat** → **Tomcat (user `tomcat`) is the service user that runs the app**; no separate systemd service and no need to log in as `tomcat`
With manager/tomcat-users disabled, deploy by **file-drop (autoDeploy)**: drop the war into webapps and Tomcat expands it itself

### 7.1 Let the `app-deploy` group drop wars (one-time, via ACL)

```bash
sudo chown tomcat:tomcat /opt/tomcat/webapps
sudo chmod 750 /opt/tomcat/webapps
# ACL: service tomcat can always read the war + group app-deploy can write/overwrite the war
sudo setfacl -R  -m g:tomcat:rX -m g:app-deploy:rwX /opt/tomcat/webapps
sudo setfacl -R -d -m g:tomcat:rX -m g:app-deploy:rwX /opt/tomcat/webapps   # new wars inherit the permissions
```
> 💡 **Explain — why ACL, not the tomcat group:** the Tomcat process (user `tomcat`) must read the war, and the deployer must write it · the default ACL makes a war newly dropped by `app-deploy` **automatically readable by `tomcat` and overwritable by `app-deploy`** — the deployer only needs to be in `app-deploy`, **not a member of group `tomcat`** (cleaner separation of the role from the service account)

### 7.2 Deploy the WAR

Do it as the deploy user (not root):
```bash
# filename = context path:  app.war → https://domain/app   |   ROOT.war → https://domain/
cp app.war /opt/tomcat/webapps/
```
Tomcat autoDeploy expands the war in a few seconds **with no restart** — check the log to confirm:
```bash
tail -f /opt/tomcat/logs/catalina.out      # see "Deployment of web application archive ... has finished"
```
> 💡 **autoDeploy** is a Tomcat 9 default that watches the webapps folder and expands any new/changed war itself · **to update a version:** drop a war of the same name over the old one and Tomcat undeploys the old then deploys the new

### 7.3 Restart Tomcat (only when necessary)

e.g. after editing server.xml / JVM opts, a restart is required:
```bash
sudo systemctl restart tomcat      # a user in group app-deploy, via sudo for that command only
```
The sudoers entry (`/etc/sudoers.d/app-deploy`) was set in section 3:
```
%app-deploy ALL=(root) NOPASSWD: /bin/systemctl restart tomcat, /bin/systemctl status tomcat
```
> 💡 **Who does what:** `tomcat` = owns the process (nologin) · group `app-deploy` = drop war (ACL) + restart (sudo) · group `app-logview` = read logs · group `sudo` = full admin
> 💡 **Backup:** if you ship backups off the machine (S3 / a standby host) **encrypt the backup files separately** (e.g. `gpg`) because LUKS only covers the local disk, not files that leave it

---

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

## 9. Edit files in the WAR & share files across services

### 9.1 Edit files in a deployed WAR

The deployed WAR at `/opt/tomcat/webapps/app/` belongs to `tomcat:tomcat`

- **Recommended: don't edit the exploded directory directly** — Tomcat may re-explode over it or redeploy and lose your edit → edit the **source → build a new war → drop it over** (the war is the source of truth)
- If you must hotfix (e.g. edit config.properties) do it **as the `tomcat` user** so file ownership stays correct:
```bash
sudo -u tomcat vi /opt/tomcat/webapps/app/WEB-INF/classes/config.properties
# if you accidentally edited it as the deploy user, restore ownership:
sudo chown tomcat:tomcat <file>
```
> ⚠️ Don't `chmod 777` to make editing easy — it lets every user modify the app's files · `sudo -u tomcat` is the cleanest and safest way

### 9.2 Share files across services (e.g. Tomcat ↔ Hive/Hadoop on the local FS)

Each service runs as a different user — grant mutual access **without opening 777** using a **shared group + setgid + (if complex) ACL**
```bash
# 1) a shared group for exchanging data
sudo groupadd datax

# 2) add both service users to the group
sudo usermod -aG datax tomcat
sudo usermod -aG datax hive

# 3) the shared folder: group + setgid (new files get group datax automatically)
sudo chown tomcat:datax /data/exchange
sudo chmod 2770 /data/exchange        # 2750 if the other side only reads
```
Have the writing service set the umask in its systemd unit so the group can read:
```ini
[Service]
# new files = 640, folders = 750
UMask=0027
```
If you need fine-grained permissions / can't change ownership → use **POSIX ACL**:
```bash
sudo setfacl -R  -m g:datax:rX /data/exchange     # grant now
sudo setfacl -R -d -m g:datax:rX /data/exchange   # default: new files inherit
getfacl /data/exchange                            # verify
```
> 💡 **Explain — `rX` (capital X):** grants execute **only on folders** (needed to enter a folder) but **doesn't set execute on plain data files** — safer than lowercase `rx` which would make every file executable

Principle: **the file-creating side owns it; the consuming side gets only `r`/`rX`** — don't grant write unless needed

> ⚠️ **If the files live on HDFS (not local disk):** the POSIX permissions above don't apply; use HDFS's own permissions (`hdfs dfs -chmod`, `hdfs dfs -setfacl`) + Kerberos/Ranger if security is enabled — the shared-group pattern only works when both services share a folder on the same machine/mount (if you want a full HDFS section, say whether it's single node or a cluster and whether Kerberos is used)

---

## 10. Post-install check

Run each item; if one fails, go back and fix that section before going to production:

- [ ] `lsblk -f | grep crypto_LUKS` — disk really encrypted
- [ ] **test one reboot** and confirm remote unlock works (if using dropbear/TPM) — most important, don't skip
- [ ] `sudo ufw status` — only 22/80/443 open; 3306 and 8080/8009 closed
- [ ] `ssh root@host` is refused and password login doesn't work
- [ ] `ss -tulpn` — MySQL/Tomcat listen only on 127.0.0.1
- [ ] `sudo -u tomcat -s` — the service user `tomcat` can't log in (nologin)
- [ ] `getent group sudo app-deploy app-logview tomcat` — each group's members are correct
- [ ] `sudo -l -U deployer` — deployer has sudo only for restart/status tomcat
- [ ] `sudo -l -U logviewer` — logviewer has **no sudo** / `sudo -u logviewer tail /opt/tomcat/logs/catalina.out` can read but not write/delete
- [ ] `last` / `sudo ausearch -k tomcat_deploy -i` — you can trace back who logged in and who dropped a war
- [ ] set retention **all logs = daily, keep 90 days**: Tomcat `maxDays` + logrotate (`catalina.out`, `gc.log`, Nginx) + auditd timer (daily SIGUSR1, `num_logs=90`) + journald (`MaxFileSec=1day`, `MaxRetentionSec=90day`)
- [ ] `systemctl list-timers | grep audit-rotate` — the daily audit-rotation timer is active
- [ ] `tail /var/log/nginx/access.log` — you see the **user's real IP** (not 127.0.0.1), and the Tomcat access log also shows the real IP (RemoteIpValve working)
- [ ] `curl -I https://yourdomain.com` — see HSTS, nosniff, and no `Server: nginx/x.x.x`
- [ ] Tomcat's `/manager`, `/examples`, `/docs` are unreachable from outside
- [ ] `mysql -h <public-ip>` from an external machine can't connect + the app can connect to the DB (check the connector works with caching_sha2)
- [ ] the app connects to the DB with the least-privilege user, not root
- [ ] `/opt/tomcat/bin/version.sh` — confirm it's the intended Tomcat 9 version
- [ ] `sudo -u tomcat jcmd $(pgrep -f catalina) VM.flags` — the JVM took the heap/GC values you set
- [ ] `systemctl show -p User <service>` — every background service runs as a dedicated user, not root
- [ ] `systemctl list-timers` — scheduled jobs (if any) are set correctly
- [ ] `sudo certbot renew --dry-run` — TLS renewal works
- [ ] `timedatectl` — time is in sync (NTP active) so log timestamps are accurate

---

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

**Must not miss:** store the LUKS passphrase somewhere other than the machine · **test remote unlock before going live** · keep a session open while editing SSH/firewall · encrypt backups that leave the machine · always test in staging first

_Supported: Ubuntu 24.04 LTS (recommended) / 22.04 LTS · Nginx 1.24+ · Tomcat 9.0.x · MySQL 8.0 · Java 11/17/21 — verify package names/directives/paths match what you actually installed_
