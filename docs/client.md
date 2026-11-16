# Client - WOW 3.3.5a
Build a pure client which supports en-US and zh-CN(optional).

## Download and re-pack a usable client
- (Recommended) Download below files from [Internet Archive](https://archive.org/download/WoW_3.3.5-12340)
    - 3.3.5-12340_Common.zip
    - 3.3.5-12340_enUS.zip
    - (Optional) 3.3.5-12340_zhCN.zip
- Download a pure WotLK 3.3.5a client from [DKPMINUS Website](https://www.dkpminus.com/blog/wow-wotlk-3-3-5a-download-wrath-of-the-lich-king-client/) using a BT downloader.


### LLA Patch `Wow.exe`
```bash
# Patch on macOS or Linux
cd $CLIENT_DIR
python3 -c '
import struct, shutil
shutil.copy2("Wow.exe", "Wow.exe.bak")
with open("Wow.exe", "r+b") as f:
    f.seek(0x3C)
    pe_offset = struct.unpack("<I", f.read(4))[0]
    char_offset = pe_offset + 22
    f.seek(char_offset)
    chars = struct.unpack("<H", f.read(2))[0]
    if chars & 0x0020:
        print("Already LAA (4GB) patched, nothing to do.")
    else:
        f.seek(char_offset)
        f.write(struct.pack("<H", chars | 0x0020))
        print("LAA patch applied successfully! Backup saved as Wow.exe.bak")
'
```

### Chinese (zhCN) client locale (Optional)
- Extract the contents of `3.3.5-12340_zhCN.zip` into `$CLIENT_DIR/Data`, so the locale MPQs sit next to the Common ones
- Launch the game with `Wow.exe --set-lang zhCN` to select the Chinese locale
- This only localizes the client itself. Server-side texts (quests/items/NPC dialogue/system strings) are translated separately — see `(Optional) Chinese (zhCN) server translations` in `docs/server.md`. zhCN and enUS clients coexist without affecting each other

### Project Reforged HD Patches
A modular suite that brings HD models, textures and rendering improvements to the 3.3.5a (build 12340) client. Compatible with any standard 3.3.5 server. Install only what you need.

1. Dependency (required): [St0ny's AIO WoW EXE Patcher](https://github.com/Raz0r1337/St0nys-AIO-WoW-EXE-Patcher)
    - Put the script files into `$CLIENT_DIR` and run the `.bat` (on macOS run it via CrossOver/Wine)
    - Choose the language, then apply the patches; optionally download the Project Reforged Preset `patcher_selection.ini` to apply the recommended configuration automatically
2. Dependency (recommended): [DXVK 3.1.1](https://github.com/Raz0r1337/dxvk/releases)
    - Extract the 32-bit (x86) build and copy `d3d9.dll` into `$CLIENT_DIR`
3. Core patches — download from https://projectreforged.github.io/wotlk/downloads/ and drop the MPQs into `$CLIENT_DIR/Data`:
    - Patch-A (HD characters & NPCs — required by Patch-C)
    - Patch-C (creatures)
    - Patch-B + Patch-D + Patch-E (buildings / doodads / environment — must be installed together, or not at all)
    - Patch-G (gear & weapons)
4. (Optional) Patch-N (darker nights), Patch-P (spell particle effects)

### AddOns
- Download available addons from [Legacy WOW](https://legacy-wow.com/wotlk-addons/)
    - Atlasloot
    - Bagnon
    - DBM
    - SexyMap
    - ...
- Download [Questie-335](https://github.com/widxwer/Questie)
- (Optional) Download **ElvUI** from [ElvUI-WotLK](https://github.com/ElvUI-WotLK/ElvUI)
- (Optional) Download **MultiBot** from [Github Repo](https://github.com/Macx-Lio/MultiBot)
- (Optional) Download **ConsolePort** from [ConsolePortLK](https://github.com/leoaviana/ConsolePortLK) or [ConsolePortLK-Enhanced](https://github.com/SuttonX/ConsolePortLK-Enhanced)

Put all addons into folder `$CLIENT_DIR/Interface/AddOns`


## Realm setting
Update the realm address in file `$CLIENT_DIR/Data/enUS/realmlist.wtf` to the server remote ip or domain name.
```
set realmlist SERVER_IP
```


## HOWTO in different OS

### Linux
Wine, Proton

### Windows
Native Support

### Mac
Parallels Desktop, CrossOver(bad performance)
