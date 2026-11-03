# tokenspeed.eroeasy.com

Two pages, one stylesheet, two screenshots and an icon. No build step, no JavaScript, no
third-party fonts — the whole directory is a document root you can `rsync`
anywhere.

| file | what it is |
|---|---|
| `index.html` | English page (canonical: `https://tokenspeed.eroeasy.com/`) |
| `zh.html` | 简体中文 (`https://tokenspeed.eroeasy.com/zh.html`) |
| `assets/styles.css` | one stylesheet; dark by default, light via `prefers-color-scheme` |
| `assets/*.png` | icon + real screenshots of this app (panel shots use a scrubbed local fixture, labelled as sample data) |

Preview locally:

```bash
python3 -m http.server 8080 --directory site
```

## nginx

`ts.eroeasy.com` exists only to be short enough to type, so it must redirect
rather than serve a second copy of the site — two live URLs for one site is how
README files and bookmarks end up disagreeing.

```nginx
# short alias -> canonical host
server {
    listen 80;
    server_name ts.eroeasy.com;
    return 301 https://tokenspeed.eroeasy.com$request_uri;
}
server {
    listen 443 ssl http2;
    server_name ts.eroeasy.com;
    ssl_certificate     /etc/letsencrypt/live/eroeasy.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/eroeasy.com/privkey.pem;
    return 301 https://tokenspeed.eroeasy.com$request_uri;
}

server {
    listen 80;
    server_name tokenspeed.eroeasy.com;
    return 301 https://$host$request_uri;
}
server {
    listen 443 ssl http2;
    server_name tokenspeed.eroeasy.com;
    ssl_certificate     /etc/letsencrypt/live/eroeasy.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/eroeasy.com/privkey.pem;

    root /srv/tokenspeed.eroeasy.com;   # contents of this directory, not the directory itself
    index index.html;

    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy same-origin always;
    add_header Strict-Transport-Security "max-age=63072000" always;

    location ~* \.(png|css)$ {
        expires 7d;
        add_header Cache-Control "public, max-age=604800, immutable";
    }
}
```

Caddy, if that is what is on the box:

```caddy
ts.eroeasy.com { redir https://tokenspeed.eroeasy.com{uri} permanent }
tokenspeed.eroeasy.com {
    root * /srv/tokenspeed.eroeasy.com
    encode gzip
    file_server
}
```

## Deploy

```bash
rsync -a --delete site/ user@host:/srv/tokenspeed.eroeasy.com/
```

`--delete` matters: without it, a page you removed from the repo keeps being
served from the server forever.

## Before the DNS points here

`ts` and `tokenspeed` both need A/AAAA records for the server, and a certificate
covering `eroeasy.com` (the nginx block above reuses one SAN set for both
hosts). Until those exist, the 「项目主页」 link in the About window is a dead
link — `AppInfo.siteURL` can be set back to `nil` for any release cut first.
