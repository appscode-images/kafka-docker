FROM eclipse-temurin:17.0.10_7-jdk

ARG KAFKA_VERSION
ARG SCALA_VERSION
ARG KAFKA_REGISTRY
ARG JMX_PROMETHEUS_AGENT_VERSION=0.20.0
ENV HOME=/opt/kafka
ENV PATH=${PATH}:${HOME}/bin
# This Dockerfile is used to build a Connect Cluster image with the specified Kafka version.
# It sets the image name and version as labels and specifies the source code repository.
LABEL name="connect-cluster" version=${KAFKA_VERSION}
LABEL org.opencontainers.image.source=https://github.com/kubedb/kafka-docker
# Install wget and nano, download Kafka from the specified registry, extract it to /opt,
# move it to the user's home directory, and remove unnecessary files.
RUN apt-get update && apt-get upgrade -y \
 && apt-get install -y wget nano \
 && wget -O /tmp/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz ${KAFKA_REGISTRY}/${KAFKA_VERSION}/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz \
 && tar xfz /tmp/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz -C /opt \
 && rm /tmp/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz \
 && mv /opt/kafka_${SCALA_VERSION}-${KAFKA_VERSION} ${HOME} \
 && rm -rf /opt/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz \
 && rm -rf /opt/kafka/bin/windows /opt/kafka/config/kraft /opt/kafka/site-docs \
 && rm -rf /opt/kafka/bin/zookeeper-*.sh

# Copy the JAAS configuration file to the config directory of Kafka
COPY ./kafka_connect_jaas.conf /opt/kafka/config

# Add Prometheus JMX exporter agent
COPY ./jmx-exporter-config.yaml /opt/jmx_exporter/jmx-exporter-config.yaml
RUN wget -O /opt/jmx_exporter/jmx_prometheus_javaagent-${JMX_PROMETHEUS_AGENT_VERSION}.jar https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/${JMX_PROMETHEUS_AGENT_VERSION}/jmx_prometheus_javaagent-${JMX_PROMETHEUS_AGENT_VERSION}.jar
ENV EXTRA_ARGS="$EXTRA_ARGS -javaagent:/opt/jmx_exporter/jmx_prometheus_javaagent-${JMX_PROMETHEUS_AGENT_VERSION}.jar=56790:/opt/jmx_exporter/jmx-exporter-config.yaml"
ENV KAFKA_JMX_OPTS="-Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Djava.rmi.server.hostname=127.0.0.1"

# Copy scripts directory to the home directory of the container
COPY scripts/ ${HOME}/scripts/
# Create a kafka group with GID 1001 and a kafka user with UID 1001.
# The user's home directory is set to $HOME and the shell is set to /bin/bash.
# The kafka user is made the owner of $HOME
RUN groupadd -r -g 1001 kafka && \
    useradd -m -d $HOME -s /bin/bash -u 1001 -r -g kafka kafka && \
    chown -R kafka:kafka $HOME
# For OpenShift, we need to set the group to 0 and the directory permissions to g=u
RUN chgrp -R 0 $HOME && \
    chmod -R g=u $HOME
# Set the user to kafka
USER kafka
# Make all scripts in the scripts directory executable
RUN chmod +x ${HOME}/scripts/*.sh
# Set the working directory to the home directory of the kafka user
WORKDIR $HOME
# Expose port 8083
EXPOSE 8083
# Set the entrypoint to /opt/kafka/scripts/entrypoint.sh
ENTRYPOINT ["/opt/kafka/scripts/entrypoint.sh"]