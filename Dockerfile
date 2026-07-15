# household-eng-tools — a tiny toolbox image the engineering agents' chart copies
# gh + kubectl + jq out of, onto each pod's PVC bin dir (/opt/data/.local/bin,
# already on the hermes image PATH). Image pulls go through containerd, NOT the
# pod netns, so this keeps working even if pod egress is later tightened
# (egress proxy / Cilium) — unlike downloading the binaries at pod start.
# Binaries are static Go builds, so an alpine (musl) base runs them fine anywhere.
FROM alpine:3.20
ARG KUBECTL_VERSION=v1.31.11
RUN set -eux; \
    apk add --no-cache ca-certificates curl tar jq; \
    # gh — pin to the current latest release (fetched at build time)
    GH_VER="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest \
      | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -1)"; \
    test -n "$GH_VER"; \
    curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VER}/gh_${GH_VER}_linux_amd64.tar.gz" -o /tmp/gh.tgz; \
    tar -xzf /tmp/gh.tgz -C /tmp; \
    install -m0755 "/tmp/gh_${GH_VER}_linux_amd64/bin/gh" /usr/local/bin/gh; \
    # kubectl — pinned to the cluster version
    curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl; \
    chmod 0755 /usr/local/bin/kubectl; \
    rm -rf /tmp/*; \
    gh --version; kubectl version --client; jq --version
CMD ["/bin/sh"]
