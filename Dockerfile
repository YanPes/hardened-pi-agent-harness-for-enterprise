FROM node:22-bookworm-slim@sha256:a149cd71dccd68704a07d4e4ca3e610c27301852b0f556865cfdb6e2856f8bed

ARG PI_VERSION=0.80.2

RUN apt-get update \
  && apt-get install -y --no-install-recommends bash ca-certificates git gosu openssh-client fd-find ripgrep \
  && ln -s /usr/bin/fdfind /usr/local/bin/fd \
  && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 10001 --shell /bin/bash pi \
  && mkdir -p /opt/pi /opt/pi-secure /opt/pi-agent-seed /workspace /home/pi/.pi /home/pi/.pi/agent \
  && chown -R pi:pi /opt/pi /opt/pi-secure /opt/pi-agent-seed /workspace /home/pi

COPY config/settings.json /opt/pi-secure/settings.json
COPY docker/entrypoint.sh /usr/local/bin/pi-secure-entrypoint
RUN chmod 0755 /usr/local/bin/pi-secure-entrypoint

USER pi
RUN npm install --prefix /opt/pi "@earendil-works/pi-coding-agent@${PI_VERSION}"

# Set PATH and env vars before any pi commands so the binary is resolvable
ENV PATH="/opt/pi/node_modules/.bin:/opt/pi/bin:$PATH" \
  HOME=/home/pi \
  PI_CODING_AGENT_DIR=/home/pi/.pi/agent \
  PI_OFFLINE=1 \
  PI_SKIP_VERSION_CHECK=1 \
  PI_TELEMETRY=0

# Pre-install pi packages (skills, etc.) into a seed dir baked into the image.
COPY config/settings.json /opt/pi-agent-seed/settings.json
RUN PI_CODING_AGENT_DIR=/opt/pi-agent-seed \
  PI_OFFLINE=0 \
  PI_SKIP_VERSION_CHECK=1 \
  PI_TELEMETRY=0 \
  pi install git:github.com/makoit/pi-forgeflow

WORKDIR /workspace

USER root
ENTRYPOINT ["pi-secure-entrypoint"]
CMD []
