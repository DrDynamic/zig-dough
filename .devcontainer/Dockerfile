FROM ubuntu:questing-20250601

# Common part (in every dev image)
ARG USERNAME="developer"
ARG USER_UID=1000
ARG USER_GID=1000

ENV USERNAME=$USERNAME
ENV USER_UID=$USER_UID
ENV USER_GID=$USER_GID

# Zig Specific part
ARG MINISIGN_VERSION="0.12"
ARG ZIG_VERSION="0.14.1"
ARG ZLS_VERSION="0.14.0"

RUN apt-get update -yqq \
&& apt-get install -yqq \
  xz-utils \
  ca-certificates

RUN mkdir -p /opt/build
ADD --chown=developer:developer --chmod=555 ./build.sh /opt/build/build.sh
RUN /opt/build/build.sh

ADD --chown=developer:developer ./zshrc /home/developer/.zshrc


RUN apt-get update -yqq && apt-get install -yqq \
    gdb


RUN chown developer:developer /opt

USER developer
WORKDIR /opt
ENV PATH="$PATH:/opt/bin"

ADD --chown=developer:developer --chmod=555 ./install-zig.sh /opt/build/install-zig.sh
RUN /opt/build/install-zig.sh ${MINISIGN_VERSION} ${ZIG_VERSION} ${ZLS_VERSION}

USER root
ADD --chown=developer:developer --chmod=555 ./install-dart.sh /opt/build/install-dart.sh
RUN /opt/build/install-dart.sh

USER developer
WORKDIR /home/developer

#FROM mcr.microsoft.com/devcontainers/base:debian
#
#ARG ZIG_VERSION
#ARG MINISIGN_VERSION
#
#RUN apt-get update -yqq && apt-get install -yqq \
#    gdb
#
#USER vscode
#WORKDIR /home/vscode
#ENV PATH="$PATH:/home/vscode/.local/bin"
#
#ADD --chown=vscode:vscode install-zig.sh install-zig.sh
#RUN chmod +x install-zig.sh && ./install-zig.sh ${ZIG_VERSION} ${MINISIGN_VERSION}