FROM openjdk:11-jre-buster

ARG KAFKA_VERSION=3.3.2
ENV KAFKA_VERSION=${KAFKA_VERSION}
ENV SCALA_VERSION=2.13
ENV HOME=/opt/kafka
ENV PATH=${PATH}:${HOME}/bin

LABEL name="kafka" version=${KAFKA_VERSION}
LABEL org.opencontainers.image.source https://github.com/kubedb/kafka-docker


# ref: https://archive.apache.org/dist/kafka contains all the kafka version binary
# ref: https://github.com/edenhill/kcat used for installing kafkacat cli
RUN apt-get update \
 && apt-get install -y wget sudo \
 && apt-get -y install kafkacat \
 && wget -O /tmp/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz \
 && tar xfz /tmp/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz -C /opt \
 && rm /tmp/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz \
 && mv /opt/kafka_${SCALA_VERSION}-${KAFKA_VERSION} ${HOME} \
 && rm -rf /opt/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz

COPY scripts/entrypoint.sh /opt/kafka/config
COPY scripts/merge_custom_config.sh /opt/kafka/config
COPY ./kafka_server_jaas.conf /opt/kafka/config
# Add Prometheus JMX exporter agent
COPY ./jmx-exporter-config.yaml /opt/jmx_exporter/jmx-exporter-config.yaml
RUN wget -O /opt/jmx_exporter/jmx_prometheus_javaagent-0.17.2.jar https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/0.17.2/jmx_prometheus_javaagent-0.17.2.jar
ENV EXTRA_ARGS="$EXTRA_ARGS -javaagent:/opt/jmx_exporter/jmx_prometheus_javaagent-0.17.2.jar=56790:/opt/jmx_exporter/jmx-exporter-config.yaml"
ENV KAFKA_JMX_OPTS="-Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Djava.rmi.server.hostname=127.0.0.1"

# temporarily make kafka a sudo user
RUN echo "kafka ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
# use kafka non-root user with uid 1001
RUN groupadd -r -g 1001 kafka && \
    useradd -m -d $HOME -s /bin/bash -u 1001 -r -g kafka kafka && \
    chown -R kafka:kafka $HOME

USER kafka

RUN ["chmod", "+x", "/opt/kafka/config/entrypoint.sh"]
RUN ["chmod", "+x", "/opt/kafka/config/merge_custom_config.sh"]

WORKDIR $HOME
EXPOSE 9092 9093 29092

ENTRYPOINT ["/opt/kafka/config/entrypoint.sh"]