# Build cruise control image to get the metrics reporter jar file
FROM eclipse-temurin:17.0.10_7-jdk AS cruise_control
ARG CC_VERSION

# Fetch Cruise-Control binary
# https://github.com/linkedin/cruise-control/releases contains all the kafka release binary
RUN set -eux \
    && apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends ca-certificates wget git \
    && wget -O /opt/cc.tar.gz https://github.com/linkedin/cruise-control/archive/refs/tags/${CC_VERSION}.tar.gz

# Extract
RUN set -eux \
	&& cd /opt \
	&& tar xzvf cc.tar.gz \
	&& mv /opt/cruise-control-* /opt/cruise-control \
    && rm cc.tar.gz

WORKDIR /opt/cruise-control

### Setup git user and init repo, otherwise build gradle will fail
RUN set -eux \
	&& git config --global user.email root@localhost \
	&& git config --global user.name root \
	&& git init \
	&& git add . \
	&& git commit -m "Init local repo." \
	&& git tag -a ${CC_VERSION} -m "Init local version."

### Setup git user and init repo ###
RUN set -eux \
    && ./gradlew clean \
    && ./gradlew jar :cruise-control-metric-reporter:jar

FROM eclipse-temurin:17.0.10_7-jdk

ARG KAFKA_VERSION
ARG SCALA_VERSION
ARG KAFKA_REGISTRY
ARG CC_VERSION
ARG TARGETARCH
ENV HOME=/opt/kafka
ENV PATH=${PATH}:${HOME}/bin

LABEL name="kafka" version=${KAFKA_VERSION}
LABEL org.opencontainers.image.source=https://github.com/kubedb/kafka-docker

RUN apt-get update && apt-get upgrade -y \
 && apt-get install -y wget nano \
 && wget -O /tmp/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz ${KAFKA_REGISTRY}/${KAFKA_VERSION}/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz \
 && tar xfz /tmp/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz -C /opt \
 && rm /tmp/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz \
 && mv /opt/kafka_${SCALA_VERSION}-${KAFKA_VERSION} ${HOME} \
 && rm -rf /opt/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz \
 && rm -rf ${HOME}/bin/windows ${HOME}/site-docs \
 && latest_version=$(curl -s https://api.github.com/repos/deviceinsight/kafkactl/releases/latest | grep "tag_name" | cut -d '"' -f 4 | sed 's/^v//') \
 && curl -LO "https://github.com/deviceinsight/kafkactl/releases/download/v${latest_version}/kafkactl_${latest_version}_linux_${TARGETARCH}.deb" \
 && dpkg -i kafkactl_${latest_version}_linux_${TARGETARCH}.deb \
 && rm kafkactl_${latest_version}_linux_${TARGETARCH}.deb

# Placing the Cruise Control metric reporter jar into the /opt/kafka/libs/ directory of every Kafka broker
# allows Kafka to find the reporter at runtime
COPY --from=cruise_control /opt/cruise-control/cruise-control-metrics-reporter/build/libs/cruise-control-metrics-reporter-${CC_VERSION}.jar /opt/kafka/libs/cruise-control-metrics-reporter.jar
COPY scripts/* /opt/kafka/config/
COPY ./kafka_server_jaas.conf /opt/kafka/config
# Add Prometheus JMX exporter agent
COPY ./jmx-exporter-config.yaml /opt/jmx_exporter/jmx-exporter-config.yaml
RUN wget -O /opt/jmx_exporter/jmx_prometheus_javaagent-0.20.0.jar https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/0.20.0/jmx_prometheus_javaagent-0.20.0.jar
ENV EXTRA_ARGS="$EXTRA_ARGS -javaagent:/opt/jmx_exporter/jmx_prometheus_javaagent-0.20.0.jar=56790:/opt/jmx_exporter/jmx-exporter-config.yaml"
ENV KAFKA_JMX_OPTS="-Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Djava.rmi.server.hostname=127.0.0.1"

# use kafka non-root user with uid 1001
RUN groupadd -r -g 1001 kafka && \
    useradd -m -d $HOME -s /bin/bash -u 1001 -r -g kafka kafka && \
    chown -R kafka:kafka $HOME

# For OpenShift, we need to set the group to 0 and the directory permissions to g=u
RUN chgrp -R 0 $HOME && \
    chmod -R g=u $HOME

USER kafka

RUN ["chmod", "+x", "/opt/kafka/config/entrypoint.sh"]
RUN ["chmod", "+x", "/opt/kafka/config/merge_custom_config.sh"]
RUN ["chmod", "+x", "/opt/kafka/config/start.sh"]

WORKDIR $HOME
EXPOSE 9092 9093 9094 29092

ENTRYPOINT ["/opt/kafka/config/entrypoint.sh"]
