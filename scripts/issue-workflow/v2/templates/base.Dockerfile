# Phase 0 spike: pi in a Docker Sandbox template.
#
# Spike finding (Task 0.3): sbx custom templates must extend a published
# docker/sandbox-templates:<variant> image — the plan's `node:24-bookworm-slim`
# base does not fit the sbx template model. We extend the `shell` variant
# (no agent pre-installed; pi is invoked directly via `sbx exec`) and then
# install the plan's node:24 toolchain on top.
#
# No credentials are baked in. Model keys enter the sandbox only through the
# sbx host-side credential proxy at request time (the sandbox sees a
# placeholder like `sbx-cs-<rand>`).

FROM docker/sandbox-templates:shell

USER root

# node:24 + git + ripgrep + jq (plan §4.3 toolchain; the shell variant is
# Ubuntu-based, so NodeSource provides the node:24-bookworm-slim equivalent).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl ca-certificates gnupg git ripgrep jq \
    && curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Go toolchain (Task 3.2 — mechanical adjustment: the plan's node:24
# toolchain covers JS, but this repo is Go; implementer/reviewer sandboxes
# must run typecheck + tests). Pinned official tarball; arm64 = the Apple
# silicon host platform. Module downloads go through proxy.golang.org,
# which the task-* roles' network policy allows.
RUN curl -fsSLo /tmp/go.tgz https://go.dev/dl/go1.26.0.linux-arm64.tar.gz \
    && rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go.tgz && rm /tmp/go.tgz \
    && ln -s /usr/local/go/bin/go /usr/local/bin/go \
    && go version

# Go review skills (Phase 4 Task 4.1 — parity with CI's review.yml, which
# clones samber/cc-skills-golang and loads the golang-* skills via --skill;
# dispatch.sh passes the same --skill flags against this bake for the five
# reviewer roles). Pinned to the commit the pr-pipeline matrix expects.
RUN git clone --depth 1 https://github.com/samber/cc-skills-golang.git /opt/cc-skills-golang \
    && git -C /opt/cc-skills-golang checkout --quiet 30cdf15cde8db8730c42a2918d7cdb4505f5ff54 \
    && rm -rf /opt/cc-skills-golang/.git

# Commits made inside implementer sandboxes must carry the project identity
# (same as the host git config) and must not trip git's ownership check on
# host-mounted worktree files (safe.directory). Changing the image requires
# a host rebuild + sbx template load (run_worktree_test.sh does it).
RUN git config --global user.name "Aleksandar Radovanovic" \
    && git config --global user.email "aleksrdvn@192.168.1.5" \
    && git config --global --add safe.directory '*'

# pi — global install with --ignore-scripts, same as CI (review.yml).
RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent \
    && pi --version

USER agent
