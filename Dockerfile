# Build cruise control image to get the metrics reporter jar file
FROM gradle:jdk11 AS cruise_control

ENV CC_VERSION=2.5.42

# Fetch Cruise-Control binary
# https://github.com/linkedin/cruise-control/releases contains all the kafka release binary
RUN set -eux \
    && apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends ca-certificates wget \
    && wget -O /tmp/cc.tar.gz https://github.com/linkedin/cruise-control/archive/refs/tags/${CC_VERSION}.tar.gz

# Extract
RUN set -eux \
	&& cd /tmp \
	&& tar xzvf cc.tar.gz \
	&& mv /tmp/cruise-control-* /tmp/cruise-control \
    && rm cc.tar.gz

### Setup git user and init repo, otherwise build gradle will fail
RUN set -eux \
	&& cd /tmp/cruise-control \
	&& git config --global user.email root@localhost \
	&& git config --global user.name root \
	&& git init \
	&& git add . \
	&& git commit -m "Init local repo." \
	&& git tag -a ${CC_VERSION} -m "Init local version."

### Setup git user and init repo ###
RUN set -eux \
    && cd /tmp/cruise-control \
    && ./gradlew jar :cruise-control-metric-reporter:jar

# Build Kafka
FROM openjdk:11-jre-buster AS Kafka

ARG KAFKA_VERSION=3.3.2
ENV KAFKA_VERSION=${KAFKA_VERSION}
ENV SCALA_VERSION=2.13
ENV HOME=/opt/kafka
ENV PATH=${PATH}:${HOME}/bin

LABEL name="kafka" version=${KAFKA_VERSION}
LABEL org.opencontainers.image.source https://github.com/kubedb/kafka-docker


# https://archive.apache.org/dist/kafka contains all the kafka version binary
RUN apt-get update \
 && apt-get install wget \
 && wget -O /tmp/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz \
 && tar xfz /tmp/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz -C /opt \
 && rm /tmp/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz \
 && mv /opt/kafka_${SCALA_VERSION}-${KAFKA_VERSION} ${HOME} \
 && rm -rf /opt/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz

COPY ./entrypoint.sh /opt/kafka/config
COPY ./kafka_server_jaas.conf /opt/kafka/config
# Add Prometheus JMX exporter agent
COPY ./jmx-exporter-config.yaml /opt/jmx_exporter/jmx-exporter-config.yaml
RUN wget -O /opt/jmx_exporter/jmx_prometheus_javaagent-0.17.2.jar https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/0.17.2/jmx_prometheus_javaagent-0.17.2.jar
ENV EXTRA_ARGS="$EXTRA_ARGS -javaagent:/opt/jmx_exporter/jmx_prometheus_javaagent-0.17.2.jar=56790:/opt/jmx_exporter/jmx-exporter-config.yaml"
ENV KAFKA_JMX_OPTS="-Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Djava.rmi.server.hostname=127.0.0.1"

# Placing the Cruise Control metric reporter jar into the /opt/kafka/libs/ directory of every Kafka broker
# allows Kafka to find the reporter at runtime
COPY --from=cruise_control /tmp/cruise-control/cruise-control-metrics-reporter/build/libs/* /opt/kafka/libs/

RUN ["chmod", "+x", "/opt/kafka/config/entrypoint.sh"]

WORKDIR $HOME
EXPOSE 9092 9093 29092

ENTRYPOINT ["/opt/kafka/config/entrypoint.sh"]