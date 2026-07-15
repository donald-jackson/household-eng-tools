# household-eng-tools — a tiny toolbox image the engineering agents' chart copies
# gh + kubectl + jq + claude out of, onto each pod's PVC bin dir
# (/opt/data/.local/bin, already on the hermes image PATH). Image pulls go through
# containerd, NOT the pod netns, so this keeps working even if pod egress is later
# tightened (egress proxy / Cilium) — unlike downloading the binaries at pod start.
#
# The binaries are copied out of this alpine (musl) image and run inside the
# glibc-based hermes container, so each must be glibc-portable:
#   - gh, kubectl        : static Go builds (fine anywhere).
#   - jq                 : STATIC release binary from jqlang (the Alpine apk jq is
#                          musl-linked and fails on glibc: "cannot execute").
#   - claude (Claude Code): the native CLI has separate glibc + musl builds; we pull
#                          the GLIBC linux-x64 build (hermes is glibc). We do NOT run
#                          it here (musl base can't exec a glibc binary) — it's
#                          checksum-verified, copied out, and runs in hermes.
FROM alpine:3.20
ARG KUBECTL_VERSION=v1.31.11
ARG JQ_VERSION=1.7.1
RUN set -eux; \
    apk add --no-cache ca-certificates curl tar coreutils; \
    GH_VER="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest \
      | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -1)"; \
    test -n "$GH_VER"; \
    curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VER}/gh_${GH_VER}_linux_amd64.tar.gz" -o /tmp/gh.tgz; \
    tar -xzf /tmp/gh.tgz -C /tmp; \
    install -m0755 "/tmp/gh_${GH_VER}_linux_amd64/bin/gh" /usr/local/bin/gh; \
    curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl; \
    chmod 0755 /usr/local/bin/kubectl; \
    curl -fsSL "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-amd64" -o /usr/local/bin/jq; \
    chmod 0755 /usr/local/bin/jq; \
    gh --version; kubectl version --client; jq --version; \
    ! (ldd /usr/local/bin/jq 2>/dev/null | grep -q '=>') || (echo "jq is dynamically linked!" && exit 1)
# Claude Code (glibc linux-x64), checksum-verified against the release manifest.
RUN set -eux; \
    CC_VER="$(curl -fsSL https://downloads.claude.ai/claude-code-releases/latest)"; \
    test -n "$CC_VER"; \
    curl -fsSL "https://downloads.claude.ai/claude-code-releases/${CC_VER}/linux-x64/claude" -o /usr/local/bin/claude; \
    chmod 0755 /usr/local/bin/claude; \
    WANT="$(curl -fsSL "https://downloads.claude.ai/claude-code-releases/${CC_VER}/manifest.json" | jq -r '.platforms["linux-x64"].checksum')"; \
    GOT="$(sha256sum /usr/local/bin/claude | cut -d' ' -f1)"; \
    test -n "$WANT" && test "$WANT" = "$GOT" || (echo "claude checksum mismatch want=$WANT got=$GOT" && exit 1); \
    echo "claude ${CC_VER} linux-x64 sha256 OK ($GOT)"
CMD ["/bin/sh"]
