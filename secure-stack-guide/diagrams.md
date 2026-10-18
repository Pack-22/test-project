# Secure Stack — แผนภาพ (Diagrams)

ภาพรวมของคู่มือ Secure Stack · GitHub เรนเดอร์บล็อก Mermaid ด้านล่างเป็นรูปให้อัตโนมัติ

---

## 1. สถาปัตยกรรม / request flow

เส้นทางของ request และจุดที่แต่ละ component เปิดรับ · firewall เปิดแค่พอร์ต **22 / 80 / 443** · MySQL กับ Tomcat listen เฉพาะ localhost · ทั้งดิสก์เข้ารหัสด้วย LUKS

```mermaid
flowchart TB
    client["Client / Browser"]

    subgraph host["Server host — UFW firewall (เปิดแค่ 22/80/443) — disk encrypted (LUKS)"]
        direction TB
        nginx["Nginx<br/>:443 TLS (public) · :80 redirect<br/>security headers, rate limit"]
        tomcat["Tomcat 9<br/>:8080 — 127.0.0.1 เท่านั้น<br/>รันเป็น user 'tomcat' (nologin)"]
        app["App (WAR)"]
        mysql[("MySQL 8<br/>:3306 — 127.0.0.1 เท่านั้น<br/>user จำกัดสิทธิ์")]
    end

    client -->|"HTTPS 443"| nginx
    nginx -->|"proxy HTTP 127.0.0.1:8080<br/>X-Forwarded-For"| tomcat
    tomcat --> app
    app -->|"JDBC 127.0.0.1:3306"| mysql
```

---

## 2. RBAC / สิทธิ์ผู้ใช้

นิยามสิทธิ์ไว้ที่ **group** ไม่ใช่ที่ตัวคน · เพิ่ม/ถอดคน = เปลี่ยน group ไม่ต้องแก้สิทธิ์รายคน · `tomcat` เป็น service account (nologin) ที่เป็นเจ้าของแอปที่รันอยู่

```mermaid
flowchart LR
    admin["somchai<br/>(admin)"]
    deployer["deployer"]
    logviewer["logviewer"]

    gsudo{{"group: sudo"}}
    gdeploy{{"group: app-deploy"}}
    glog{{"group: app-logview"}}
    svc["tomcat<br/>service account (nologin)"]

    admin --> gsudo
    deployer --> gdeploy
    logviewer --> glog

    gsudo -->|"sudo เต็ม"| c1["ดูแลระบบได้ทุกอย่าง"]
    gdeploy -->|"ACL เขียน webapps"| c2["วาง / ทับ WAR"]
    gdeploy -->|"sudo (restart/status เท่านั้น)"| c3["Restart Tomcat"]
    glog -->|"ACL อ่าน logs"| c4["อ่าน log อย่างเดียว<br/>(แก้/ลบไม่ได้)"]
    svc -->|"เจ้าของ process + ไฟล์"| c5["รันแอป · อ่าน WAR"]
```

---

## 3. Logging & retention

ใคร/อะไรถูกบันทึก ลงไฟล์ไหน และ retention ในเครื่อง (default **90 วัน รายวัน**) · ถ้าต้องเก็บยาว (เช่น 1 ปีตาม PCI-DSS) ให้ ship ออก central server

```mermaid
flowchart LR
    u1["เข้าเครื่อง<br/>(SSH / sudo)"] --> l1["auth.log + audit.log<br/>90 วัน — auditd timer รายวัน"]
    u2["เข้าเว็บ<br/>(ภายนอก)"] --> l2["Nginx access.log / error.log<br/>90 วัน — logrotate"]
    u3["ระดับแอป<br/>(session, เวลาตอบ)"] --> l3["Tomcat access / catalina / gc<br/>90 วัน — maxDays + logrotate"]
    u4["systemd services"] --> l4["journald<br/>90 วัน — MaxRetentionSec"]

    l1 --> central[("Central log server<br/>rsyslog / ELK / Loki<br/>1 ปีขึ้นไป · กันแก้/ลบ")]
    l2 --> central
    l3 --> central
    l4 --> central
```

---

## 4. Runbook แก้ปัญหา (decision tree)

request เดินทาง Client → Nginx → Tomcat → app → MySQL · เช็กสุขภาพรวมก่อน แล้วไล่ตามอาการ (ดู log ทีละชั้น)

```mermaid
flowchart TD
    start(["เจอปัญหา"]) --> health["เช็กสุขภาพรวม:<br/>systemctl status nginx tomcat mysql<br/>df -h · free -h · ss -tulpn"]
    health --> q{"อาการ?"}

    q -->|"502 / 503"| d1["nginx error.log →<br/>tomcat status + :8080 →<br/>catalina.out"]
    q -->|"500"| d2["nginx access.log (500) →<br/>catalina.out + localhost.log<br/>(stack trace)"]
    q -->|"ช้า"| d3["$request_time → Tomcat %D →<br/>gc.log → top / free"]
    q -->|"OOM / เด้งซ้ำ"| d4["journalctl -u tomcat →<br/>grep OOM → heap dump →<br/>เพิ่ม -Xmx (5.7)"]
    q -->|"ต่อ DB ไม่ได้"| d5["catalina.out → mysql error.log →<br/>ss :3306 → SHOW GRANTS"]
    q -->|"SSH เข้าไม่ได้"| d6["ssh -v → auth.log →<br/>AllowUsers / สิทธิ์ key →<br/>fail2ban unban"]
    q -->|"ดิสก์เต็ม"| d7["df -h → du → เช็ก<br/>logrotate / maxDays (5.8)"]
    q -->|"HTTPS / cert"| d8["certbot certificates →<br/>renew --dry-run →<br/>letsencrypt log"]
    q -->|"รีบูตแล้วค้าง"| d9["LUKS: SSH เข้า initramfs →<br/>cryptroot-unlock (2.1)"]
```
