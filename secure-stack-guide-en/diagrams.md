# Secure Stack — Diagrams

Visual overview of the Secure Stack guide. GitHub renders these Mermaid blocks as diagrams automatically.

---

## 1. Architecture / request flow

How a request travels, and where each component is exposed. Only ports **22 / 80 / 443** are open at the firewall; MySQL and Tomcat listen on localhost only; the whole disk is encrypted with LUKS.

```mermaid
flowchart TB
    client["Client / Browser"]

    subgraph host["Server host — UFW firewall (only 22/80/443 open) — disk encrypted with LUKS"]
        direction TB
        nginx["Nginx<br/>:443 TLS (public) · :80 redirect<br/>security headers, rate limit"]
        tomcat["Tomcat 9<br/>:8080 — 127.0.0.1 only<br/>runs as user 'tomcat' (nologin)"]
        app["App (WAR)"]
        mysql[("MySQL 8<br/>:3306 — 127.0.0.1 only<br/>least-privilege user")]
    end

    client -->|"HTTPS 443"| nginx
    nginx -->|"proxy HTTP 127.0.0.1:8080<br/>X-Forwarded-For"| tomcat
    tomcat --> app
    app -->|"JDBC 127.0.0.1:3306"| mysql
```

---

## 2. RBAC / user permissions

Permissions are defined on **groups**, not people. Add/remove a person by changing their group membership — never per-person permissions. `tomcat` is a nologin service account that owns the running app.

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

    gsudo -->|"full sudo"| c1["Administer everything"]
    gdeploy -->|"ACL write on webapps"| c2["Drop / overwrite WAR"]
    gdeploy -->|"sudo (restart/status only)"| c3["Restart Tomcat"]
    glog -->|"ACL read on logs"| c4["Read logs only<br/>(no edit/delete)"]
    svc -->|"owns process + files"| c5["Run app · read WAR"]
```

---

## 3. Logging & retention

Who/what is recorded, which file it lands in, and the on-machine retention (default **90 days, daily**). For long retention (e.g. 1 year for PCI-DSS) logs are forwarded to a central server.

```mermaid
flowchart LR
    u1["Host access<br/>(SSH / sudo)"] --> l1["auth.log + audit.log<br/>90d — auditd daily timer"]
    u2["Web visitors<br/>(external)"] --> l2["Nginx access.log / error.log<br/>90d — logrotate"]
    u3["App level<br/>(session, timing)"] --> l3["Tomcat access / catalina / gc<br/>90d — maxDays + logrotate"]
    u4["systemd services"] --> l4["journald<br/>90d — MaxRetentionSec"]

    l1 --> central[("Central log server<br/>rsyslog / ELK / Loki<br/>1 year+ · tamper-resistant")]
    l2 --> central
    l3 --> central
    l4 --> central
```

---

## 4. Troubleshooting runbook (decision tree)

A request travels Client → Nginx → Tomcat → app → MySQL. Check overall health first, then follow the branch for your symptom (trace the logs layer by layer).

```mermaid
flowchart TD
    start(["Problem reported"]) --> health["Health check:<br/>systemctl status nginx tomcat mysql<br/>df -h · free -h · ss -tulpn"]
    health --> q{"Symptom?"}

    q -->|"502 / 503"| d1["nginx error.log →<br/>tomcat status + :8080 →<br/>catalina.out"]
    q -->|"500"| d2["nginx access.log (500) →<br/>catalina.out + localhost.log<br/>(stack trace)"]
    q -->|"Slow"| d3["$request_time → Tomcat %D →<br/>gc.log → top / free"]
    q -->|"OOM / restart loop"| d4["journalctl -u tomcat →<br/>grep OOM → heap dump →<br/>raise -Xmx (5.7)"]
    q -->|"DB error"| d5["catalina.out → mysql error.log →<br/>ss :3306 → SHOW GRANTS"]
    q -->|"No SSH"| d6["ssh -v → auth.log →<br/>AllowUsers / key perms →<br/>fail2ban unban"]
    q -->|"Disk full"| d7["df -h → du → check<br/>logrotate / maxDays (5.8)"]
    q -->|"HTTPS / cert"| d8["certbot certificates →<br/>renew --dry-run →<br/>letsencrypt log"]
    q -->|"Hang after reboot"| d9["LUKS: SSH to initramfs →<br/>cryptroot-unlock (2.1)"]
```
