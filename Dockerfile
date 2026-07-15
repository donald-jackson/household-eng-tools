# household-eng-tools — a tiny toolbox image the engineering agents' chart copies
# gh + kubectl + jq out of, onto each pod's PVC bin dir (/opt/data/.local/bin,
# already on the hermes image PATH). Image pulls go through containerd, NOT the
# pod netns, so this keeps working even if pod egress is later tightened
# (egress proxy / Cilium) — unlike downloading the binaries at pod start.
#
# ALL THREE must be statically linked: the binaries are copied out of this alpine
# (musl) image and run inside the glibc-based hermes container. gh + kubectl are
# static Go builds (fine). jq must be the STATIC release binary from jqlang — the
# Alpine apk jq is dynamically musl-linked and fails on glibc with
# "cannot execute: required file not found".
FROM alpine:3.20
ARG KUBECTL_VERSION=v1.31.11
ARG JQ_VERSION=1.7.1
RUN set -eux; \
    apk add --no-cache ca-certificates curl tar; \
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
    rm -rf /tmp/*; \
    gh --version; kubectl version --client; jq --version; \
    # portability sanity: static binaries have no interpreter / no libc deps
    ! (ldd /usr/local/bin/jq 2>/dev/null | grep -q '=>') || (echo "jq is dynamically linked!" && exit 1)
CMD ["/bin/sh"]
