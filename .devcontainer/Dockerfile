FROM ruby:3.2.5

ARG BOSH_CLI_VERSION
ARG CHRUBY_VERSION

ENV DEBIAN_FRONTEND="noninteractive"
ENV GEM_HOME=/home/vscode/.gems

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        apt-transport-https \
        build-essential \
        ca-certificates \
        curl \
        direnv \
        gcc \
        gettext-base \
        git \
        gnupg \
        jq \
        libreadline-dev \
        libssl-dev \
        libxslt1-dev \
        libxml2-dev \
        libyaml-dev \
        libsqlite3-dev \
        lsb-release \
        make \
        openssl \
        python3-pip \
        sqlite3 \
        sudo \
        wget \
        zlib1g-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN wget https://github.com/cloudfoundry/bosh-cli/releases/download/v${BOSH_CLI_VERSION}/bosh-cli-${BOSH_CLI_VERSION}-linux-amd64 -O /usr/local/bin/bosh && \
    chmod +x /usr/local/bin/bosh

RUN wget -O chruby.tar.gz https://github.com/postmodern/chruby/archive/v${CHRUBY_VERSION}.tar.gz && \
    tar -xzvf chruby.tar.gz && \
    cd chruby-*/ && \
    make install && \
    cd .. && \
    rm -rf ./chruby-* && \
    chmod +x /usr/local/share/chruby/chruby.sh && \
    echo 'source /usr/local/share/chruby/chruby.sh' >> ~/.profile

RUN useradd -ms /bin/bash vscode \
    && echo vscode ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/vscode \
    && chmod 0440 /etc/sudoers.d/vscode

RUN echo 'gem: --no-document' > /etc/gemrc && \
    gem update --system && \
    bundle config --global path "${GEM_HOME}" && \
    bundle config --global bin "${GEM_HOME}/bin" && \
    mkdir -p "${GEM_HOME}"/gems && \
    gem install bundler && \
    gem install deep_merge && \
    gem install rubocop && \
    gem install ruby-debug-ide && \
    gem install debug && \
    gem install ruby-lsp

RUN echo 'eval "$(direnv hook bash)"' >> ~/.profile

USER vscode