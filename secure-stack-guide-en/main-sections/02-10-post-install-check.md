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
