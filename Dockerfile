FROM node:22-bookworm-slim@sha256:a149cd71dccd68704a07d4e4ca3e610c27301852b0f556865cfdb6e2856f8bed

ARG PI_VERSION=0.42.0

RUN apt-get update \
    && apt-get install -y --no-install-recommends bash ca-certificates git openssh-client \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 10001 --shell /bin/bash pi \
    && mkdir -p /opt/pi /opt/pi-secure /workspace \
    && touch /opt/pi-secure/auth.json \
    && chown -R pi:pi /opt/pi /opt/pi-secure /workspace /home/pi

COPY config/settings.json /opt/pi-secure/settings.json
COPY docker/entrypoint.sh /usr/local/bin/pi-secure-entrypoint
RUN chmod 0755 /usr/local/bin/pi-secure-entrypoint

USER pi
RUN npm install --prefix /opt/pi "@earendil-works/pi-coding-agent@${PI_VERSION}"
WORKDIR /workspace

ENV PATH="/opt/pi/bin:$PATH" \
    HOME=/home/pi \
    PI_CODING_AGENT_DIR=/home/pi/.pi/agent \
    PI_OFFLINE=1 \
    PI_SKIP_VERSION_CHECK=1 \
    PI_TELEMETRY=0

ENTRYPOINT ["pi-secure-entrypoint"]
CMD []
