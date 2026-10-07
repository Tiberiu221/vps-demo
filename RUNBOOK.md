# RUNBOOK: primul deploy pe Linux (Ubuntu 24.04), de la zero până la final

**Rezultat:** app-ul Express rulează ca serviciu **systemd** sub userul `app`, în spatele **nginx** (port 80), cu firewall **ufw**, config în env file și loguri în **journald**. Durată: ~1–1,5 h.
**Legendă:** **[Mac]** = terminal în `~/Desktop/vps-demo` · **[root]** = sesiunea `ssh root@IP` · **[app]** = sesiunea `ssh app@IP`. Înlocuiește `IP` peste tot.
Rulează comenzile **pe rând, câte una**: dacă lipești un bloc întreg, o linie poate ajunge ca răspuns la un prompt (parolă, `yes/no`).

## 0. Cheia SSH (pe Mac)
```bash
cat ~/.ssh/id_ed25519.pub
```
→ o linie `ssh-ed25519 AAAA...`. Dacă lipsește: `ssh-keygen -t ed25519`.

## 1. Serverul
**Varianta A: Hetzner Cloud** (~0,006 €/h, se plătește)
1. console.hetzner.cloud → proiect → **Add Server** → Image **Ubuntu 24.04**, Type **CX22** (sau cel mai mic x86 afișat), **SSH keys** → lipește cheia (`pbcopy < ~/.ssh/id_ed25519.pub`).
2. **Create & Buy now** → notează IPv4. ⚠️ La final: **Delete server** (și un server oprit se facturează). Cont nou: poate cere verificare; dacă durează, mergi pe B.

**Varianta B: VM local gratuit (Multipass)**
```bash
brew install --cask multipass        # cere parola de Mac
printf '#cloud-config\ndisable_root: false\nssh_authorized_keys:\n  - %s\n' "$(cat ~/.ssh/id_ed25519.pub)" > ~/vps-cloud-init.yaml
multipass launch 24.04 --name vps --cloud-init ~/vps-cloud-init.yaml
multipass info vps
```
→ `Launched: vps` (prima dată descarcă imaginea, câteva minute), apoi `IPv4: 192.168.64.X` = IP-ul tău. VM-ul e accesibil de pe Mac (ssh, `curl http://IP`, browser). cloud-init îți pune cheia și la root, deci **de aici pașii sunt identici cu Hetzner**.
Fără cloud-init: `multipass launch 24.04 --name vps` → `multipass shell vps` → `sudo -i` (= root). Fișierele le copiezi cu `multipass transfer deploy/setup-server.sh vps:/tmp/`, iar ca user app intri cu `sudo -iu app`.

## 2. Primul SSH + bootstrap
[Mac]
```bash
scp deploy/setup-server.sh root@IP:
ssh root@IP
```
→ prima dată: `Are you sure you want to continue connecting (yes/no/[fingerprint])?` → `yes`; promptul devine `root@...:~#`.
[root]
```bash
bash setup-server.sh
```
→ pașii `==> [1/6]` … `[6/6]`, apoi la final:
```
node v22.x.x, npm 10.x.x, nginx version: nginx/1.24.0 (Ubuntu)
-rw------- 1 root root ... /etc/vps-demo/app.env
Status: active   (OpenSSH, 80/tcp, 443/tcp: ALLOW Anywhere, plus v6)
```
Ce face: user `app` (fără parolă, doar cheie SSH; sudo doar pentru `systemctl restart vps-demo`), ufw (22/80/443), Node 22 (NodeSource), nginx, git, `/etc/vps-demo/app.env` (chmod 600). E idempotent, îl poți rula din nou.

## 3. Codul pe server, ca `app`
**Cu git (recomandat).** Pe github.com/new creează repo **public** gol `vps-demo` (fără README; nu conține secrete), apoi:
[Mac]
```bash
git remote add origin git@github.com:Tiberiu221/vps-demo.git && git push -u origin main
ssh app@IP          # tab nou; root rămâne deschis în celălalt
```
[app]
```bash
git clone https://github.com/Tiberiu221/vps-demo.git && cd vps-demo && npm ci --omit=dev
```
→ `added 68 packages ... found 0 vulnerabilities`; promptul `app@...:~/vps-demo$` (userul nou intră cu aceeași cheie).
**Cu scp (fără GitHub)**, [Mac]:
```bash
ssh app@IP 'mkdir -p vps-demo'
scp -r server.js package.json package-lock.json deploy app@IP:vps-demo/
ssh app@IP 'cd vps-demo && npm ci --omit=dev'
```

## 4. Env file (config/secrete pe server, nu în git)
[root]
```bash
nano /etc/vps-demo/app.env      # APP_NAME=change-me → APP_NAME=vps-demo-tiberiu; Ctrl+O, Enter, Ctrl+X
ls -l /etc/vps-demo/app.env
```
→ `-rw------- 1 root root`. Test [app]: `cat /etc/vps-demo/app.env` → `Permission denied` (corect: doar root/systemd îl citește).

## 5. Serviciul systemd
[root]
```bash
cp /home/app/vps-demo/deploy/vps-demo.service /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now vps-demo
systemctl status vps-demo --no-pager
curl -s http://127.0.0.1:3000/health
journalctl -u vps-demo -f       # loguri live; Ctrl+C ca să ieși
```
→ `Created symlink ... multi-user.target.wants/vps-demo.service`, `Active: active (running)`, `Main PID: ... (node)`, în log `vps-demo-tiberiu v1.0.0 listening on http://127.0.0.1:3000`; curl → `{"status":"ok"}`.
Bonus `Restart=always`: `systemctl kill -s KILL vps-demo; sleep 4; systemctl status vps-demo --no-pager` → din nou `active (running)`, alt PID; în journal: `status=9/KILL` și `Scheduled restart job`.

## 6. nginx ca reverse proxy (80 → 127.0.0.1:3000)
[root]
```bash
cp /home/app/vps-demo/deploy/nginx-vps-demo.conf /etc/nginx/sites-available/vps-demo
ln -sf /etc/nginx/sites-available/vps-demo /etc/nginx/sites-enabled/vps-demo
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx
```
→ `syntax is ok` și `test is successful`.
[Mac]
```bash
curl -I http://IP
curl http://IP/
```
→ `HTTP/1.1 200 OK`, `Server: nginx/1.24.0 (Ubuntu)`, `X-Powered-By: Express` (cererea a trecut prin nginx până în Node), apoi `{"app":"vps-demo-tiberiu","version":"1.0.0","hostname":"...","uptimeSeconds":...}`.
În `journalctl -u vps-demo -f` apare IP-ul Mac-ului (din `X-Forwarded-For`). Portul 3000 nu e public: `curl -m 3 http://IP:3000` → timeout/eroare (corect).

## 7. Modific codul și fac redeploy
[Mac]
```bash
npm version minor --no-git-tag-version          # 1.0.0 → 1.1.0 în package.json + lock
git commit -m "Release 1.1.0" package.json package-lock.json && git push
```
[app]
```bash
bash ~/vps-demo/deploy/deploy.sh
```
→ `git pull` (Fast-forward) → `npm ci` → restart → `{"status":"ok"}` → `==> Deploy OK`; în ultimele 20 de linii: `SIGTERM received, closing server` (procesul vechi s-a oprit curat) și `... v1.1.0 listening`. [Mac] `curl http://IP/` → `"version":"1.1.0"`.
Cu scp: `scp package.json package-lock.json app@IP:vps-demo/`, apoi același `deploy.sh`.

## 8. Schimb o variabilă de mediu + restart
[root]
```bash
sed -i 's/^APP_NAME=.*/APP_NAME=vps-demo-env-2/' /etc/vps-demo/app.env
curl -s http://127.0.0.1:3000/      # încă numele vechi: env-ul se citește doar la pornire
systemctl restart vps-demo
curl -s http://127.0.0.1:3000/      # "app":"vps-demo-env-2", uptimeSeconds aproape 0
```

## Depanare rapidă
- `Could not get lock /var/lib/dpkg/lock-frontend` → update-uri automate la primul boot: așteaptă 1–2 min și rulează din nou `bash setup-server.sh`.
- `Permission denied (publickey)` → altă cheie: `ssh -i ~/.ssh/CHEIA root@IP`.
- `REMOTE HOST IDENTIFICATION HAS CHANGED` (ai recreat VM-ul) → `ssh-keygen -R IP`.
- `No route to host` spre 192.168.64.X → System Settings → Privacy & Security → Local Network → bifează aplicația de terminal; oprește VPN-ul.
- `502 Bad Gateway` → Node nu rulează: `systemctl status vps-demo`, `journalctl -u vps-demo -n 50 --no-pager`.
- Apare „Welcome to nginx!” → n-ai șters `/etc/nginx/sites-enabled/default`.
- `journalctl` ca app arată „No entries” → `exit` și reconectează-te (grupul `systemd-journal` se aplică la login nou).

## Curățenie
Hetzner: Console → server → **Delete**. Multipass: `multipass delete --purge vps` și `rm ~/vps-cloud-init.yaml`.

## Notițele mele
- Varianta folosită / IP:
- Ce a mers diferit față de runbook și cum am rezolvat:
