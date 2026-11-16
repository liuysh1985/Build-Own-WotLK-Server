# How to build server
## Prerequisite
As the docker images are built from source in Linux environment, below tools are required:
- Docker community edition
- git


## Code Repositories
|Repo Name|Github Link|Branch Name|
|-|---|--|
|azerothcore-wotlk|https://github.com/mod-playerbots/azerothcore-wotlk|Playerbot|
|mod-playerbots|https://github.com/mod-playerbots/mod-playerbots|master|
|mod-autobalance|https://github.com/azerothcore/mod-autobalance|master|
|mod-individual-progression|https://github.com/ZhengPeiRu21/mod-individual-progression|master|
|mod-transmog|https://github.com/azerothcore/mod-transmog|master|
|mod-ale|https://github.com/azerothcore/mod-ale|master (kept, but disabled at runtime via `ALE.Enabled=false`)|
|mod-ah-bot|https://github.com/azerothcore/mod-ah-bot|master|
|mod-ollama-chat|https://github.com/DustinHendrickson/mod-ollama-chat|main|


For exploring available modules, access [Azerothcore Catalogue](https://www.azerothcore.org/catalogue.html#/)

## (Optional) Proxy Setting
This helps a lot when pulling packages/code in container
```bash
# Ubuntu 26.04
cat <<EOF | sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf
[Service]
Environment="HTTP_PROXY=http://[PROXY_IP]:[PROXY_PORT]"
Environment="HTTPS_PROXY=http://[PROXY_IP]:[PROXY_PORT]"
Environment="NO_PROXY=localhost,127.0.0.1,192.168.0.0/16"
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker
```

## Clone code and Build images locally
Clone into the canonical base dir (default `$HOME/WotLK`, see `start-server.sh --base-dir`) so the launch flow finds both the clone (`<base-dir>/azerothcore-wotlk`) and the runtime (`<base-dir>/runtime`).
```bash
# Create the base dir first, put everything into the folder
mkdir -p $HOME/WotLK && cd $HOME/WotLK
git clone https://github.com/mod-playerbots/azerothcore-wotlk --branch Playerbot --depth 1
cd azerothcore-wotlk/modules
# Clone required modules from github one by one
git clone <MODULE_GITHUB_LINK>
# Once the code is downloaded, build images from source
cd ../
DOCKER_IMAGE_TAG=v20261113 docker compose build
# Check images after image building
docker images
```

## (Optional) Download Maps data
In the AZ server first startup, it will try to download maps data from github repo [client-data](https://github.com/wowgaming/client-data). To speed up the downloading, we can download the required zip file using any tools and extract the zip file content to Server Data Directory.

Alternatively, extract from a real game client with the `tools` compose profile (`docker compose --profile tools run --rm ac-tools`). This works because the base compose file lives inside the clone, so the extractor image's build context resolves there.


## (Optional) Chinese (zhCN) server translations
Translate server-side texts (quests/items/NPC dialogue/system strings) by updating the database with SQL files from [AC_db_chinese](https://github.com/gswxy/AC_db_chinese). No recompiling needed: the core loads locale tables and returns strings per client language, so zhCN and enUS clients coexist.
```bash
# Prerequisite: Python 3.8+. The commands below use the `mysql` client via --mysql-cli;
# alternatively drop that flag and `pip3 install pymysql`.
git clone https://github.com/gswxy/AC_db_chinese && cd AC_db_chinese

# Convert locales/world/20_acore_string/acore_string_zhCN.sql to support new structure
python3 -c '
import re

path = "locales/world/20_acore_string/acore_string_zhCN.sql"
with open(path, "r", encoding="utf-8") as f:
    lines = f.readlines()

pattern = re.compile(
    r"^\s*UPDATE\s+`acore_string`\s+SET\s+`locale_zhCN`\s*=\s*(\x27(?:\\.|[^\x27])*\x27)\s+WHERE\s+`entry`\s*=\s*(\d+).*?;",
    re.IGNORECASE
)

out = []
converted = 0

for line in lines:
    m = pattern.match(line)
    if m:
        content, entry = m.group(1), m.group(2)
        out.append(f"INSERT IGNORE INTO `acore_string_locale` (`entry`, `locale`, `content`) VALUES ({entry}, \x27zhCN\x27, {content});\n")
        converted += 1
    else:
        out.append(line)

with open(path, "w", encoding="utf-8") as f:
    f.writelines(out)

print(f"Conversion complete: {converted} records converted.")
'

# DRY RUN (install.py does not write to the DB without --apply).
# $RUNTIME_DIR is the runtime dir from start-server.sh (default $HOME/WotLK/runtime).
python3 scripts/install.py --mysql-cli --host SERVER_IP --user root --password "$(cat $RUNTIME_DIR/db.password)"

# Once the dry run looks right, apply:
python3 scripts/install.py --mysql-cli --host SERVER_IP --user root --password "$(cat $RUNTIME_DIR/db.password)" --apply

# (Optional) also install the Playerbots localization (bot chat lines & Chinese name pools):
python3 scripts/install.py --mysql-cli --host SERVER_IP --user root --password "$(cat $RUNTIME_DIR/db.password)" --apply --playerbots
```

## Realm setting
```bash
# Use mysql client.
mysql -h <SERVER_IP> -u root -p

UPDATE acore_auth.realmlist 
SET 
    address = '<TAILSCALE_IP>',      -- Your server's Tailscale 100.x.y.z IP
    localAddress = '<LAN_IP>',       -- Your server's internal LAN IP
    localSubnetMask = '255.255.255.0' 
WHERE id = 1;
```

## Create first account
```bash
# Attach to the worldserver RAS console; detach with Ctrl-P then Ctrl-Q
docker compose attach ac-worldserver

account create ACCOUNT_NAME PASSWORD EMAIL
account set addon ACCOUNT_NAME 2
account set gmlevel ACCOUNT_NAME 3 -1
```
