FROM tomcat:9-jdk11-temurin

ARG VIVO_TDB_FILE_MODE=direct
ARG VIVO_CONTAINER_VIVO_HOME=/usr/local/vivo/home
ARG VIVO_ARTIFACTS=/opt/vivo/artifacts
ARG VIVO_CONTAINER_PORT=8080

ENV VIVO_TDB_FILE_MODE=${VIVO_TDB_FILE_MODE}
ENV VIVO_CONTAINER_VIVO_HOME=${VIVO_CONTAINER_VIVO_HOME}
ENV VIVO_ARTIFACTS=${VIVO_ARTIFACTS}
ENV VIVO_CONTAINER_PORT=${VIVO_CONTAINER_PORT}

ENV JAVA_OPTS="${JAVA_OPTS} -Dtdb:fileMode=${VIVO_TDB_FILE_MODE}"

RUN mkdir -p "${VIVO_CONTAINER_VIVO_HOME}"
RUN mkdir -p "${VIVO_ARTIFACTS}"

VOLUME ${VIVO_CONTAINER_VIVO_HOME}

# Copy VIVO configuration templates into the image and deploy the WAR at the default ROOT context
# CATALINA_HOME is provided by the tomcat base image (/usr/local/tomcat)
COPY ./home/src/main/resources/config "${VIVO_ARTIFACTS}/config"
COPY ./installer/webapp/target/vivo.war "${CATALINA_HOME}/webapps/ROOT.war"

COPY --chmod=755 start.sh /start.sh

# This does not publish the port. Use `docker run -p 8080:8080` to publish it.
EXPOSE ${VIVO_CONTAINER_PORT}

CMD ["/bin/bash", "/start.sh"]
