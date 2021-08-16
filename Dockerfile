#
# This one houses the main git clone
#
FROM 345280441424.dkr.ecr.ap-south-1.amazonaws.com/ark_base:latest as src

#
# Basic Parameters
#
ARG ARCH="amd64"
ARG OS="linux"
ARG VER="0.40.0"
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
ARG VER="0.40.0"
ARG PKG="google_cadvisor"
ARG PFM_MAJ="4"
ARG PFM_MIN="11"
ARG PFM_REL="0"
ARG PFM_VER="${PFM_MAJ}.${PFM_MIN}.${PFM_REL}"
ARG PFM_SRC="https://sourceforge.net/projects/perfmon2/files/libpfm${PFM_MAJ}/libpfm-${PFM_VER}.tar.gz"
ARG PFM_SHA="112bced9a67d565ff0ce6c2bb90452516d1183e5"
ARG IPMCTL_VER="02.00.00.3820"
ARG IPMCTL_SRC="https://github.com/intel/ipmctl"

#
# Set the Go environment
#
ENV GOROOT="/usr/local/go"
ENV GOPATH="/go"
ENV PATH="${PATH}:${GOROOT}/bin"
ENV GO_FLAGS="-tags=libpfm,netgo,libipmctl"

#
# Some important labels
#
LABEL ORG="Armedia LLC"
LABEL MAINTAINER="Armedia Devops Team <devops@armedia.com>"
LABEL APP="Grafana"
LABEL VERSION="${VER}"

#
# Download and install the compilation tools
#
RUN apk --no-cache add libc6-compat device-mapper findutils zfs build-base linux-headers go python3 bash git wget cmake pkgconfig ndctl-dev && \
    apk --no-cache add thin-provisioning-tools --repository http://dl-3.alpinelinux.org/alpine/edge/main/ && \
    echo 'hosts: files mdns4_minimal [NOTFOUND=return] dns mdns4' >> /etc/nsswitch.conf && \
    rm -rf /var/cache/apk/*

#
# Set the working directory for all builds
#
WORKDIR /usr/src/app/

#
# Build libpfm
#
RUN curl -L "${PFM_SRC}" && \
    echo "${PFM_SHA}  libpfm-${PFM_VER}.tar.gz" | sha1sum -c && \
    tar -xzf "libpfm-${PFM_VER}.tar.gz" && \
    cd "libpfm-${PFM_VER}" && \
    export DBG="-g -Wall" && \
    make && \
    make install

#
# Build libipmctl
#
RUN git clone -b "v${IMPCTL_VER}" "${IPMCTL_SRC}" ipmctl && \
    cd ipmctl && \
    mkdir output && \
    cd output && \
    cmake -DRELEASE=ON -DCMAKE_INSTALL_PREFIX=/ -DCMAKE_INSTALL_LIBDIR=/usr/local/lib .. && \
    make -j all && \
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
ARG VER="0.40.0"
ARG PKG="google_cadvisor"
ARG SRC="https://github.com/google/cadvisor.git"
ARG UID="google"

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

RUN apk --no-cache add libc6-compat device-mapper findutils zfs ndctl && \
    apk --no-cache add thin-provisioning-tools --repository http://dl-3.alpinelinux.org/alpine/edge/main/ && \
    echo 'hosts: files mdns4_minimal [NOTFOUND=return] dns mdns4' >> /etc/nsswitch.conf && \
    rm -rf /var/cache/apk/*

#
# Copy the built artifacts
#
COPY --from=build /usr/local/lib/libpfm.so* /usr/local/lib/
COPY --from=build /usr/local/lib/libipmctl.so* /usr/local/lib/
COPY --from=build "${GOPATH}/src/github.com/google/cadvisor/cadvisor" /usr/local/bin/cadvisor

#
# Final parameters
#
USER        ${UID}
EXPOSE      8080
ENTRYPOINT  [ "/usr/bin/cadvisor", "-logtostderr" ]
HEALTHCHECK --interval=30s --timeout=3s \
            CMD wget --quiet --tries=1 --spider "${CADVISOR_HEALTHCHECK_URL}" || exit 1
