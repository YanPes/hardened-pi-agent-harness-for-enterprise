FROM node:22-bookworm-slim

ARG PI_VERSION=latest

RUN apt-get update \
    && apt-get install -y --no-install-recommends bash ca-certificates git openssh-client \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g "@earendil-works/pi-coding-agent@${PI_VERSION}"

RUN useradd --create-home --uid 10001 --shell /bin/bash pi \
    && mkdir -p /opt/pi-secure /workspace \
    && touch /opt/pi-secure/auth.json \
    && chown -R pi:pi /opt/pi-secure /workspace /home/pi

COPY config/settings.json /opt/pi-secure/settings.json
COPY docker/entrypoint.sh /usr/local/bin/pi-secure-entrypoint
RUN chmod 0755 /usr/local/bin/pi-secure-entrypoint

USER pi
WORKDIR /workspace

ENV HOME=/home/pi \
    PI_CODING_AGENT_DIR=/home/pi/.pi/agent \
    PI_OFFLINE=1 \
    PI_SKIP_VERSION_CHECK=1 \
    PI_TELEMETRY=0

ENTRYPOINT ["pi-secure-entrypoint"]
CMD []
