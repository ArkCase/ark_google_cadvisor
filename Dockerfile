#
# This one houses the main git clone
#
FROM 345280441424.dkr.ecr.ap-south-1.amazonaws.com/ark_base:latest as src

#
# Basic Parameters
#
ARG ARCH="amd64"
ARG OS="linux"
ARG VER="0.39.3"
ARG PKG="google_cadvisor"
ARG SRC="https://github.com/google/cadvisor.git"

#
# Some important labels
#
LABEL ORG="Armedia LLC"
LABEL MAINTAINER="Armedia Devops Team <devops@armedia.com>"
LABEL APP="Google cAdvisor"
LABEL VERSION="${VER}"

WORKDIR /src

#
# Download the primary artifact
#
RUN yum -y update && yum -y install git && git clone -b "v${VER}" --single-branch "${SRC}" "/src"

#
# This one builds the artifacts
#
FROM 345280441424.dkr.ecr.ap-south-1.amazonaws.com/ark_base:latest as build

#
# Basic Parameters
#
ARG ARCH="amd64"
ARG OS="linux"
ARG VER="0.39.3"
ARG PKG="google_cadvisor"
ARG PFM_MAJ="4"
ARG PFM_MIN="11"
ARG PFM_REL="0"
ARG PFM_VER="${PFM_MAJ}.${PFM_MIN}.${PFM_REL}"
ARG PFM_TAR="libpfm-${PFM_VER}.tar.gz"
ARG PFM_SRC="https://sourceforge.net/projects/perfmon2/files/libpfm${PFM_MAJ}/${PFM_TAR}"
ARG PFM_SHA="112bced9a67d565ff0ce6c2bb90452516d1183e5"
ARG GO_VER="1.16.7"
ARG GO_SRC="https://golang.org/dl/go${GO_VER}.${OS}-${ARCH}.tar.gz"

#
# Set the Go environment
#
ENV GOROOT="/usr/local/go"
ENV GOPATH="/go"
ENV PATH="${PATH}:${GOROOT}/bin"
#ENV GO_FLAGS="-tags=libpfm,netgo,libipmctl"
ENV GO_FLAGS="-tags=libpfm,netgo"

#
# Download and install go
#
RUN curl -L "${GO_SRC}" -o - | tar -C "/usr/local" -xzf -

#
# Some important labels
#
LABEL ORG="Armedia LLC"
LABEL MAINTAINER="Armedia Devops Team <devops@armedia.com>"
LABEL APP="Google cAdvisor"
LABEL VERSION="${VER}"

#
# Download and install the compilation tools
#
# In case we want to support these later:
#        zfs
#        fortify-headers
#        ipmctl
#        libipmctl
RUN yum -y install epel-release
RUN yum -y install \
        bash \
        cmake \
        compat-glibc \
        device-mapper \
        device-mapper-persistent-data \
        findutils \
        gcc \
        gcc-c++ \
        git \
        kernel-headers \
        make \
        ndctl-devel \
        patch \
        python3 \
        pkgconfig \
        wget && \
    echo 'hosts: files mdns4_minimal [NOTFOUND=return] dns mdns4' >> /etc/nsswitch.conf && \
    yum -y clean all

#
# Set the working directory for all builds
#
WORKDIR /usr/src/app/

#
# Build libpfm
#
RUN curl -L "${PFM_SRC}" -o "${PFM_TAR}" && \
    echo "${PFM_SHA}  ${PFM_TAR}" | sha1sum -c && \
    tar -xzf "${PFM_TAR}" && \
    cd "libpfm-${PFM_VER}" && \
    export DBG="-g -Wall" && \
    make && \
    make install

#
# Build cAdvisor
#
WORKDIR "${GOPATH}/src/github.com/google/cadvisor"
COPY --from=src /src "${GOPATH}/src/github.com/google/cadvisor"
RUN ./build/build.sh

#
# The actual runnable container
#
FROM 345280441424.dkr.ecr.ap-south-1.amazonaws.com/ark_base:latest

#
# Basic Parameters
#
ARG ARCH="amd64"
ARG OS="linux"
ARG VER="0.39.3"
ARG PKG="google_cadvisor"
ARG SRC="https://github.com/google/cadvisor.git"
ARG UID="root"

#
# Some important labels
#
LABEL ORG="Armedia LLC"
LABEL MAINTAINER="Armedia Devops Team <devops@armedia.com>"
LABEL APP="Google cAdvisor"
LABEL VERSION="${VER}"

#
# Some useful environment variables
#
ENV GOROOT="/usr/local/go"
ENV GOPATH="/go"
ENV CADVISOR_HEALTHCHECK_URL="http://localhost:8080/healthz"

#
# In case we want to support it later:
#       zfs
RUN yum -y install \
        compat-glibc \
        device-mapper \
        device-mapper-persistent-data \
        findutils \
        libpfm \
        ndctl \
        wget && \
    echo 'hosts: files mdns4_minimal [NOTFOUND=return] dns mdns4' >> /etc/nsswitch.conf && \
    yum -y clean all

#
# Copy the built artifacts
#
COPY --from=build /usr/local/lib/libpfm.so* /usr/local/lib/
# COPY --from=build /usr/local/lib/libipmctl.so* /usr/local/lib/
COPY --from=build "${GOPATH}/src/github.com/google/cadvisor/cadvisor" /usr/local/bin/cadvisor

#
# Final parameters
#
USER        ${UID}
EXPOSE      8080
ENTRYPOINT  [ "/usr/local/bin/cadvisor", "-logtostderr" ]
HEALTHCHECK --interval=30s --timeout=3s \
            CMD wget --quiet --tries=1 --spider "${CADVISOR_HEALTHCHECK_URL}" || exit 1
