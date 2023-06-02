# Multi-stage build requires Docker 17.05 or higher
# --------------- Builder stage ---------------
FROM gradle:jdk11 AS cruise_control

ENV CC_VERSION=2.5.42
ENV CCUI_VERSION=0.4.0

# Fetch Cruise-Control binary
# https://github.com/linkedin/cruise-control/releases contains all the kafka release binary
RUN set -eux \
    && apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends ca-certificates wget \
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

# Compile and remove leftover directories \
RUN set -eux \
	&& ./gradlew --console=plain --no-daemon -i clean \
    && ./gradlew --console=plain --no-daemon -i jar :cruise-control:jar  \
    && rm -rf cruise-control-core cruise-control-metrics-reporter cruise-control-client


# Configure Cruise Control to point to the proper Kafka and Zookeeper endpoints
RUN sed -i 's/bootstrap.servers=.*/bootstrap.servers=my-cluster-kafka-bootstrap:9092/g' config/cruisecontrol.properties \
    && sed -i 's/capacity.config.file=.*/capacity.config.file=config\/capacityJBOD.json/g' config/cruisecontrol.properties \
    && sed -i 's/sample.store.topic.replication.factor=.*/sample.store.topic.replication.factor=1/g' config/cruisecontrol.properties

# Install Cruise Control GUI Frontend
RUN set -eux \
    && wget -O /opt/ccui.tar.gz https://github.com/linkedin/cruise-control-ui/archive/refs/tags/v${CCUI_VERSION}.tar.gz

# Extract
RUN set -eux \
	&& cd /opt \
	&& tar xzvf ccui.tar.gz \
	&& mv /opt/cruise-control-ui-* /opt/cruise-control/cruise-control-ui/ \
    && rm ccui.tar.gz

RUN cd cruise-control-ui/static \
    && cat config.csv

ENTRYPOINT ["/bin/bash", "-c", "./kafka-cruise-control-start.sh config/cruisecontrol.properties"]

# --------------- Final stage ---------------
FROM centos:7
WORKDIR cruise-control

RUN yum -y install java-11-openjdk-devel && \
    yum clean all -y

COPY --from=cruise_control /opt/cruise-control .

# Ensure Cruise Control writable for logs
RUN chmod a+rw -R .

ENTRYPOINT ["/bin/bash", "-c", "./kafka-cruise-control-start.sh config/cruisecontrol.properties"]