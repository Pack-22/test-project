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
