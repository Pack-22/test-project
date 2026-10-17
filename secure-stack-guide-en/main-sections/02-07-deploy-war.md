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
