# --------------- Builder stage ---------------
FROM eclipse-temurin:17.0.7_7-jdk AS cruisecontrol

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

# Build
RUN set -eux \
    && ./gradlew clean \
    && ./gradlew jar \
    && ./gradlew jar copyDependantLibs


FROM node:20.3.1-buster as cruisecontrol_ui

ARG CCUI_VERSION

# Fetch Cruise-Control-UI binary
# https://github.com/linkedin/cruise-control-ui/releases contains all the kafka release binary
RUN set -eux \
    && wget -O /opt/ccui.tar.gz https://github.com/linkedin/cruise-control-ui/archive/refs/tags/v${CCUI_VERSION}.tar.gz

# Extract
RUN set -eux \
	&& cd /opt \
	&& tar xzvf ccui.tar.gz \
	&& mv /opt/cruise-control-ui-* /opt/cruise-control-ui \
    && rm ccui.tar.gz

# Build
RUN set -eux \
    && cd /opt/cruise-control-ui \
    && npm install \
    && npm run build

# --------------- Final stage ---------------
FROM centos:7
WORKDIR /opt/cruise-control

RUN yum -y install java-11-openjdk-devel && \
    yum clean all -y

COPY --from=cruisecontrol    /opt/cruise-control /opt/cruise-control
COPY --from=cruisecontrol_ui /opt/cruise-control-ui /opt/cruise-control/cruise-control-ui

COPY /scripts/entrypoint.sh /opt/cruise-control/config/entrypoint.sh
COPY /scripts/merge_custom_config.sh /opt/cruise-control/config/merge_custom_config.sh
COPY ./kafka_server_jaas.conf /opt/cruise-control/config

#COPY /scripts/cruisecontrol.properties /opt/cruise-control/config/cruisecontrol.properties

# Ensure Cruise Control writable for logs
RUN chmod a+rw -R .

RUN ["chmod", "+x", "/opt/cruise-control/config/entrypoint.sh"]
RUN ["chmod", "+x", "/opt/cruise-control/config/merge_custom_config.sh"]

ENTRYPOINT ["/opt/cruise-control/config/entrypoint.sh"]
EXPOSE 9090