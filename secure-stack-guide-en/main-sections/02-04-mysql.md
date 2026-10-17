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
