# household-eng-tools

A tiny toolbox image (`gh` + `kubectl` + `jq`) that the engineering-agent Helm
chart (`ddj-eks-workloads` → `lib/household-agent-chart`) copies onto each agent
pod's PVC via an initContainer. Kept out of the GitOps repo because that repo
holds no image builds. Built by GHA → `ghcr.io/donald-jackson/household-eng-tools`.
