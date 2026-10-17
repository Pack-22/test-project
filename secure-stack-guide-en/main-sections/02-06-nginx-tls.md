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
