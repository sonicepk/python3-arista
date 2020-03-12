# Copyright (c) 2018 Arista Networks, Inc.  All rights reserved.
# Arista Networks, Inc. Confidential and Proprietary.

FROM golang:1.12.7-alpine3.10 as build
LABEL maintainer="Giuseppe Valente gvalente@arista.com"

ENV CFSSLVERSION 1.3.3

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

RUN apk add --no-cache \
    git=2.22.2-r0 \
    gcc=8.3.0-r0 \
    libc-dev=0.7.1-r0 \
    && wget https://github.com/cloudflare/cfssl/archive/${CFSSLVERSION}.tar.gz \
    && echo "39b42f3f8c22e254fa8ed4079308ecad1b0f77cdb56e57099e434389866e58863687307d6cf0f5ec8e4664ad4743ee8728f47a6a1375f3f74f8206a709f0ffc3  ${CFSSLVERSION}.tar.gz" | sha512sum -c - \
    && tar xvf ${CFSSLVERSION}.tar.gz \
    && mkdir -p /go/src/github.com/cloudflare \
    && mv cfssl-${CFSSLVERSION} /go/src/github.com/cloudflare/cfssl \
    && go install github.com/cloudflare/cfssl/cmd/...

FROM aristanetworks/base:3.9.3
LABEL maintainer="Giuseppe Valente gvalente@arista.com"

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

RUN apk add --no-cache \
    bash=4.4.19-r1 \
    docker=18.09.8-r0 \
    git=2.20.2-r0 \
    libffi=3.2.1-r6 \
    libpq=11.7-r0 \
    libressl=2.7.5-r0 \
    openssh-client=7.9_p1-r6 \
    openvpn=2.4.6-r4 \
    python2=2.7.16-r2 \
    python3=3.6.9-r2 \
    sshpass=1.06-r0 \
    util-linux=2.33-r0 \
 && apk add --virtual build-dependencies --no-cache \
    gcc=8.3.0-r0 \
    libffi-dev=3.2.1-r6 \
    make=4.2.1-r2 \
    musl-dev=1.1.20-r5 \
    libressl-dev=2.7.5-r0 \
    postgresql-dev=11.7-r0 \
    python3-dev=3.6.9-r2 \
 && pip3 install --upgrade pip==19.3.1 \
 && pip3 install \
    ansible==2.9.1 \
    apache-libcloud==2.5.0 \
    docker==4.1.0 \
    jmespath==0.9.4 \
    kubernetes==10.0.1 \
    netaddr==0.7.19 \
    openshift==0.10.1 \
    paramiko==2.7.1 \
    passlib==1.7.1 \
    psycopg2==2.8.3 \
    PyYAML==5.1.1 \
 && apk del build-dependencies \
 && unlink /usr/bin/python \
 && ln -s /usr/bin/python3 /usr/bin/python \
 && chown -R prod:prod /home/prod/.cache

# Install helm and helm-tiller plugin
WORKDIR /tmp

ENV HELM2_VERSION 2.14.2-k8sauthpatch
ENV HELM2_CHECKSUM 143597d3f6a1c294ea08ea339ce43be8f482573ef652e48292bf31077729c969
RUN wget -nv https://github.com/asetty/helm/releases/download/v${HELM2_VERSION}/helm-v${HELM2_VERSION}-linux-amd64.tar.gz \
 && echo "${HELM2_CHECKSUM} helm-v${HELM2_VERSION}-linux-amd64.tar.gz" \
   | sha256sum -c - \
 && tar xvf helm-v${HELM2_VERSION}-linux-amd64.tar.gz \
 && cp linux-amd64/helm /usr/bin/helm2 \
 && cp linux-amd64/tiller /usr/bin/tiller \
 && ln -s /usr/bin/helm2 /usr/bin/helm \
 && rm -rf helm-v${HELM2_VERSION}-linux-amd64.tar.gz linux-amd64

ENV HELM3_VERSION 3.1.0
ENV HELM3_CHECKSUM f0fd9fe2b0e09dc9ed190239fce892a468cbb0a2a8fffb9fe846f893c8fd09de
RUN wget -nv https://get.helm.sh/helm-v${HELM3_VERSION}-linux-amd64.tar.gz \
 && echo "${HELM3_CHECKSUM} helm-v${HELM3_VERSION}-linux-amd64.tar.gz" \
   | sha256sum -c - \
 && tar xvf helm-v${HELM3_VERSION}-linux-amd64.tar.gz \
 && cp linux-amd64/helm /usr/bin/helm3 \
 && rm -rf helm-v${HELM3_VERSION}-linux-amd64.tar.gz linux-amd64 \
 && helm3 plugin install https://github.com/helm/helm-2to3

ENV HELM_HOME /home/prod/.helm
USER prod
RUN mkdir -p ${HELM_HOME}/plugins \
 && helm plugin install https://github.com/rimusz/helm-tiller \
 && helm tiller install

USER root
WORKDIR /home/prod

# Install kubectl
RUN wget -nv https://storage.googleapis.com/kubernetes-release/release/v1.15.0/bin/linux/amd64/kubectl \
  	-O /usr/bin/kubectl \
 && echo "738abf75c58fd0c2ae814ef29901a21ac92dcfec0f31464366d97143487e01ebda400bf4ec4f6882cd13dd205fe197cf8c0a34daa2ce9f10858104c6444846f3  /usr/bin/kubectl" | sha512sum -c - \
 && chmod +x /usr/bin/kubectl \
 && mkdir -m 0777 /home/prod/.kube

# Install cfssl binaries
COPY --from=build /go/bin/cfssl /usr/bin
COPY --from=build /go/bin/cfssl-bundle /usr/bin
COPY --from=build /go/bin/cfssl-certinfo /usr/bin
COPY --from=build /go/bin/cfssl-newkey /usr/bin
COPY --from=build /go/bin/cfssl-scan /usr/bin
COPY --from=build /go/bin/cfssljson /usr/bin
COPY --from=build /go/bin/mkbundle /usr/bin
COPY --from=build /go/bin/multirootca /usr/bin

ENV GCLOUD_VERSION 253.0.0
ENV PATH $PATH:/usr/lib/google-cloud-sdk/bin

# Install gcloud
RUN wget -nv https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-${GCLOUD_VERSION}-linux-x86_64.tar.gz \
    -O google-cloud-sdk.tar.gz \
 && echo "df3834e538025b257b7cc5d6e7518ca16f05e99aa82671dda19045e688b5268a  google-cloud-sdk.tar.gz" | sha256sum -c - \
 && tar xf google-cloud-sdk.tar.gz -C /usr/lib \
 && rm google-cloud-sdk.tar.gz \
 && gcloud config set disable_usage_reporting true \
 && gcloud components install --quiet alpha beta \
 && chown -R prod: /home/prod/.config/gcloud

# Create the jenkins user so this image is usable by pipeline
RUN useradd jenkins -u 10000 -G prod \
 && chmod -R g+w /home/prod

# Create the docker group to match CoreOS
RUN groupadd -g 233 coreosdocker \
 && usermod -a -G coreosdocker prod \
 && usermod -a -G coreosdocker jenkins

# Custom patch built from (for v10.0.0 tag):
# Patch #169 for kubernetes-client https://github.com/kubernetes-client/python-base/pull/169
# https://github.com/kubernetes-client/python-base/pull/169/commits/864563760bbb27e1498f66228c2188e2d6359072.diff
#COPY kubernetes-client-169.diff /tmp/169.diff
# hadolint ignore=DL3003
#RUN cd "$(python -c 'import kubernetes.config, inspect, re; print(re.sub(r"/kubernetes/config/.*", "/kubernetes/", inspect.getfile(kubernetes.config)))')" \
# && patch -p1 < /tmp/169.diff \
# && rm /tmp/169.diff

# Patch #168 for kubernetes-client https://github.com/kubernetes-client/python-base/pull/168
# https://github.com/kubernetes-client/python-base/pull/168/commits/93af4b52bd6e1e6623f923650e4e5f919efe47db.diff
#COPY kubernetes-client-168.diff /tmp/168.diff
# hadolint ignore=DL3003
#RUN cd "$(python -c 'import kubernetes.config, inspect, re; print(re.sub(r"/kubernetes/config/.*", "/kubernetes/", inspect.getfile(kubernetes.config)))')" \
# && patch -p1 < /tmp/168.diff \
# && rm /tmp/168.diff

# Patch #63219 for ansible https://github.com/ansible/ansible/pull/63219
# https://github.com/ansible/ansible/commit/b1cbc89afd573a6e94d4cd77363a470eed899af7.diff
#COPY ansible-63219.diff /tmp/63219.diff
# hadolint ignore=DL3003
#RUN cd "$(python -c 'import ansible, inspect, re; print(re.sub(r"/ansible/__init__.py", "/", inspect.getfile(ansible)))')" \
# && patch -p1 < /tmp/63219.diff \
# && rm /tmp/63219.diff

USER prod
