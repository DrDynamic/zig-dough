FROM mcr.microsoft.com/devcontainers/base:debian

ARG ZIG_VERSION
ARG MINISIGN_VERSION

RUN apt-get update -yqq && apt-get install -yqq \
    gdb

USER vscode
WORKDIR /home/vscode
ENV PATH="$PATH:/home/vscode/.local/bin"

ADD --chown=vscode:vscode install-zig.sh install-zig.sh
RUN chmod +x install-zig.sh && ./install-zig.sh ${ZIG_VERSION} ${MINISIGN_VERSION}