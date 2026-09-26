# Third-party notices

This repository's original files are licensed under the MIT License. The container also contains or downloads separately licensed components:

## Box64

- Project: <https://github.com/ptitSeb/box64>
- Version built by default: 0.4.4
- License: MIT
- License text in the image: `/usr/share/licenses/box64/LICENSE`

## DepotDownloader

- Project: <https://github.com/SteamRE/DepotDownloader>
- Version bundled by default: 3.4.0, Linux ARM64
- License: GPL-2.0
- Binary license text in the image: `/opt/depotdownloader/LICENSE`
- Corresponding tagged source in the image: `/usr/src/DepotDownloader-3.4.0.tar.gz`

## Debian packages

Debian and packages installed from its archives retain their respective licenses. Package copyright information is available under `/usr/share/doc` in the image.

## Valheim Dedicated Server

Valheim Dedicated Server is proprietary software owned by Iron Gate AB. It is not included in this repository or baked into the image. At container startup, DepotDownloader retrieves Steam app 896660 directly into the operator's persistent volume. Operation remains subject to the applicable [Valheim EULA](https://www.valheimgame.com/eula/), Steam terms, and local law.
