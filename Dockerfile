#
# Copyright (c) 2021 Pterodactyl
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

FROM --platform=$TARGETOS/$TARGETARCH debian:bullseye-slim

LABEL author="Isaac A." maintainer="isaac@isaacs.site"
LABEL org.opencontainers.image.source="https://github.com/pterodactyl/yolks"
LABEL org.opencontainers.image.licenses=MIT

ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies, Node.js, and create the 'container' user.
# This RUN instruction must be completed as root.
RUN dpkg --add-architecture i386 \
    && apt update \
    && apt upgrade -y \
    && apt install -y lib32gcc-s1 lib32stdc++6 unzip curl iproute2 tzdata libgdiplus libsdl2-2.0-0:i386 \
    && apt install -y locales xz-utils libncurses5:i386 libtinfo5:i386 libcurl4 \
    && sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && dpkg-reconfigure --frontend=noninteractive locales \
    && update-locale LANG=en_US.UTF-8 \
    && curl -sL https://deb.nodesource.com/setup_14.x | bash - \
    && apt install -y nodejs \
    && mkdir /node_modules \
    && npm install --prefix / ws \
    && useradd -d /home/container -m container \
    && apt clean && rm -rf /var/lib/apt/lists/*

# Install SteamCMD itself as root, and set ownership and execute permissions here.
# This RUN instruction is performed by root (before the USER switch).
RUN mkdir -p /usr/local/bin/steamcmd-tool \
    && cd /usr/local/bin/steamcmd-tool \
    && curl -sSL -o steamcmd.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
    && tar -xzvf steamcmd.tar.gz \
    && rm steamcmd.tar.gz \
    && chmod +x steamcmd.sh \
    && chmod -R +x . \
    && chown -R container:container /usr/local/bin/steamcmd-tool \
    && mkdir -p /home/container/steamapps \
    \
    # Robustes SteamCMD-Setup beim Build:
    # Nur SteamCMD selbst initialisieren (+quit), NICHT das Spiel herunterladen.
    # Das Spiel wird später von entrypoint.sh im /home/container Verzeichnis installiert.
    && RETRIES=5 && COUNT=0 && \
    while [ $COUNT -lt $RETRIES ]; do \
        echo "Attempting SteamCMD self-initialisation (Attempt $((COUNT + 1))/$RETRIES)..." && \
        /usr/local/bin/steamcmd-tool/steamcmd.sh +quit && \
        echo "SteamCMD self-initialisation successful." && break; \
        COUNT=$((COUNT + 1)); \
        echo "SteamCMD self-initialisation failed. Retrying in 10 seconds..."; \
        sleep 10; \
    done \
    && if [ $COUNT -eq $RETRIES ]; then echo "SteamCMD self-initialisation failed after $RETRIES attempts." && exit 1; fi

# Switch to the 'container' user. All subsequent RUN, CMD, or ENTRYPOINT commands will be run as this user.
USER container
ENV USER=container HOME=/home/container

WORKDIR /home/container

# Copy entrypoint and wrapper scripts into the container
COPY ./entrypoint.sh /entrypoint.sh
COPY ./wrapper.js /wrapper.js

# Set the entrypoint for the container
CMD [ "/bin/bash", "/entrypoint.sh" ]
