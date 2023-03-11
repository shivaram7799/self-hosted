FROM ubuntu:20.04

ENV TARGETPLATFORM=linux/amd64
ENV RUNNER_VERSION=2.301.1
ARG RUNNER_CONTAINER_HOOKS_VERSION=0.2.0
# Docker and Docker Compose arguments
ENV CHANNEL=stable
ARG DUMB_INIT_VERSION=1.2.5
ENV ARGOCD_CLI_VERSION=v2.1.2

# Other arguments
ARG DEBUG=false

ENV DEBIAN_FRONTEND=noninteractive

# Use 1001 for compatibility with GitHub-hosted runners
ARG RUNNER_UID=1001

#Add basic dependencies
RUN apt-get update -y \
    && apt-get install -y apt-utils \
    && apt-get install -y software-properties-common \
    && apt-get install -y --no-install-recommends \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    sudo \
    wget

#Install Vault resources
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add - \
    && apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"

#install google-chrome-stable apt
RUN wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo apt-key add - \
    && sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list'

#add apt repositories for kubectl
#RUN curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
#    && echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

#Install kubectl binary
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && curl -LO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256" \
    && echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check \
    && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl


#Install ArgoCD Cli
RUN curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/$ARGOCD_CLI_VERSION/argocd-linux-amd64 \
    && chmod +x /usr/local/bin/argocd

RUN add-apt-repository -y ppa:git-core/ppa \
    && apt-get update -y \
    && apt-get install -y --no-install-recommends \
    awscli \
    build-essential \
    dnsutils \
    ftp \
    git \
    git-lfs \
    google-chrome-stable \
    iproute2 \
    iptables \
    iputils-ping \
    jq \
    libasound2 \
    libgbm-dev \
    libgconf-2-4 \
    libgtk-3-0 \
    libgtk2.0-0 \
    libnotify-dev \
    libnss3 \
    libunwind8 \
    libxss1 \
    libxtst6 \
    locales \
    net-tools \
    netcat \
    openssh-client \
    parallel \
    python3-pip \
    rsync \
    shellcheck \
    sudo \
    telnet \
    time \
    tzdata \
    uidmap \
    unzip \
    upx \
    vault \
    xauth \
    xvfb \
    zip \
    zstd \
    && ln -sf /usr/bin/python3 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip \
    && rm -rf /var/lib/apt/lists/*

# Runner user
RUN adduser --disabled-password --gecos "" --uid $RUNNER_UID runner

ENV HOME=/home/runner

# Set-up subuid and subgid so that "--userns-remap=default" works
RUN set -eux; \
    addgroup --system dockremap; \
    adduser --system --ingroup dockremap dockremap; \
    echo 'dockremap:165536:65536' >> /etc/subuid; \
    echo 'dockremap:165536:65536' >> /etc/subgid

RUN export ARCH=$(echo ${TARGETPLATFORM} | cut -d / -f2) \
    && if [ "$ARCH" = "amd64" ] || [ "$ARCH" = "i386" ]; then export ARCH=x86_64 ; fi \
    && curl -fLo /usr/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v${DUMB_INIT_VERSION}/dumb-init_${DUMB_INIT_VERSION}_${ARCH} \
    && chmod +x /usr/bin/dumb-init

ENV RUNNER_ASSETS_DIR=/runnertmp
RUN export ARCH=$(echo ${TARGETPLATFORM} | cut -d / -f2) \
    && if [ "$ARCH" = "amd64" ] || [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "i386" ]; then export ARCH=x64 ; fi \
    && mkdir -p "$RUNNER_ASSETS_DIR" \
    && cd "$RUNNER_ASSETS_DIR" \
    && curl -fLo runner.tar.gz https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${ARCH}-${RUNNER_VERSION}.tar.gz \
    && tar xzf ./runner.tar.gz \
    && rm runner.tar.gz \
    && ./bin/installdependencies.sh \
    && mv ./externals ./externalstmp \
    # libyaml-dev is required for ruby/setup-ruby action.
    # It is installed after installdependencies.sh and before removing /var/lib/apt/lists
    # to avoid rerunning apt-update on its own.
    && apt-get install -y libyaml-dev \
    && rm -rf /var/lib/apt/lists/*

ENV RUNNER_TOOL_CACHE=/opt/hostedtoolcache
RUN mkdir /opt/hostedtoolcache \
    && chgrp runner /opt/hostedtoolcache \
    && chmod g+rwx /opt/hostedtoolcache

RUN cd "$RUNNER_ASSETS_DIR" \
    && curl -fLo runner-container-hooks.zip https://github.com/actions/runner-container-hooks/releases/download/v${RUNNER_CONTAINER_HOOKS_VERSION}/actions-runner-hooks-k8s-${RUNNER_CONTAINER_HOOKS_VERSION}.zip \
    && unzip ./runner-container-hooks.zip -d ./k8s \
    && rm -f runner-container-hooks.zip

# Make the rootless runner directory executable
RUN mkdir /run/user/$RUNNER_UID \
    && chown runner:runner /run/user/$RUNNER_UID \
    && chmod a+x /run/user/$RUNNER_UID

# We place the scripts in `/usr/bin` so that users who extend this image can
# override them with scripts of the same name placed in `/usr/local/bin`.
COPY entrypoint-dind-rootless.sh startup.sh logger.sh graceful-stop.sh update-status /usr/bin/
RUN chmod +x /usr/bin/entrypoint-dind-rootless.sh /usr/bin/startup.sh

# Copy the docker shim which propagates the docker MTU to underlying networks
# to replace the docker binary in the PATH.
COPY docker-shim.sh /usr/local/bin/docker

# Configure hooks folder structure.
COPY hooks /etc/arc/hooks/

# Add the Python "User Script Directory" to the PATH
ENV PATH="${PATH}:${HOME}/.local/bin:/home/runner/bin"
ENV ImageOS=ubuntu20
ENV XDG_RUNTIME_DIR=/run/user/$RUNNER_UID

RUN echo "PATH=${PATH}" > /etc/environment \
    && echo "ImageOS=${ImageOS}" >> /etc/environment \
    && echo "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}" >> /etc/environment

# No group definition, as that makes it harder to run docker.
USER runner

# This will install docker under $HOME/bin according to the content of the script
RUN export SKIP_IPTABLES=1 \
    && curl -fsSL https://get.docker.com/rootless | sh \
    && /home/runner/bin/docker -v

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["entrypoint-dind-rootless.sh"]
