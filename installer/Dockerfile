# ============================================================================
# Lemonade Stand Assistant Installer
# ============================================================================
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

RUN microdnf install -y \
    python3 \
    python3-pip \
    jq \
    tar \
    gzip \
    bc \
    openssl \
    gettext \
    && microdnf clean all

# OpenShift CLI
RUN curl -L https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz -o /tmp/oc.tar.gz && \
    tar -xzvf /tmp/oc.tar.gz -C /usr/local/bin/ oc && \
    chmod +x /usr/local/bin/oc && \
    rm /tmp/oc.tar.gz

# Helm CLI
RUN curl -L https://get.helm.sh/helm-v3.14.0-linux-amd64.tar.gz | \
    tar -xzv -C /tmp && \
    mv /tmp/linux-amd64/helm /usr/local/bin/helm && \
    chmod +x /usr/local/bin/helm && \
    rm -rf /tmp/linux-amd64

# Copy installer scripts
COPY installer/entrypoint.sh /installer/entrypoint.sh
COPY installer/lib/ /installer/lib/
RUN chmod +x /installer/entrypoint.sh /installer/lib/*.sh

# Copy Helm chart
COPY chart/ /installer/chart/

# Copy quickstart manifest
COPY quickstart-manifest.yaml /installer/manifest.yaml

WORKDIR /installer

ENTRYPOINT ["/installer/entrypoint.sh"]
