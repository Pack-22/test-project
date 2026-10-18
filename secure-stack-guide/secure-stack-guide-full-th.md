# คู่มือติดตั้ง Secure Stack

### Ubuntu · Nginx · Tomcat · MySQL

`อัปเดต 2026-10-17`

คู่มือติดตั้งแบบ step-by-step ตั้งแต่เครื่องเปล่าจนระบบรันได้และปลอดภัย — ทำตามลำดับหัวข้อ 1 → 10

**ก่อนเริ่ม**
- 🧪 ทดสอบใน **staging** ก่อนทำกับ production เสมอ
- 🔒 ห้ามข้าม **หัวข้อ 2** (การเข้ารหัสดิสก์) — ทำย้อนหลังไม่ได้

**ป้ายกำกับความสำคัญ** — `[Critical]` ห้ามข้าม · `[High]` ควรทำ · `[Hardening]` ทำเพิ่มได้

**วิธีอ่าน** — แต่ละหัวข้อมี 💡 **อธิบาย** (ทำไม/ทำงานยังไง) และ ⚠️ **ระวัง** (จุดพลาดแล้วพัง) · ค่า `<...>` และชื่อตัวอย่าง (`somchai`, `yourdomain.com`) ให้แทนด้วยค่าจริงของคุณ

---

## สารบัญ

**ติดตั้ง & ตั้งค่า**

| # | หัวข้อ | ครอบคลุม |
|---|---|---|
| 1 | เตรียมก่อนติดตั้ง | เวอร์ชัน Ubuntu, สิ่งที่ต้องมี |
| 2 | ติดตั้ง Ubuntu + LUKS | เข้ารหัสดิสก์, unlock ระยะไกล |
| 3 | ตั้งค่าหลังบูต | update, user/role group, SSH, firewall, audit, NTP |
| 4 | MySQL | bind localhost, user จำกัดสิทธิ์ |
| 5 | Tomcat 9 | systemd, JVM heap/GC, log + retention |
| 6 | Nginx + TLS | reverse proxy, security header, access log |
| 7 | Deploy แอป (WAR) | file-drop, สิทธิ์ ACL |
| 8 | Service อื่นๆ | systemd hardening, timer, log |
| 9 | แก้ไฟล์ WAR & แชร์ไฟล์ | ACL, shared group |
| 10 | ตรวจสอบหลังติดตั้ง | checklist |

**ภาคผนวก**

| | หัวข้อ |
|---|---|
| A | มาตรฐานการเก็บ log |
| B | รายละเอียด log แต่ละตัว |
| C | ส่ง log ไป central server |
| D | Runbook แก้ปัญหา |
| E | Preventive Maintenance |

---

## 1. เตรียมก่อนติดตั้ง

### 1.1 เวอร์ชัน Ubuntu ที่รองรับ

คู่มือนี้ทดสอบกับ **Ubuntu Server LTS** — ใช้ LTS เท่านั้นสำหรับ production (support ยาว, แพตช์ต่อเนื่อง)

| เวอร์ชัน | สถานะ | แนะนำ |
|---|---|---|
| **24.04 LTS** (Noble) | support ถึง 2029 (ESM 2034) | ✅ **แนะนำ** — ใหม่สุดที่พิสูจน์แล้ว |
| **22.04 LTS** (Jammy) | support ถึง 2027 (ESM 2032) | ✅ รองรับ — ถ้าระบบเดิมใช้อยู่ |
| **20.04 LTS** (Focal) | หมด standard support (เหลือ ESM) | ⚠️ เลี่ยงสำหรับติดตั้งใหม่ |
| **26.04 LTS** (ถ้าออกแล้ว) | ใหม่มาก | ⚠️ รอ patch รอบแรก + เช็ก package พร้อม |
| non-LTS (เช่น 25.x) | support แค่ 9 เดือน | ❌ ไม่ใช้กับ server |

> 💡 คำสั่งในคู่มือยึดตาม **24.04 / 22.04** · ถ้าใช้เวอร์ชันอื่นให้เช็กชื่อ package/path (เช่น `default-jre`, path ของ MySQL config) ว่าตรงกัน

### 1.2 สิ่งที่ต้องมี

- Ubuntu Server ISO **24.04 LTS** (แนะนำ) หรือ **22.04 LTS**
- **SSH key pair ของแต่ละคน** สร้างที่เครื่องตัวเอง (ไม่ใช่บน server) ด้วยคำสั่งด้านล่าง เก็บ **private key ไว้ที่เครื่องตัวเองเท่านั้น** ส่งเฉพาะไฟล์ `.pub` ให้ admin เอาไปใส่ server

```bash
ssh-keygen -t ed25519 -C "somchai@company"      # ได้ไฟล์ ~/.ssh/id_ed25519 (private) + .pub (public)
```

- Domain name ที่ชี้ A record มาที่ IP server (จำเป็นสำหรับขอ TLS cert ในหัวข้อ 6)
- สเปกขั้นต่ำแนะนำ: 2 vCPU / 4 GB RAM / 40 GB ดิสก์ ขึ้นไป (MySQL + Tomcat + JVM กินแรมพอควร)
- วางแผนไว้ล่วงหน้า: passphrase ดิสก์ และที่เก็บ (password manager / ตู้เซฟ) **คนละที่กับเครื่อง**

> 💡 **อธิบาย — ทำไมใช้ SSH key ไม่ใช้รหัสผ่าน:** key เป็นคู่กุญแจ public/private ที่ยาวและสุ่ม เดา/brute force แทบไม่ได้ ต่างจากรหัสผ่านที่คนตั้งสั้นและซ้ำ · เราจะปิด password login ทั้งหมดในหัวข้อ 3 เพื่อตัดการโจมตีแบบเดารหัส

---

## 2. ติดตั้ง Ubuntu + เข้ารหัสดิสก์ (LUKS) [Critical]

> ⚠️ ต้องทำตอนติดตั้งเท่านั้น — ลงไปแล้วมาเข้ารหัสทีหลังต้องล้างลงใหม่

1. บูตจาก ISO → เลือกภาษา / คีย์บอร์ด / เน็ตเวิร์ก
2. หน้า **"Guided storage configuration"** → เลือก **"Use an entire disk"**
3. ติ๊ก ✅ **"Encrypt the LVM group with LUKS"** แล้วตั้ง **passphrase ดิสก์**
4. สร้าง admin account แรก — **จำชื่อ user นี้ไว้** (เช่น `somchai`) จะใช้เป็น admin หลักต่อในหัวข้อ 3 และต้องใส่ใน `AllowUsers` ของ SSH
5. หน้า "SSH Setup" → ติ๊กเปิด OpenSSH server (จะได้ SSH เข้าได้ทันทีหลังลงเสร็จ)
6. ติดตั้งจนเสร็จ รีบูต (ตอนบูตจะถาม passphrase ดิสก์)

> 💡 **อธิบาย — LUKS ทำงานยังไง:** LUKS เข้ารหัสทั้ง partition ด้วย master key ที่ล็อกด้วย passphrase ของคุณ · ตอนบูตต้องใส่ passphrase เพื่อปลดล็อก ดิสก์ ถึงจะ mount และบูตต่อได้ · ป้องกันกรณี **ดิสก์/เครื่องถูกขโมย** — ถอดดิสก์ไปเสียบเครื่องอื่นก็อ่านไม่ออก · แต่ **ไม่ช่วย**ตอนเครื่องเปิดรันอยู่หรือโดนเจาะผ่านเน็ต (ตอนนั้น ดิสก์ ปลดล็อกแล้ว)

**ตรวจว่าเข้ารหัสจริง** — หา mapper name ก่อน (ชื่อต่างกันแต่ละเครื่อง):
```bash
lsblk -f | grep crypto_LUKS          # เห็น type crypto_LUKS = partition ถูกเข้ารหัส
lsblk                                # ดูชื่อ mapper เช่น dm_crypt-0 หรือ <disk>_crypt
sudo cryptsetup status <mapper-name> # แทน <mapper-name> ด้วยชื่อที่เห็น → ต้องขึ้น type: LUKS2
```

### 2.1 ปลดล็อกระยะไกลตอนรีบูต (เครื่อง headless) [High]

ทุกครั้งที่รีบูต เครื่องจะ**ค้างรอ passphrase ก่อนบูต** ถ้าเป็นเครื่องในศูนย์ข้อมูลไม่มีจอ ต้องตั้งวิธีปลดล็อกจากระยะไกล **ก่อน**เอาขึ้นจริง

**ตัวเลือก A — Dropbear (พิมพ์ passphrase ผ่าน SSH ตอนบูต)**
```bash
sudo apt install -y dropbear-initramfs
# 1) ใส่ public key สำหรับ unlock (คนละไฟล์กับ authorized_keys ปกติได้)
sudo tee /etc/dropbear/initramfs/authorized_keys < unlock_key.pub
# 2) ตั้ง static IP ให้ initramfs (จำเป็น! ไม่งั้น SSH เข้าตอนบูตไม่ได้)
#    แก้ /etc/initramfs-tools/initramfs.conf เพิ่มบรรทัด (IP=client::gateway:netmask::iface:off):
#    IP=10.0.0.10::10.0.0.1:255.255.255.0::eth0:off
sudo update-initramfs -u
```
ตอนบูต: SSH เข้าไปที่ IP เครื่อง (port 22 ของ initramfs) แล้วรันคำสั่งปลดล็อก:
```bash
ssh -i unlock_key root@10.0.0.10
cryptroot-unlock          # ใส่ passphrase → เครื่องบูตต่อ
```
> ⚠️ **ระวัง:** ถ้าข้ามขั้นตั้ง static IP เครื่องจะบูตมาค้างโดย SSH เข้าไม่ได้ ต้องไปต่อจอที่เครื่องจริง — **ทดสอบรีบูต 1 รอบใน staging** ให้แน่ใจว่า unlock ระยะไกลได้ก่อนขึ้น production

**ตัวเลือก B — Clevis + TPM2 (ปลดล็อกอัตโนมัติด้วยชิป TPM)**
```bash
sudo apt install -y clevis clevis-luks clevis-initramfs
lsblk                                        # หา partition ที่เป็น crypto_LUKS เช่น /dev/sda3
sudo clevis luks bind -d /dev/sda3 tpm2 '{}' # ผูก key กับ TPM ของเครื่องนี้
sudo update-initramfs -u
```
> 💡 **อธิบาย:** TPM เก็บ key ไว้ในชิปบนเมนบอร์ด เครื่องนี้บูตเองได้โดยไม่ต้องพิมพ์ passphrase · แต่ถ้า**ถอดดิสก์ไปเครื่องอื่น TPM ไม่มี → ปลดไม่ได้** (ซึ่งเป็นสิ่งที่เราต้องการ) · เหมาะกับเครื่องที่ต้องรีบูตเองบ่อย · **ควรเก็บ passphrase สำรองไว้เสมอ** เผื่อ TPM/เมนบอร์ดเสีย

> 💡 **คลาวด์ (AWS/GCP/Azure):** ข้ามหัวข้อ 2 ทั้งหมดได้ — เปิด การเข้ารหัสดิสก์ ของ provider ตอนสร้าง volume แทน (EBS encryption / CMEK) มัน unlock อัตโนมัติด้วย KMS ไม่ต้องยุ่งกับ dropbear/TPM

---

## 3. ตั้งค่าเริ่มต้นหลังบูต [Critical]

### 3.1 อัปเดตระบบ (แบบคุมเอง — ไม่เปิด auto-update)

```bash
sudo apt update && sudo apt full-upgrade -y     # อัปเดตครั้งแรกตอนติดตั้ง
```
> 💡 **อธิบาย — ทำไมไม่เปิด auto-update:** `unattended-upgrades` จะลง security update ให้เองกลางดึก ซึ่งบางครั้งอัป library/JVM/MySQL ที่กระทบแอปโดยไม่มีใครรู้ แล้วแอปพังตอนเช้า · เราเลือก **patch เองตามรอบ + เทสต์ staging ก่อน** เพื่อคุมว่าจะอัปอะไรเมื่อไหร่

```bash
# รอบ patch ประจำ (เช่น รายเดือน):
sudo apt update && apt list --upgradable        # ดูว่ามีอะไรให้อัป
sudo apt install --only-upgrade <package>        # อัปเฉพาะที่ตรวจแล้วใน staging
```
> 💡 อยากรู้ว่ามี security update ค้างไหมโดยไม่ลงให้อัตโนมัติ: `unattended-upgrades --dry-run -d` (แค่ดู ไม่ลง)

### 3.2 สร้าง role group ตามสิทธิ์ แล้วสร้าง user ไปใส่กลุ่ม

> 💡 **แนวคิด (RBAC):** นิยาม "สิทธิ์" ไว้ที่ **group** ไม่ใช่ที่ตัวคน — สิทธิ์จริง (sudo, อ่าน/เขียนไฟล์) ผูกกับ group ครั้งเดียว · เพิ่มคนเข้าทีม = สร้าง user แล้ว `usermod -aG <group>` · เอาคนออก = ถอดจาก group — ไม่ต้องแก้สิทธิ์รายคนเลย

**ขั้น 1 — สร้าง role group (นิยามสิทธิ์)**
```bash
sudo groupadd app-deploy      # สิทธิ์: วาง war + restart tomcat
sudo groupadd app-logview     # สิทธิ์: อ่าน log tomcat อย่างเดียว
# admin ใช้ group `sudo` ที่มีอยู่แล้ว (sudo เต็ม) · service account `tomcat` (รันแอป) สร้างในหัวข้อ 5
```

**ขั้น 2 — ผูกสิทธิ์เข้ากับ group**
```bash
# app-deploy: restart/status tomcat ผ่าน sudo เฉพาะคำสั่ง (visudo กัน syntax พัง)
sudo visudo -f /etc/sudoers.d/app-deploy
#   %app-deploy ALL=(root) NOPASSWD: /bin/systemctl restart tomcat, /bin/systemctl status tomcat

echo "umask 027" | sudo tee -a /etc/profile   # ไฟล์ใหม่ให้ group อ่านได้ คนนอกไม่เห็น
```
> 💡 สิทธิ์ "เขียน war" ของ `app-deploy` และ "อ่าน log" ของ `app-logview` เป็น **ACL บนโฟลเดอร์** ตั้งหลังติดตั้ง Tomcat — app-deploy → **หัวข้อ 7.1**, app-logview → **หัวข้อ 5.6** (ที่นี่แค่สร้าง group ไว้ก่อน)

**ขั้น 3 — ฟังก์ชันสร้าง user (ใช้ซ้ำทุกคน)** — เข้าด้วย SSH key ไม่มีรหัส
```bash
create_user() {                                  # ใช้: create_user <ชื่อ>  (ต้องมีไฟล์ <ชื่อ>.pub ที่ cwd)
  U=$1
  sudo adduser --disabled-password "$U"
  sudo -u "$U" mkdir -p /home/$U/.ssh
  sudo -u "$U" tee /home/$U/.ssh/authorized_keys < ${U}.pub
  sudo chmod 700 /home/$U/.ssh && sudo chmod 600 /home/$U/.ssh/authorized_keys
}
```

**ขั้น 4 — สร้าง user แล้วใส่กลุ่มตามสิทธิ์**
```bash
create_user somchai   && sudo usermod -aG sudo        somchai    # admin (sudo เต็ม)
create_user deployer  && sudo usermod -aG app-deploy  deployer   # deploy war + restart
create_user logviewer && sudo usermod -aG app-logview logviewer  # ดู log อย่างเดียว

# คน 1 คนถือหลายสิทธิ์ได้ = ใส่หลายกลุ่ม เช่น ทั้ง deploy และดู log:
#   sudo usermod -aG app-deploy,app-logview someone
```
> 💡 **สรุป:** `sudo` = admin เต็ม · `app-deploy` = วาง war + restart · `app-logview` = อ่าน log อย่างเดียว · ใครต้องสิทธิ์ไหนก็ใส่กลุ่มนั้น — เพิ่ม/ถอดคนภายหลังทำที่ group ไม่ต้องแตะสิทธิ์
> 💡 **ทำไม `visudo`:** มันตรวจ syntax ก่อนเซฟ ถ้าพิมพ์ผิดจะเตือน — ถ้าไฟล์ sudoers พัง `sudo` จะใช้ไม่ได้ทั้งเครื่อง กู้ยาก
> ⚠️ **service user สำหรับงานนอก Tomcat:** ถ้ามี background process อื่นที่ไม่ใช่ WAR ให้สร้าง service user แยก (nologin) ตามหัวข้อ 8 — สำหรับ stack นี้ `tomcat` (หัวข้อ 5) เป็น service account ที่รันแอปอยู่แล้ว

### 3.3 SSH hardening

แก้ `/etc/ssh/sshd_config`:
```
# ห้าม login เป็น root ตรงๆ
PermitRootLogin no
# ปิดรหัสผ่าน เหลือ key อย่างเดียว
PasswordAuthentication no
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 3
# อนุญาตเฉพาะ user ที่ระบุ (ใส่ให้ครบทุกคนที่ต้องเข้า)
AllowUsers somchai deployer logviewer
```
> ⚠️ sshd_config ก็ **ไม่รองรับคอมเมนต์ท้ายบรรทัด** — ถ้าต่อ `# ...` ท้าย `AllowUsers` มันจะถูกนับเป็นชื่อ user เพิ่ม · คอมเมนต์ต้องขึ้นบรรทัดใหม่
```bash
# เปิด terminal ใหม่ ทดสอบ ssh ด้วย key ให้เข้าได้ก่อน แล้วค่อย restart (กันล็อกตัวเอง)
sudo systemctl restart ssh
```
> ⚠️ **ระวังล็อกตัวเองออก:** ถ้า `AllowUsers` ไม่มีชื่อ user ที่คุณใช้อยู่ หรือยังไม่ได้ใส่ key ให้เขา พอ restart ปุ๊บจะ SSH เข้าไม่ได้อีกเลย — **ต้องเปิด session ที่ login ได้ค้างไว้ 1 อัน** ทดสอบจนชัวร์ก่อน

### 3.4 Firewall UFW

```bash
sudo ufw default deny incoming       # ปิดขาเข้าทั้งหมดเป็น default
sudo ufw default allow outgoing      # ขาออกเปิด (ให้ apt/certbot ทำงาน)
sudo ufw allow 22/tcp                # SSH — จำกัดเป็น IP ออฟฟิศได้: ufw allow from <ip> to any port 22
sudo ufw allow 80,443/tcp            # เว็บ ผ่าน Nginx
sudo ufw enable
```
> 💡 **อธิบาย:** หลัก least-exposure — เปิดเฉพาะพอร์ตที่ต้องรับจากภายนอก (22/80/443) ที่เหลือปิดหมด · **MySQL (3306) และ Tomcat (8080/8009) ไม่เปิด** เพราะให้คุยกันภายในเครื่องผ่าน 127.0.0.1 เท่านั้น ต่อให้ลืม bind มันก็ยังโดน firewall กันอีกชั้น

### 3.5 fail2ban + sysctl [Hardening]

```bash
sudo apt install -y fail2ban      # จับ IP ที่ลอง login SSH ผิดซ้ำๆ แล้วแบนชั่วคราว
```
`/etc/sysctl.d/99-hardening.conf` (ปรับพารามิเตอร์ kernel/network ให้ปลอดภัยขึ้น):
```
# กัน IP spoofing
net.ipv4.conf.all.rp_filter=1
# ไม่ตอบ ping broadcast (กัน smurf)
net.ipv4.icmp_echo_ignore_broadcasts=1
# ไม่รับ ICMP redirect (กัน MITM)
net.ipv4.conf.all.accept_redirects=0
# กัน SYN flood
net.ipv4.tcp_syncookies=1
# ASLR เต็มรูปแบบ (กัน memory exploit)
kernel.randomize_va_space=2
```
```bash
sudo sysctl --system      # โหลดค่าใหม่ทันที
```

### 3.6 Audit — ตรวจย้อนหลังว่าใครเข้ามาทำอะไร [High]

แยกเป็น 3 ชั้น: ใครเข้า-ออก (login), ใครใช้ sudo ทำอะไร, และคำสั่ง/ไฟล์ที่ถูกแตะ

**1) ประวัติการ login (มีในตัว ไม่ต้องลงเพิ่ม)**
```bash
last                               # ใครล็อกอินเข้า-ออกเมื่อไหร่ จาก IP ไหน
lastlog                            # ครั้งล่าสุดของแต่ละ user
sudo grep sshd /var/log/auth.log   # รายละเอียด SSH (สำเร็จ/ล้มเหลว + key fingerprint)
```

**2) การใช้ sudo — ถูกบันทึกอัตโนมัติ**
```bash
sudo grep sudo /var/log/auth.log   # ทุกคำสั่งผ่าน sudo + ใครรัน (เช่น deployer restart tomcat ตอนไหน)
```

**3) auditd — บันทึกคำสั่งและการแตะไฟล์สำคัญ**
```bash
sudo apt install -y auditd audispd-plugins
```
เพิ่ม rule ใน `/etc/audit/rules.d/hardening.rules`:
```
# บันทึกทุกคำสั่งที่ถูก exec พร้อม user
-a always,exit -F arch=b64 -S execve -k exec

# เฝ้าดูการ deploy / แก้ไฟล์ Tomcat
-w /opt/tomcat/webapps/ -p wa -k tomcat_deploy
-w /opt/tomcat/conf/ -p wa -k tomcat_conf

# เฝ้าดูการเปลี่ยน user/สิทธิ์
-w /etc/passwd -p wa -k identity
-w /etc/sudoers.d/ -p wa -k sudoers
```
```bash
sudo augenrules --load && sudo systemctl restart auditd
```
ค้นย้อนหลัง:
```bash
sudo ausearch -ua deployer -i          # ทุก event ของ user deployer (-i = อ่านง่าย)
sudo ausearch -k tomcat_deploy -i      # ไฟล์ war ถูกวาง/แก้เมื่อไหร่ โดยใคร
sudo aureport -u --summary             # สรุปกิจกรรมแยกตาม user
```

**retention ของ audit log — หมุนรายวัน เก็บ 90 วัน**

auditd ไม่มี "หมุนตามวัน" ในตัว แต่มันหมุนไฟล์เมื่อได้สัญญาณ `SIGUSR1` — เราสั่งให้หมุนวันละครั้งด้วย systemd timer แล้วตั้ง `num_logs=90` = เก็บ 90 ไฟล์ ≈ 90 วัน (ไฟล์ละวัน ไล่ง่าย)

`/etc/audit/auditd.conf`:
```
# เก็บ 90 ไฟล์ (= 90 วัน เมื่อหมุนวันละครั้ง)
num_logs = 90
# MB ต่อไฟล์ (safety cap กันวันที่ event พุ่งผิดปกติ)
max_log_file = 200
# ถ้าไฟล์วันเดียวโตเกิน cap ก็หมุนก่อน
max_log_file_action = ROTATE
# เหลือ disk < 1000MB → เตือน
space_left = 1000
space_left_action = email
# disk จะเต็มจน audit เขียนไม่ได้ → เข้า single-user (compliance เข้มใช้ halt)
admin_space_left_action = single
```
timer หมุนรายวัน — `/etc/systemd/system/audit-rotate.service` + `.timer`:
```ini
# audit-rotate.service — ยิงสัญญาณให้ auditd หมุน log วันละครั้ง
[Service]
# รันครั้งเดียวแล้วจบ ไม่ค้างเป็น daemon
Type=oneshot
# SIGUSR1 = สั่ง auditd หมุน log
ExecStart=/bin/systemctl kill -s SIGUSR1 auditd
```
```ini
# audit-rotate.timer — ตั้งเวลาให้ service ข้างบนทำงาน
[Timer]
# หมุนต้นวันของทุกวัน (00:05)
OnCalendar=*-*-* 00:05:00
# ถ้าเครื่องปิดช่วงนั้น ให้รันย้อนตอนเปิด
Persistent=true

[Install]
WantedBy=timers.target
```
```bash
sudo systemctl daemon-reload
sudo systemctl restart auditd
sudo systemctl enable --now audit-rotate.timer
```
> 💡 **อธิบาย:** systemd timer ยิง SIGUSR1 วันละครั้งให้ auditd หมุน → ได้ `audit.log.1` … `audit.log.90` (ย้อน 90 วัน ไฟล์ละวัน) · `max_log_file` เป็นแค่ตาข่ายกันวันที่ event พุ่งผิดปกติ · ถ้าต้องเก็บยาวกว่า 90 วันตามนโยบาย → ส่งออก central (ภาคผนวก C)

> 💡 **อธิบาย:** `ausearch -k <key>` ค้นตาม tag ที่ตั้งใน rule — `-k tomcat_deploy` ตอบได้ว่า "war ถูกวางเมื่อไหร่ โดย user ไหน" ตรงกับที่ต้องการ audit การ deploy · `ausearch -ua <user>` = ดูทุกอย่างที่ user คนนั้นทำ
> 💡 สำหรับ admin ที่อยากเก็บ **ทุก keystroke คำสั่ง**: เพิ่ม `session required pam_tty_audit.so enable=*` ใน `/etc/pam.d/sshd`
> ⚠️ **กันคนเจาะลบร่องรอย:** ควร**ส่ง log ออกไปเก็บนอกเครื่อง** (central syslog/log server) ด้วย — ถ้าเก็บในเครื่องอย่างเดียว คนที่ได้ root อาจลบ log ทิ้งได้

### 3.7 ตั้ง timezone + เวลาตรงกัน (NTP) [High]

```bash
# 1) ตั้ง timezone
timedatectl list-timezones | grep Bangkok     # หาชื่อ timezone ที่ถูกต้อง
sudo timedatectl set-timezone Asia/Bangkok     # หรือ UTC (ดูหมายเหตุ)

# 2) เปิด NTP ให้เวลา sync อัตโนมัติ
sudo timedatectl set-ntp true                  # เปิด systemd-timesyncd

# 3) ตรวจผล
timedatectl                                    # ต้องเห็น:
#   Time zone: Asia/Bangkok (+07, +0700)
#   System clock synchronized: yes
#   NTP service: active
```
> 💡 **เลือก timezone เป็นมาตรฐานเดียวทั้ง fleet:** หลายองค์กรตั้ง server เป็น **UTC** เพื่อตัดปัญหา DST/เขตเวลาสับสนตอน correlate log ข้าม region · ถ้าทีมดู log เป็นเวลาไทยสะดวกกว่าใช้ `Asia/Bangkok` ได้ แต่ **ต้องเหมือนกันทุกเครื่อง** · เปลี่ยน timezone มีผลกับ timestamp ของ log ที่เขียน**หลังจากนั้น** (ของเก่าไม่เปลี่ยน)
> 💡 **JVM/Tomcat** ใช้ timezone ของ OS อยู่แล้ว · ถ้าอยากบังคับชัดเจน ใส่ `-Duser.timezone=Asia/Bangkok` ใน `setenv.sh` (5.7)
> 💡 **อธิบาย — ทำไมสำคัญกับ log:** log ทุกไฟล์พึ่ง timestamp · ถ้าเวลาเครื่องเพี้ยน จะ **correlate เหตุการณ์ข้ามระบบ/ข้ามเครื่องไม่ได้** และ log ใช้เป็นหลักฐานไม่ได้ · มาตรฐาน (เช่น PCI-DSS req. 10.6) **บังคับ** ให้เวลาทุกเครื่อง sync กับแหล่งเวลาเดียวกัน · ถ้าต้องชี้ NTP ไปที่ server ภายในองค์กร แก้ `NTP=` ใน `/etc/systemd/timesyncd.conf`

---

## 4. ติดตั้ง & ตั้งค่า MySQL [Critical]

```bash
sudo apt install -y mysql-server
sudo systemctl enable --now mysql
sudo mysql_secure_installation      # ลบ anonymous user, test db, ปิด remote root
```
> 💡 **อธิบาย — `mysql_secure_installation` ทำอะไร:** เป็น wizard ที่ลบของ default ที่เสี่ยง (บัญชี anonymous, database `test`, การ login root จากระยะไกล) · ตอบ Yes ให้หมดได้ ยกเว้น "Validate Password Component" ที่จะบังคับความซับซ้อนรหัส (เลือกตามนโยบายทีม)

bind localhost — `/etc/mysql/mysql.conf.d/mysqld.cnf`:
```ini
[mysqld]
bind-address = 127.0.0.1       # รับ connection เฉพาะในเครื่อง — ภายนอกต่อไม่ได้
local_infile = 0               # ปิด LOAD DATA LOCAL (กันอ่านไฟล์ฝั่ง client ผ่าน SQL)
skip_symbolic_links = 1        # กันใช้ symlink ชี้ข้าม directory
```
```bash
sudo systemctl restart mysql
```

สร้าง database + user จำกัดสิทธิ์:
```bash
sudo mysql        # เข้า MySQL shell ในนาม root (ผ่าน socket, ไม่ต้องใช้รหัส)
```
```sql
CREATE DATABASE appdb CHARACTER SET utf8mb4;
CREATE USER 'app'@'127.0.0.1' IDENTIFIED BY '<รหัสยาวสุ่ม>';
GRANT SELECT,INSERT,UPDATE,DELETE ON appdb.* TO 'app'@'127.0.0.1';   -- ให้เฉพาะที่แอปใช้
-- ห้าม GRANT ALL / *.* / 'app'@'%'  (จะกลายเป็น user เทพที่ต่อจากไหนก็ได้)
FLUSH PRIVILEGES;
```
> 💡 **อธิบาย — least privilege ของ DB:** แอปควรใช้ user ที่ทำได้แค่ CRUD บน `appdb` เท่านั้น · ถ้าแอปโดน SQL injection ผู้โจมตีก็ทำได้แค่ในขอบเขตนี้ ไม่สามารถ DROP ตาราง, อ่าน db อื่น, หรือสร้าง user ใหม่
> ⚠️ **gotcha ที่เจอบ่อย — caching_sha2_password:** MySQL 8 ใช้ auth แบบ `caching_sha2_password` เป็น default ซึ่ง **JDBC connector เก่า (Connector/J < 8.0) ต่อไม่ติด** ขึ้น error auth — แก้โดย**ใช้ Connector/J 8.0+ ในแอป** (วิธีที่ถูก) หรือถ้าจำเป็นจริงค่อยเปลี่ยน auth ของ user: `ALTER USER 'app'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '<รหัส>';`
> 💡 ไม่ทำ encryption ที่ MySQL — ข้อมูลบนดิสก์ถูก LUKS ครอบไว้แล้ว · รหัส MySQL ถูก hash อัตโนมัติ

---

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

## 6. ติดตั้ง & ตั้งค่า Nginx + TLS [Critical]

> 💡 **อธิบาย — โครงสร้าง Nginx:** คอนฟิกมี 3 ชั้นซ้อนกัน — **`http {}`** (ค่ากลางทั้ง server), **`server {}`** (1 เว็บไซต์/โดเมน), **`location {}`** (เส้นทาง URL ในไซต์) · directive แต่ละตัว**ต้องวางให้ถูกชั้น** ไม่งั้น `nginx -t` ไม่ผ่าน

### 6.1 ติดตั้ง + ตั้ง server_name ก่อน

```bash
sudo apt install -y nginx
sudo systemctl enable --now nginx
```
แก้ไซต์ default `/etc/nginx/sites-available/default` ใส่ `server_name` ให้ตรง domain (certbot ต้องใช้หาตำแหน่ง):
```nginx
server {
    listen 80;
    server_name yourdomain.com;        # ← แก้เป็น domain จริง
    location / {
        proxy_pass http://127.0.0.1:8080;        # ส่งต่อไป Tomcat
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```
```bash
sudo nginx -t && sudo systemctl reload nginx
```
> ⚠️ **ก่อนขอ cert ต้องครบ:** (1) DNS A record ของ `yourdomain.com` ชี้มาที่ IP เครื่องแล้ว (2) UFW เปิด 80/443 แล้ว (หัวข้อ 3.4) (3) `server_name` ตรง — ไม่งั้น certbot ขอ cert ไม่ผ่าน

### 6.2 ขอใบรับรอง TLS (Let's Encrypt)

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d yourdomain.com     # certbot แก้ server block เติม listen 443 + cert + redirect ให้อัตโนมัติ
```
> 💡 certbot จะเติม `listen 443 ssl`, path ของ cert, และ redirect 80→443 ลงใน server block ให้เอง พร้อมตั้ง cron ต่ออายุอัตโนมัติ (cert อายุ 90 วัน)

### 6.3 เพิ่มค่าความปลอดภัย

ใส่ **ใน `http {}`** ของ `/etc/nginx/nginx.conf` (มีผลทุกไซต์):
```nginx
server_tokens off;                     # ซ่อนเวอร์ชัน Nginx ใน header/หน้า error
client_max_body_size 10m;              # จำกัดขนาด request (กัน upload ถล่ม)
client_body_timeout 10s;
client_header_timeout 10s;

# security headers (มีผลหลังเปิด HTTPS จาก 6.2)
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;  # บังคับ HTTPS
add_header X-Content-Type-Options "nosniff" always;                                  # กัน MIME sniffing
add_header X-Frame-Options "SAMEORIGIN" always;                                      # กัน clickjacking
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
```
ส่วน `ssl_protocols` / `ssl_ciphers` certbot ตั้งให้แล้วใน `options-ssl-nginx.conf` — ไม่ต้องตั้งซ้ำ
```bash
sudo nginx -t && sudo systemctl reload nginx
```
> 💡 **อธิบาย — ทำไมมี Nginx หน้า Tomcat:** Nginx รับ HTTPS จากภายนอกแล้ว proxy เป็น HTTP ไป Tomcat ที่ localhost — Tomcat ไม่ต้องโดนเน็ตตรงๆ, จัดการ cert/TLS ที่เดียว, และกรอง request ชั้นหน้าได้ (rate limit, body size)

### 6.4 Log & retention (Nginx) [High]

Nginx เป็น **แหล่งหลักที่บันทึกว่าใครเข้าเว็บ** เพราะอยู่หน้าสุดและเห็น **IP จริงของผู้ใช้** · มี 2 ไฟล์:

| ไฟล์ | บันทึกอะไร |
|---|---|
| `/var/log/nginx/access.log` | ทุก request: IP จริง, เวลา, `"METHOD /path"`, status, bytes, referer, user-agent |
| `/var/log/nginx/error.log` | error ของ Nginx เอง (config ผิด, upstream ล่ม, TLS ปัญหา) |

**format log (เก็บครบ ให้สอดคล้องกับ Tomcat 5.9):** default `combined` เก็บเกือบครบอยู่แล้ว แต่ไม่มี response time — นิยาม format เองใน `http {}` ของ `/etc/nginx/nginx.conf`:
```nginx
log_format rich '$remote_addr - $remote_user [$time_local] '
                '"$request" $status $body_bytes_sent $request_time '
                '"$http_referer" "$http_user_agent"';
access_log /var/log/nginx/access.log rich;
```
```
203.0.113.5 - - [17/Oct/2026:19:40:12 +0700] "POST /app/orders/create HTTP/1.1" 200 512 0.048 "https://site/app/orders" "Mozilla/5.0 ..."
```
**แต่ละ field:** `$remote_addr` IP จริง · `$remote_user` user จาก HTTP auth (session login = `-`) · `"$request"` **method + หน้า/endpoint** · `$status` · `$body_bytes_sent` · `$request_time` **เวลาตอบ (วินาที)** · `"$http_referer"` **มาจากหน้าไหน** · `"$http_user_agent"` browser · `sudo nginx -t && sudo systemctl reload nginx` ให้มีผล

**retention:** Ubuntu ติดตั้ง logrotate ให้ Nginx อยู่แล้วที่ `/etc/logrotate.d/nginx` (default `rotate 14` = เก็บ 14 วัน) — ปรับให้ตรง policy:
```bash
sudo sed -i 's/rotate 14/rotate 90/' /etc/logrotate.d/nginx   # เก็บ 90 วันให้ตรงกับ log อื่น
sudo logrotate -d /etc/logrotate.d/nginx                      # dry-run ตรวจ
```
```bash
# ดูสดว่าใครกำลังเข้ามา:
sudo tail -f /var/log/nginx/access.log
# สรุป top IP ที่เข้ามามากสุด:
sudo awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head
```
> 💡 **สรุปเลเยอร์ของ log "ใครเข้ามา":**
> - **SSH/เข้าเครื่อง** (sysadmin) → `last`, `/var/log/auth.log`, auditd (หัวข้อ 3.6)
> - **เข้าเว็บจากภายนอก** (ผู้ใช้ทั่วไป) → **Nginx access.log** (IP จริง + URL) — แหล่งหลัก
> - **ระดับแอป** (session, response time) → Tomcat access log (หัวข้อ 5.9)
> - **username ที่ login ในแอป** → ต้องให้แอปเขียน log เอง
> ⚠️ ตั้ง retention ของ access.log ให้ **ยาวพอกับ audit** (เช่น 90 วัน+) เพราะเวลาสืบสวนเหตุ มักต้องย้อนดู request log ประกอบ

---

## 7. Deploy แอป (WAR บน Tomcat)

แอปเป็น **WAR รันในตัว Tomcat** → **Tomcat (user `tomcat`) คือ service user ที่รันแอป** ไม่ต้องมี systemd service แยกและไม่ต้อง login เป็น `tomcat`
ปิด manager/tomcat-users แล้ว จึง deploy แบบ **file-drop (autoDeploy)**: วางไฟล์ war ลง webapps แล้ว Tomcat กางเอง

### 7.1 ให้สิทธิ์ group `app-deploy` วาง war ได้ (ทำครั้งเดียว ด้วย ACL)

```bash
sudo chown tomcat:tomcat /opt/tomcat/webapps
sudo chmod 750 /opt/tomcat/webapps
# ACL: ให้ service tomcat อ่าน war ได้เสมอ + group app-deploy เขียน/ทับ war ได้
sudo setfacl -R  -m g:tomcat:rX -m g:app-deploy:rwX /opt/tomcat/webapps
sudo setfacl -R -d -m g:tomcat:rX -m g:app-deploy:rwX /opt/tomcat/webapps   # war ใหม่สืบทอดสิทธิ์
```
> 💡 **อธิบาย — ทำไมใช้ ACL ไม่ใช่ group tomcat:** process Tomcat (user `tomcat`) ต้องอ่าน war ได้, คน deploy ต้องเขียนได้ · default ACL ทำให้ war ที่ `app-deploy` วางใหม่ **ให้ `tomcat` อ่านได้อัตโนมัติ และ `app-deploy` เขียนทับได้** — คน deploy อยู่แค่ group `app-deploy` พอ **ไม่ต้องเป็นสมาชิก group `tomcat`** (แยก role ออกจาก service account สะอาดกว่า)

### 7.2 Deploy WAR

ทำในนาม deploy user (ไม่ใช้ root):
```bash
# ชื่อไฟล์ = context path:  app.war → https://domain/app   |   ROOT.war → https://domain/
cp app.war /opt/tomcat/webapps/
```
Tomcat autoDeploy จะกาง war เองในไม่กี่วินาที **ไม่ต้อง restart** — ดู log ยืนยัน:
```bash
tail -f /opt/tomcat/logs/catalina.out      # เห็น "Deployment of web application archive ... has finished"
```
> 💡 **autoDeploy** คือค่า default ของ Tomcat 9 ที่เฝ้าดูโฟลเดอร์ webapps เจอ war ใหม่/เปลี่ยนก็กางให้เอง · **อัปเดตเวอร์ชัน:** วางทับไฟล์ war ชื่อเดิม Tomcat จะ undeploy ตัวเก่าแล้ว deploy ตัวใหม่ให้

### 7.3 Restart Tomcat (เฉพาะเมื่อจำเป็น)

เช่น แก้ server.xml / JVM opts ต้อง restart:
```bash
sudo systemctl restart tomcat      # ใช้ user ใน group app-deploy ผ่าน sudo เฉพาะคำสั่ง
```
sudoers (`/etc/sudoers.d/app-deploy`) ตั้งไว้แล้วในหัวข้อ 3:
```
%app-deploy ALL=(root) NOPASSWD: /bin/systemctl restart tomcat, /bin/systemctl status tomcat
```
> 💡 **สรุปใครทำอะไร:** `tomcat` = เจ้าของ process (nologin) · group `app-deploy` = วาง war (ACL) + restart (sudo) · group `app-logview` = อ่าน log · group `sudo` = admin เต็ม
> 💡 **Backup:** ถ้าส่ง backup ออกนอกเครื่อง (S3 / เครื่องสำรอง) **เข้ารหัสไฟล์ backup แยก** (เช่น `gpg`) เพราะ LUKS ครอบแค่ดิสก์ในเครื่อง ไม่ครอบไฟล์ที่ออกไปข้างนอก

---

## 8. Service / งานเบื้องหลังอื่นๆ (ถ้ามี)

ใช้รูปแบบเดียวกันซ้ำได้ทุก service — หลักการ 4 ข้อ:

1. **1 service = 1 user เฉพาะ (nologin) ไม่แชร์กัน** — service ไหนโดนเจาะก็ไม่ลามถึงตัวอื่น
2. **รันผ่าน systemd ที่ harden** ไม่รันด้วย root และไม่ปล่อยค้างใน screen/tmux
3. **network service → bind `127.0.0.1`** และ UFW ปิดพอร์ตไว้ (ให้คุยผ่าน Nginx/localhost เท่านั้น)
4. **งานตามเวลา → ใช้ systemd timer** (ดีกว่า cron: log รวมใน journald, คุม user/สิทธิ์ได้)

**สร้าง user + วางไฟล์**
```bash
sudo useradd --system --create-home --home-dir /opt/worker \
     --shell /usr/sbin/nologin worker
sudo chown -R worker:worker /opt/worker
```

**systemd unit (template ที่ harden)** — `/etc/systemd/system/worker.service`
```ini
[Unit]
Description=Background worker
# รอ network พร้อมก่อนสตาร์ท
After=network.target

[Service]
# รันด้วย user เฉพาะ (nologin) ไม่ใช่ root
User=worker
Group=worker
WorkingDirectory=/opt/worker
ExecStart=/opt/worker/run.sh
# ตายผิดปกติ → สตาร์ทใหม่
Restart=on-failure

# --- hardening ---
# ห้าม process ยกระดับสิทธิ์ตัวเอง
NoNewPrivileges=true
# ทั้งระบบเป็น read-only สำหรับ process นี้
ProtectSystem=strict
# มองไม่เห็น /home
ProtectHome=true
# /tmp แยกของตัวเอง (process อื่นไม่เห็น)
PrivateTmp=true
# เขียนได้เฉพาะโฟลเดอร์นี้ (ข้อยกเว้นของ ProtectSystem)
ReadWritePaths=/opt/worker/data
# ตัด capability พิเศษทั้งหมด (เปิด port<1024, แก้เวลาระบบ ฯลฯ) — ใส่เท่าที่ต้องถ้าจำเป็น
CapabilityBoundingSet=

[Install]
WantedBy=multi-user.target
```
```bash
sudo systemctl daemon-reload && sudo systemctl enable --now worker
```
> 💡 **อธิบาย — directive hardening:** `ProtectSystem=strict` + `ReadWritePaths` = process เขียนได้แค่โฟลเดอร์ที่อนุญาต ต่อให้โดนเจาะก็แก้ไฟล์ระบบไม่ได้ · `PrivateTmp` = กันไฟล์ชั่วคราวรั่วถึงกัน · `CapabilityBoundingSet=` ว่าง = ตัดสิทธิ์พิเศษ (เช่น เปิด port < 1024, แก้เวลาระบบ) ทั้งหมด

**งานตามเวลา (แทน cron)** — `.service` (Type=oneshot) + `.timer`
```ini
# /etc/systemd/system/cleanup.service — งานที่ timer เรียก
[Service]
# รันครั้งเดียวแล้วจบ
Type=oneshot
# รันด้วย service user เดียวกัน
User=worker
ExecStart=/opt/worker/cleanup.sh
```
```ini
# /etc/systemd/system/cleanup.timer — ตารางเวลา
[Timer]
# ทุกวันเวลา 02:00
OnCalendar=*-*-* 02:00:00
# ถ้าเครื่องปิดช่วงนั้น ให้รันย้อนตอนเปิด
Persistent=true

[Install]
WantedBy=timers.target
```
```bash
sudo systemctl enable --now cleanup.timer
systemctl list-timers          # ดูตารางงานทั้งหมด + รอบถัดไป
```

**Restart / ดู log** — ให้สิทธิ์ผ่าน group `app-deploy` เฉพาะคำสั่ง (เพิ่มในบรรทัด sudoers เดิม)
```
%app-deploy ALL=(root) NOPASSWD: /bin/systemctl restart worker, /bin/systemctl status worker
```
```bash
sudo systemctl restart worker
```

**Logs ของ service — ไปอยู่ใน journald อัตโนมัติ**

service ที่รันผ่าน systemd **ไม่ต้องตั้ง log เอง** — ทุกอย่างที่ ExecStart พิมพ์ออก stdout/stderr ถูก journald เก็บให้ · retention = `journald.conf` (รายวัน 90 วัน ที่ตั้งในภาคผนวก B) ครอบให้แล้ว
```bash
journalctl -u worker -f                              # ดู log สด
journalctl -u worker --since today                   # เฉพาะวันนี้
journalctl -u worker --since "2026-10-17" --until "2026-10-18"   # ย้อนรายวัน
journalctl -u worker -p err                          # เฉพาะ level error
```
> 💡 **ทำไมไม่เห็นไฟล์ log:** service พวกนี้ไม่ได้เขียนไฟล์ใน `/var/log/` แบบ Nginx/Tomcat — มัน log เข้า **journald** (binary) ซึ่งดูด้วย `journalctl -u <ชื่อ>` · ครบทั้ง retention + ค้นตามวัน/level ได้เลย
> 💡 **ถ้า service เขียน log เป็นไฟล์เอง** (เช่น `/opt/worker/logs/app.log`) → เพิ่ม logrotate เหมือน 5.8 ให้หมุนรายวัน เก็บ 90:
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

> 💡 ถ้า service ต้องต่อ MySQL → สร้าง DB user แยกอีกตัว ให้สิทธิ์เฉพาะ db/ตารางที่ใช้ (เหมือนหัวข้อ 4) ไม่ใช้ user เดียวกับแอปหลัก

---

## 9. แก้ไฟล์ใน WAR & แชร์ไฟล์ข้าม service

### 9.1 แก้ไฟล์ใน WAR ที่กางแล้ว

WAR ที่กางอยู่ `/opt/tomcat/webapps/app/` เป็นของ `tomcat:tomcat`

- **แนะนำ: อย่าแก้ในไดเรกทอรีที่กางโดยตรง** — Tomcat อาจ re-explode ทับ หรือ redeploy แล้วการแก้หาย → แก้ที่ **source → build war ใหม่ → วางทับ** (war คือ source of truth)
- ถ้าจำเป็นต้องแก้ด่วน (เช่น แก้ config.properties) ให้ทำ **ในนาม user `tomcat`** เพื่อให้เจ้าของไฟล์ไม่เพี้ยน:
```bash
sudo -u tomcat vi /opt/tomcat/webapps/app/WEB-INF/classes/config.properties
# ถ้าเผลอแก้ด้วย deploy user แล้ว ให้คืนเจ้าของ:
sudo chown tomcat:tomcat <ไฟล์>
```
> ⚠️ ห้าม `chmod 777` เพื่อให้แก้ง่าย — มันเปิดให้ทุก user แก้ไฟล์แอปได้ · ใช้ `sudo -u tomcat` คือทางที่สะอาดและปลอดภัยสุด

### 9.2 แชร์ไฟล์ข้าม service (เช่น Tomcat ↔ Hive/Hadoop บน local FS)

แต่ละ service รันคนละ user — ให้เข้าถึงกันได้โดย**ไม่เปิด 777** ด้วย **shared group + setgid + (ถ้าซับซ้อน) ACL**
```bash
# 1) group กลางสำหรับแชร์ข้อมูล
sudo groupadd datax

# 2) เพิ่ม service user ทั้งสองฝั่งเข้า group
sudo usermod -aG datax tomcat
sudo usermod -aG datax hive

# 3) โฟลเดอร์แชร์: group + setgid (ไฟล์ใหม่ได้ group datax อัตโนมัติ)
sudo chown tomcat:datax /data/exchange
sudo chmod 2770 /data/exchange        # 2750 ถ้าฝั่งปลายทางอ่านอย่างเดียว
```
ให้ service ฝั่งที่เขียนไฟล์ ตั้ง umask ใน systemd unit ให้ group อ่านได้:
```ini
[Service]
# ไฟล์ใหม่ = 640, โฟลเดอร์ = 750
UMask=0027
```
ถ้าต้องการสิทธิ์ละเอียด / เปลี่ยนเจ้าของไม่ได้ → ใช้ **POSIX ACL**:
```bash
sudo setfacl -R  -m g:datax:rX /data/exchange     # ให้สิทธิ์ตอนนี้
sudo setfacl -R -d -m g:datax:rX /data/exchange   # default: ไฟล์ใหม่สืบทอด
getfacl /data/exchange                            # ตรวจ
```
> 💡 **อธิบาย — `rX` (X ตัวใหญ่):** ให้สิทธิ์ execute **เฉพาะโฟลเดอร์** (ต้อง execute ถึงจะเข้าโฟลเดอร์ได้) แต่**ไม่ติด execute ให้ไฟล์ข้อมูลธรรมดา** — ปลอดภัยกว่า `rx` ตัวเล็กที่จะทำให้ไฟล์ทุกอันกลายเป็น executable

หลัก: **ฝั่งสร้างไฟล์เป็นเจ้าของ, ฝั่งที่ใช้แค่อ่านให้ `r`/`rX` พอ** อย่าให้เขียนถ้าไม่จำเป็น

> ⚠️ **ถ้าไฟล์อยู่บน HDFS (ไม่ใช่ดิสก์ local):** สิทธิ์ POSIX ข้างบนใช้ไม่ได้ ต้องใช้สิทธิ์ของ HDFS เอง (`hdfs dfs -chmod`, `hdfs dfs -setfacl`) + Kerberos/Ranger ถ้าเปิด security — แพทเทิร์น shared-group ใช้ได้เฉพาะเมื่อทั้งสอง service แชร์โฟลเดอร์บนเครื่อง/mount เดียวกัน (ถ้าต้องการหัวข้อ HDFS เต็ม บอกได้ว่าเป็น single node หรือ cluster และใช้ Kerberos ไหม)

---

## 10. ตรวจสอบหลังติดตั้ง

รันทีละข้อ ถ้าข้อไหนไม่ผ่านให้กลับไปแก้หัวข้อนั้นก่อนขึ้น production:

- [ ] `lsblk -f | grep crypto_LUKS` — ดิสก์เข้ารหัสจริง
- [ ] **ทดสอบรีบูต 1 รอบ** แล้ว unlock ระยะไกลได้ (ถ้าใช้ dropbear/TPM) — สำคัญสุด อย่าข้าม
- [ ] `sudo ufw status` — เปิดเฉพาะ 22/80/443; 3306 และ 8080/8009 ปิด
- [ ] `ssh root@host` ถูกปฏิเสธ และ password login ใช้ไม่ได้
- [ ] `ss -tulpn` — MySQL/Tomcat listen แค่ 127.0.0.1
- [ ] `sudo -u tomcat -s` — service user `tomcat` login ไม่ได้ (nologin)
- [ ] `getent group sudo app-deploy app-logview tomcat` — สมาชิกแต่ละ group ถูกต้อง
- [ ] `sudo -l -U deployer` — deployer มี sudo เฉพาะ restart/status tomcat เท่านั้น
- [ ] `sudo -l -U logviewer` — logviewer **ไม่มี sudo** / `sudo -u logviewer tail /opt/tomcat/logs/catalina.out` อ่านได้ แต่เขียน/ลบไม่ได้
- [ ] `last` / `sudo ausearch -k tomcat_deploy -i` — ดูย้อนหลังได้ว่าใคร login และใครวาง war
- [ ] ตั้ง retention **ทุก log = รายวัน เก็บ 90 วัน**: Tomcat `maxDays` + logrotate (`catalina.out`, `gc.log`, Nginx) + auditd timer (SIGUSR1 รายวัน, `num_logs=90`) + journald (`MaxFileSec=1day`, `MaxRetentionSec=90day`)
- [ ] `systemctl list-timers | grep audit-rotate` — timer หมุน audit รายวันทำงาน
- [ ] `tail /var/log/nginx/access.log` — เห็น **IP จริงของผู้ใช้** (ไม่ใช่ 127.0.0.1) และ Tomcat access log ก็เห็น IP จริง (RemoteIpValve ทำงาน)
- [ ] `curl -I https://yourdomain.com` — เห็น HSTS, nosniff, ไม่เห็น `Server: nginx/x.x.x`
- [ ] เข้า `/manager`, `/examples`, `/docs` ของ Tomcat จากภายนอกไม่ได้
- [ ] `mysql -h <public-ip>` จากเครื่องนอกต่อไม่ติด + แอปต่อ DB ได้ (เช็ก connector เข้ากับ caching_sha2)
- [ ] app เชื่อม DB ด้วย user จำกัดสิทธิ์ ไม่ใช่ root
- [ ] `/opt/tomcat/bin/version.sh` — ยืนยันเป็น Tomcat 9 เวอร์ชันที่ต้องการ
- [ ] `sudo -u tomcat jcmd $(pgrep -f catalina) VM.flags` — JVM รับค่า heap/GC ที่ตั้งจริง
- [ ] `systemctl show -p User <service>` — ทุก service เบื้องหลังรันด้วย user เฉพาะ ไม่ใช่ root
- [ ] `systemctl list-timers` — งานตามเวลา (ถ้ามี) ตั้งถูกต้อง
- [ ] `sudo certbot renew --dry-run` — ต่ออายุ TLS ได้
- [ ] `timedatectl` — เวลา sync (NTP active) เพื่อให้ timestamp ของ log แม่น

---

## ภาคผนวก A — มาตรฐานการเก็บ log

**default ในคู่มือ = 90 วัน** เทียบกับมาตรฐานที่พบบ่อย:

| มาตรฐาน | retention ขั้นต่ำ | 90 วันพอไหม |
|---|---|---|
| **พ.ร.บ.คอมพิวเตอร์ (ไทย) ม.26** | ≥ 90 วัน (ขยายได้ถึง 2 ปี) | ✅ ผ่าน |
| **PCI-DSS** (ถ้าแตะข้อมูลบัตร/การเงิน) | 1 ปี (online พร้อมใช้ 3 เดือน) | ⚠️ ต้อง archive เพิ่มให้ครบ 1 ปี |
| **ISO 27001** | กำหนดเองตาม risk/กฎหมาย | ต้องมีนโยบายเป็นลายลักษณ์อักษร |
| **PDPA (ไทย)** | ไม่ระบุตัวเลข | เก็บพอสืบสวน/ตามนโยบายองค์กร |

> ⚠️ **สำหรับระบบการเงิน (เช่น linebot-finance / cbi_platform):** น่าจะเข้าข่าย PCI-DSS → ตั้ง online 90 วันในเครื่อง **+ ship log ออก central/archive ให้ครบ 1 ปีขึ้นไป**

**มาตรฐานบังคับมากกว่าแค่ retention — เช็ก 5 ข้อนี้:**

1. ✅ **เวลาตรงกัน (NTP)** — timestamp แม่น (หัวข้อ 3.7) · PCI req. 10.6
2. ✅ **กันแก้ไข/ลบ (integrity)** — จำกัดสิทธิ์อ่าน (app-logview read-only, auditd) + **ส่งออก central log** กัน root ในเครื่องลบร่องรอย
3. ✅ **เก็บครบทุกเหตุการณ์สำคัญ** — login, การใช้สิทธิ์ (sudo), การเข้าถึงข้อมูล, การเปลี่ยน config, การ deploy → auditd (3.6) + access log (5.9, 6.4) ครอบแล้ว
4. ⬜ **review สม่ำเสมอ** — ต้องมีคน/เครื่องมือ (SIEM) ดู log เป็นรอบ ไม่ใช่เก็บไว้เฉยๆ
5. ✅ **central log server** — วิธี forward อยู่ใน **ภาคผนวก C** (ตัว server ปลายทาง เช่น Graylog/ELK/Loki เป็นงานแยก)

> ⚠️ **ยืนยันตัวเลข/ข้อกำหนดกับทีม compliance / legal ขององค์กรก่อนเสมอ** — มาตรฐานมีการปรับเวอร์ชัน และแต่ละองค์กร/อุตสาหกรรมมีข้อบังคับเพิ่มเติม คู่มือนี้ตั้ง baseline ที่ดี แต่ไม่แทนการรับรอง compliance

---

## ภาคผนวก B — รายละเอียด log แต่ละตัว

ทุก log ในระบบนี้: ทำหน้าที่อะไร เก็บอะไร และตั้ง retention ที่หัวข้อไหน

| Log | Path | หน้าที่ | เก็บรายละเอียดอะไร | retention ตั้งที่ |
|---|---|---|---|---|
| **Nginx access** | `/var/log/nginx/access.log` | ทุก request ที่เข้าเว็บจากภายนอก (แหล่งหลัก "ใครเข้า") | IP จริงของ client · เวลา · `"METHOD /path HTTP/x"` · status · bytes · referer · user-agent | 6.4 (logrotate) |
| **Nginx error** | `/var/log/nginx/error.log` | ปัญหาของ Nginx เอง | config ผิด · upstream (Tomcat) ล่ม · TLS/cert error · timeout | 6.4 (logrotate) |
| **Tomcat access** | `/opt/tomcat/logs/access.<date>.log` | request ระดับแอป (เสริมจาก Nginx) | IP จริง (ผ่าน RemoteIpValve) · เวลา · request · status · response time (ms) | 5.9 (`maxDays`) |
| **catalina.out** | `/opt/tomcat/logs/catalina.out` | stdout/stderr ของ Tomcat + แอป | log การ start/stop · exception/stack trace · `System.out` ของแอป | 5.8 (logrotate) |
| **catalina.\<date\>** | `/opt/tomcat/logs/catalina.<date>.log` | เหตุการณ์ของ Tomcat core (JULI) | start/stop component · deploy/undeploy · warning ของ container | 5.8 (`maxDays`) |
| **localhost.\<date\>** | `/opt/tomcat/logs/localhost.<date>.log` | error ระดับ web app ที่ไม่ถูก catch | exception ที่หลุดถึง container · lifecycle ของ app | 5.8 (`maxDays`) |
| **GC log** | `/opt/tomcat/logs/gc.log` | พฤติกรรม Garbage Collector ของ JVM | ทุกรอบ GC · pause time · heap ก่อน/หลัง · สาเหตุ GC | 5.8 (logrotate รายวัน) |
| **auth.log** | `/var/log/auth.log` | การ login / sudo / SSH (แหล่งหลัก "ใครเข้าเครื่อง") | SSH login สำเร็จ/ล้มเหลว + key fingerprint · ทุกคำสั่ง sudo + ใครรัน · su | logrotate (OS default) |
| **audit.log** | `/var/log/audit/audit.log` | auditd — หลักฐานระดับ kernel | `execve` (คำสั่งที่รัน) · การแตะไฟล์ที่ watch (webapps/conf/passwd/sudoers) · เปลี่ยน identity | 3.6 (รายวัน เก็บ 90) |
| **MySQL error** | `/var/log/mysql/error.log` | ปัญหาของ MySQL | start/stop · crash · ปัญหา connection/auth · คำเตือน | logrotate (mysql default) |
| **journald** | `journalctl` (binary) | log รวมของทุก systemd service | output ของ `tomcat`, `worker`, timer ฯลฯ · boot log | `journald.conf` (รายวัน 90, ดูด้านล่าง) |

> 💡 **journald — เก็บรายวัน 90 วัน** แก้ `/etc/systemd/journald.conf`:
> ```
> [Journal]
> # เก็บลง ดิสก์ ถาวร (/var/log/journal) ไม่ใช่แค่ RAM
> Storage=persistent
> # ใช้ ดิสก์ ได้สูงสุด 2GB
> SystemMaxUse=2G
> # ปิดไฟล์ journal ทุกวัน (1 ไฟล์ = 1 วัน ไล่ง่าย)
> MaxFileSec=1day
> # ลบ journal ที่เกิน 90 วัน
> MaxRetentionSec=90day
> ```
> แล้ว `sudo systemctl restart systemd-journald` · ดูขนาดปัจจุบัน: `journalctl --disk-usage` · ดู log ของวันใดวันหนึ่ง: `journalctl --since "2026-10-17" --until "2026-10-18"`

> 💡 **map กับ "ใครเข้ามา":** เข้าเครื่อง → `auth.log` + `audit.log` · เข้าเว็บ → Nginx `access.log` · ระดับแอป → Tomcat `access` · username ในแอป → แอปเขียนเอง

---

## ภาคผนวก C — ส่ง log ไป central server

เก็บ log ในเครื่องอย่างเดียวไม่พอสำหรับ compliance เพราะ (1) คนที่ได้ root ลบร่องรอยได้ (2) retention ยาว (เช่น 1 ปี) เปลืองดิสก์เครื่อง · วิธีมาตรฐานคือ **forward ออกไป central log server** (rsyslog / Graylog / ELK / Loki — ตัว server เป็นงานแยก)

**ระวังก่อน:** เปิด UFW ขาออกไปยัง log server เฉพาะพอร์ตที่ใช้ และ **ใช้ TLS** กันดักอ่านระหว่างทาง

### C.1 syslog + auth.log → rsyslog forward (ง่ายสุด, มีในตัว)

`/etc/rsyslog.d/90-forward.conf`:
```
# ส่งทุก log ของ syslog (รวม auth) ไป log server ผ่าน TCP/TLS
*.*  action(type="omfwd"
            target="logserver.internal" port="6514" protocol="tcp"
            StreamDriver="gtls" StreamDriverMode="1" StreamDriverAuthMode="x509/name"
            queue.type="linkedList" queue.filename="fwdq"   # คิวกันหายถ้า server ล่ม
            action.resumeRetryCount="-1")
```
```bash
sudo systemctl restart rsyslog
```

### C.2 ไฟล์ log ของ Nginx/Tomcat → ใช้ rsyslog imfile หรือ log shipper

ไฟล์พวกนี้ไม่ได้ผ่าน syslog ต้องมีตัว tail แล้วส่ง:
```
# /etc/rsyslog.d/91-appfiles.conf — ให้ rsyslog อ่านไฟล์แล้ว forward
module(load="imfile")
input(type="imfile" File="/var/log/nginx/access.log" Tag="nginx-access")
input(type="imfile" File="/opt/tomcat/logs/catalina.out" Tag="tomcat-out")
input(type="imfile" File="/opt/tomcat/logs/access.*.log" Tag="tomcat-access")
```
> 💡 ทางเลือกที่นิยมกว่าสำหรับไฟล์แอป: **log shipper** — Promtail (→ Loki), Filebeat (→ Elasticsearch), หรือ Fluent Bit · ติดตั้งเป็น service เบาๆ tail ไฟล์แล้วส่งปลายทาง ค้นหา/ทำ dashboard ได้สะดวกกว่า raw syslog

### C.3 audit.log → audisp-remote (ช่องทางเฉพาะของ auditd)

```bash
sudo apt install -y audispd-plugins
```
เปิด plugin ใน `/etc/audit/plugins.d/au-remote.conf` (`active = yes`) แล้วตั้งปลายทางใน `/etc/audit/audisp-remote.conf`:
```
remote_server = logserver.internal
port = 60
transport = tcp
# เปิด TLS/Kerberos ตามที่ log server รองรับ
enable_krb5 = no
```
```bash
sudo systemctl restart auditd
```
> 💡 **อธิบาย:** auditd มีช่องทาง forward ของตัวเอง (audisp) แยกจาก syslog เพื่อรักษา integrity ของ audit trail · ปลายทางต้องรัน `auditd` ในโหมดรับ (`au-remote`) หรือ SIEM ที่รองรับ

> ⚠️ **หลัง forward แล้ว ในเครื่องยังเก็บ retention สั้นได้** (เช่น 90 วัน) ส่วน retention ยาว (1 ปี+) ให้ไปอยู่ที่ central server — ตรงกับที่ ภาคผนวก A ต้องการ

---

## ภาคผนวก D — Runbook แก้ปัญหา (ไล่จากไหนไปไหน)

> 💡 **หลักการไล่ปัญหา:** request เดินทาง **Client → Nginx → Tomcat → แอป → MySQL** · ไล่ log **ตามเส้นทางนี้ทีละชั้น** ดูว่าปัญหาหยุดที่ชั้นไหน (ชั้นที่เริ่มเห็น error = ต้นเหตุอยู่แถวนั้น)

**เช็กสุขภาพรวมก่อนเสมอ:**
```bash
systemctl status nginx tomcat mysql     # service ไหน down
df -h ; free -h                         # disk/RAM เต็มไหม
ss -tulpn                               # พอร์ตที่ควร listen (443 nginx, 8080/3306 localhost)
```

### D.1 เว็บเข้าไม่ได้ / ขึ้น 502 หรือ 503

ไล่จากนอกเข้าใน:
1. `curl -I https://yourdomain.com` — ได้ status อะไร (ต่อไม่ติดเลย = network/firewall/nginx down)
2. `systemctl status nginx` — nginx รันไหม · `sudo nginx -t` — config ผิดไหม
3. `sudo tail /var/log/nginx/error.log` — **502/503 มักเขียนที่นี่** (เช่น `connect() failed ... upstream`) = nginx ต่อ Tomcat ไม่ได้
4. `systemctl status tomcat` — Tomcat รันไหม · `ss -tulpn | grep 8080` — listen อยู่ไหม
5. `tail /opt/tomcat/logs/catalina.out` — Tomcat start fail / crash ไหม

### D.2 ขึ้น error 500 (แอปพัง)

1. `grep ' 500 ' /var/log/nginx/access.log` — endpoint ไหนที่พัง
2. `tail -f /opt/tomcat/logs/catalina.out` + `localhost.<date>.log` — **stack trace อยู่ที่นี่** (ชื่อ exception + ไฟล์โค้ด)
3. ถ้า stack ชี้ไป DB → ไป D.5 · ถ้าชี้ config → เช็กไฟล์ config ของแอป

### D.3 เว็บช้า

1. `/var/log/nginx/access.log` ดู `$request_time` — ช้าที่ชั้นไหน (ค่าสูง = ช้าตั้งแต่ upstream)
2. Tomcat access log `%D` (ms) — endpoint ไหนช้า
3. `tail /opt/tomcat/logs/gc.log` — GC pause บ่อย/นานไหม (heap ตึง → ไป D.4)
4. `top` / `free -h` — CPU/RAM ตัน หรือ swap ไหม
5. ถ้า query ช้า → เปิด MySQL slow query log ดู

### D.4 Tomcat ตายแล้วเด้ง / OutOfMemory

1. `journalctl -u tomcat --since today` — เห็นรอบ restart ไหม
2. `grep -i outofmemory /opt/tomcat/logs/catalina.out` — ยืนยัน OOM
3. มี heap dump ใน `/opt/tomcat/logs/*.hprof` → เปิดด้วย Eclipse MAT หาว่า object อะไรกิน memory
4. `gc.log` — heap เต็มเร็ว/GC ถี่ → เพิ่ม `-Xmx` (ดู 5.7 ตารางขนาด) หรือหา memory leak ในแอป

### D.5 แอปต่อ DB ไม่ได้

1. log แอป / `catalina.out` — error อะไร (`Communications link failure` = ต่อไม่ติด · `Access denied` = user/รหัส · `Public Key Retrieval` / auth = caching_sha2 → ดู 4)
2. `systemctl status mysql` + `sudo tail /var/log/mysql/error.log`
3. `ss -tulpn | grep 3306` — MySQL listen `127.0.0.1` ไหม · `mysql -u app -p -h 127.0.0.1 appdb` — ลองต่อด้วย user แอป
4. ตรวจ grant: `SHOW GRANTS FOR 'app'@'127.0.0.1';`

### D.6 SSH เข้าไม่ได้

1. `ssh -v user@host` ฝั่ง client — ดูว่าค้างตรงไหน (auth fail / connection refused)
2. (ถ้ายังมี session อื่นเข้าได้) `sudo tail /var/log/auth.log` — เหตุผลที่ปฏิเสธ
3. เช็ก `AllowUsers` มีชื่อ user ไหม · key perms `~/.ssh` = 700, `authorized_keys` = 600
4. `sudo fail2ban-client status sshd` — IP โดนแบนไหม → `sudo fail2ban-client set sshd unbanip <ip>`

### D.7 Disk เต็ม

1. `df -h` — partition ไหนเต็ม
2. `sudo du -xh / | sort -rh | head` — โฟลเดอร์ไหนกิน
3. `du -sh /opt/tomcat/logs /var/log/* ; journalctl --disk-usage` — log โตผิดปกติไหม (retention ไม่ทำงาน?)
4. แก้เฉพาะหน้า: ลบ log เก่า/บีบอัด · แก้ระยะยาว: ตรวจ logrotate/maxDays (5.8) และ `logrotate -f` รันทันที

### D.8 HTTPS error / cert หมดอายุ

1. `curl -vI https://yourdomain.com` — ดู TLS error
2. `sudo certbot certificates` — วันหมดอายุ
3. `sudo certbot renew --dry-run` — ต่ออายุได้ไหม · `/var/log/letsencrypt/` ดูสาเหตุ (เช่น port 80 ถูกบล็อก/DNS เปลี่ยน)

### D.9 Deploy แล้วแอปไม่ขึ้น

1. `tail -f /opt/tomcat/logs/catalina.out` ตอนวาง war — เห็น `Deployment ... has finished` ไหม หรือ error
2. สิทธิ์ไฟล์: war ต้องให้ `tomcat` อ่านได้ (`ls -l /opt/tomcat/webapps/` — group `tomcat` + อ่านได้) ดู 7.1
3. ชื่อไฟล์ = context path ถูกไหม (`app.war` → `/app`) · autoDeploy เปิดอยู่ไหม

### D.10 รีบูตแล้วเครื่องค้าง (LUKS)

เครื่องค้างรอ passphrase ก่อนบูต → SSH เข้า initramfs แล้ว `cryptroot-unlock` (ดู 2.1) · ถ้า dropbear เข้าไม่ได้ = static IP ใน initramfs ไม่ถูก → ต้องต่อจอที่เครื่อง

> 💡 **เก็บ runbook นี้ไว้ที่เข้าถึงได้ตอนระบบล่ม** (central wiki / มือถือ) ไม่ใช่เฉพาะบนเครื่องที่อาจเข้าไม่ได้

---

## ภาคผนวก E — Preventive Maintenance (บำรุงรักษาตามรอบ)

> 💡 **แนวคิด:** ตรวจก่อนพัง · งานประจำที่ทำสม่ำเสมอกันไม่ให้ปัญหาเล็กลุกลาม (ดิสก์ เต็ม, cert หมด, patch ค้าง, backup เสีย)

### งาน Monitoring (ตั้ง alert ให้เตือนอัตโนมัติ — สำคัญสุด)

ตั้งให้ระบบ monitor (เช่น Prometheus/Zabbix/Netdata หรือ cron + alert) เตือนเมื่อ:

| เตือนเมื่อ | เกณฑ์ | ทำไม |
|---|---|---|
| Disk เต็ม | > 80% | กันระบบ/log เขียนไม่ได้ (ดู D.7) |
| Service down | nginx/tomcat/mysql ไม่ active | รู้ก่อนผู้ใช้แจ้ง |
| RAM/Swap | swap เริ่มถูกใช้มาก | heap/MySQL กินเกิน (ดู 5.7) |
| Cert ใกล้หมด | < 30 วัน | กัน HTTPS ล่ม (ปกติ certbot ต่อเอง แต่เฝ้าไว้) |
| 5xx rate พุ่ง | ผิดปกติจาก baseline | แอป/DB มีปัญหา |
| Failed login พุ่ง | SSH ล้มเหลวถี่ | โดนโจมตี (fail2ban ควรจัดการ) |
| Backup | งาน backup ล้มเหลว | กันค้นพบว่า backup เสียตอนต้องใช้ |

### รอบการตรวจ

| รอบ | งาน |
|---|---|
| **รายวัน** (อัตโนมัติ + สายตา) | เช็ก service health, ดิสก์/RAM, สแกน error log, ยืนยัน backup สำเร็จ |
| **รายสัปดาห์** | ไล่ดู log ผิดปกติ (auth fail, 5xx) · เช็ก log retention ทำงาน (`du -sh` ไม่โตผิด) · ดู fail2ban ban · ดูเทรนด์ ดิสก์ |
| **รายเดือน** | ลง security patch (staging→prod ตาม 3.1) · **ทดสอบ restore backup** (ไม่ใช่แค่สำรอง) · ทบทวน user/group ถอดคนที่ออก · เช็ก cert auto-renew · ไล่ดู audit log |
| **รายไตรมาส** | **ทดสอบรีบูต + LUKS unlock** · ทบทวน firewall rule · ทบทวน JVM heap/GC เทียบ load จริง · อัปเดต Tomcat/Java minor version · ซ้อม DR |
| **รายปี** | หมุน credential/SSH key · DR drill เต็มรูปแบบ · ทบทวนทั้ง config เทียบ baseline + มาตรฐาน compliance |

### จุดที่คนลืมบ่อย (ทำให้พังทั้งที่กันได้)

- ⚠️ **ไม่เคยทดสอบ restore** — backup มีแต่กู้ไม่ได้จริง · เดือนละครั้งลอง restore ขึ้นเครื่อง test
- ⚠️ **ไม่ทดสอบ LUKS unlock หลังแก้ network/initramfs** — รีบูตจริงแล้วเข้าไม่ได้
- ⚠️ **ปล่อย ดิสก์ โตเงียบๆ** — ตั้ง alert 80% ไว้ ไม่รอจนเต็ม
- ⚠️ **ไม่ถอด user คนที่ออกจากทีม** — ทบทวน `getent group` ทุกเดือน
- ⚠️ **patch ค้างนาน** — ช่องโหว่เก่าสะสม · มีรอบ patch ประจำ

> 💡 **ทำงานประจำพวกนี้ให้เป็นอัตโนมัติเท่าที่ได้** — systemd timer (เช็ก ดิสก์/health), monitoring tool (alert), และ documented checklist สำหรับงานที่ต้องใช้คน (restore test, DR drill)

---

**จุดที่พลาดไม่ได้:** เก็บ LUKS passphrase คนละที่กับเครื่อง · **ทดสอบ unlock ระยะไกลก่อนขึ้นจริง** · เปิด session ค้างไว้ตอนแก้ SSH/firewall · เข้ารหัส backup ที่ส่งออกนอกเครื่อง · เทสต์ใน staging ก่อนทุกครั้ง

_รองรับ: Ubuntu 24.04 LTS (แนะนำ) / 22.04 LTS · Nginx 1.24+ · Tomcat 9.0.x · MySQL 8.0 · Java 11/17/21 — ตรวจชื่อ package/directive/path ให้ตรงกับที่ติดตั้งจริง_
