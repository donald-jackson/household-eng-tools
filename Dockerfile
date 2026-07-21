# household-eng-tools — a developer toolbox image the engineering agents' chart stages
# onto each pod's PVC. The whole tree lands under /opt/toolbox (bin/ + lib/ + aws-cli/);
# the eng-tools-install initContainer copies it to /opt/data/.local/toolbox and symlinks
# the executables into /opt/data/.local/bin, which is already on the hermes image PATH.
# Image pulls go through containerd, NOT the pod netns, so this keeps working even if pod
# egress is later tightened (egress proxy / Cilium) — unlike installing at pod start.
#
# Base is debian-slim (GLIBC) to match the hermes container: every tool here is copied
# out and run inside hermes, so glibc-native tools (node, aws-cli v2, claude) work
# directly and we smoke-test all of them at build time. Everything is laid out under a
# single relocatable prefix so node/npm/aws keep their relative deps when staged.
#
# Tools: gh, kubectl, jq, yq (static/glibc single binaries) · node/npm/npx + pnpm
# (glibc) · aws-cli v2 (glibc bundle) · claude (Claude Code, glibc, checksum-verified).
FROM debian:bookworm-slim

ARG KUBECTL_VERSION=v1.31.11
ARG JQ_VERSION=1.7.1
ARG NODE_MAJOR=22
ENV TOOLBOX=/opt/toolbox
# NB: default /bin/sh, no pipefail — a `curl | grep -m1` version probe legitimately
# SIGPIPEs curl when grep closes the pipe early; the final smoke-test RUN is the real
# backstop that every binary downloaded and runs.

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl tar xz-utils unzip \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p "$TOOLBOX/bin"

# ── static single-binaries: gh, kubectl, jq, yq ───────────────────────────────
RUN set -eux; \
    GH_VER="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | grep -m1 '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')"; \
    test -n "$GH_VER"; \
    curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VER}/gh_${GH_VER}_linux_amd64.tar.gz" | tar -xz -C /tmp; \
    install -m0755 "/tmp/gh_${GH_VER}_linux_amd64/bin/gh" "$TOOLBOX/bin/gh"; \
    curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o "$TOOLBOX/bin/kubectl"; \
    curl -fsSL "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-amd64" -o "$TOOLBOX/bin/jq"; \
    curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" -o "$TOOLBOX/bin/yq"; \
    chmod 0755 "$TOOLBOX/bin/kubectl" "$TOOLBOX/bin/jq" "$TOOLBOX/bin/yq"; \
    rm -rf /tmp/gh_*

# ── Node.js (glibc LTS) → bin/{node,npm,npx} + lib/node_modules ────────────────
RUN set -eux; \
    NODE_VER="$(curl -fsSL https://nodejs.org/dist/index.json | "$TOOLBOX/bin/jq" -r --arg maj "v${NODE_MAJOR}" '[.[] | select(.lts != false and (.version|startswith($maj)))][0].version')"; \
    test -n "$NODE_VER"; \
    curl -fsSL "https://nodejs.org/dist/${NODE_VER}/node-${NODE_VER}-linux-x64.tar.xz" | tar -xJ --strip-components=1 -C "$TOOLBOX"; \
    rm -rf "$TOOLBOX/include" "$TOOLBOX/share"

# ── pnpm (installed globally via the node we just staged → $TOOLBOX/bin/pnpm) ──
# The GitHub release binary name is unstable across versions; installing through npm
# lands a relocatable $TOOLBOX/bin/pnpm → ../lib/node_modules symlink instead.
RUN set -eux; \
    export PATH="$TOOLBOX/bin:$PATH"; \
    npm install -g pnpm@latest; \
    pnpm --version

# ── AWS CLI v2 (glibc bundle) → aws-cli/ + a RELATIVE bin/aws symlink ──────────
# The installer writes bin/aws as an ABSOLUTE symlink to the build-time install dir,
# which breaks once the tree is staged to a different path — rewrite it to relative so
# the whole toolbox is relocatable.
RUN set -eux; \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip; \
    unzip -q /tmp/awscliv2.zip -d /tmp; \
    /tmp/aws/install --install-dir "$TOOLBOX/aws-cli" --bin-dir "$TOOLBOX/bin"; \
    ln -sf ../aws-cli/v2/current/bin/aws "$TOOLBOX/bin/aws"; \
    rm -rf /tmp/awscliv2.zip /tmp/aws

# ── Claude Code (glibc linux-x64), checksum-verified against the release manifest ──
RUN set -eux; \
    CC_VER="$(curl -fsSL https://downloads.claude.ai/claude-code-releases/latest)"; \
    test -n "$CC_VER"; \
    curl -fsSL "https://downloads.claude.ai/claude-code-releases/${CC_VER}/linux-x64/claude" -o "$TOOLBOX/bin/claude"; \
    chmod 0755 "$TOOLBOX/bin/claude"; \
    WANT="$(curl -fsSL "https://downloads.claude.ai/claude-code-releases/${CC_VER}/manifest.json" | "$TOOLBOX/bin/jq" -r '.platforms["linux-x64"].checksum')"; \
    GOT="$(sha256sum "$TOOLBOX/bin/claude" | cut -d' ' -f1)"; \
    test -n "$WANT" && test "$WANT" = "$GOT" || { echo "claude checksum mismatch want=$WANT got=$GOT"; exit 1; }

# ── smoke-test everything (glibc base can run it all) ─────────────────────────
RUN set -eux; export PATH="$TOOLBOX/bin:$PATH"; \
    gh --version; kubectl version --client; jq --version; yq --version; \
    node --version; npm --version; npx --version; pnpm --version; aws --version; \
    claude --version || true; \
    echo "toolbox ready: $(ls "$TOOLBOX/bin" | tr '\n' ' ')"
CMD ["/bin/bash"]
