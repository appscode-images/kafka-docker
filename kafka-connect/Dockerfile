FROM openjdk:11-jre-buster

ARG KAFKA_VERSION
ARG SCALA_VERSION
ARG KAFKA_REGISTRY
ENV HOME=/opt/kafka
ENV PATH=${PATH}:${HOME}/bin

# This Dockerfile is used to build a Kafka Connect image with the specified Kafka version.
# It sets the image name and version as labels and specifies the source code repository.
LABEL name="kafka-connect" version=${KAFKA_VERSION}
LABEL org.opencontainers.image.source=https://github.com/kubedb/kafka-docker

# Install wget and vim, download Kafka from the specified registry, extract it to /opt,
# move it to the user's home directory, and remove unnecessary files.
RUN apt-get update \
 && apt-get install -y wget vim \
 && wget -O /tmp/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz ${KAFKA_REGISTRY}/${KAFKA_VERSION}/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz \
 && tar xfz /tmp/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz -C /opt \
 && rm /tmp/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz \
 && mv /opt/kafka_${SCALA_VERSION}-${KAFKA_VERSION} ${HOME} \
 && rm -rf /opt/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz \
 && rm -rf /opt/kafka/bin/windows /opt/kafka/config/kraft /opt/kafka/site-docs \
 && rm -rf /opt/kafka/bin/zookeeper-*.sh

# Copy scripts directory to the home directory of the container
COPY scripts/ ${HOME}/scripts/
# Create a kafka group with GID 1001 and a kafka user with UID 1001.
# The user's home directory is set to $HOME and the shell is set to /bin/bash.
# The kafka user is made the owner of $HOME and /tmp directories.
RUN groupadd -r -g 1001 kafka && \
    useradd -m -d $HOME -s /bin/bash -u 1001 -r -g kafka kafka && \
    chown -R kafka:kafka $HOME && chown -R kafka:kafka /tmp

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