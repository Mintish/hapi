FROM maven:3.6.3-jdk-11 as build-hapi

ARG HAPI_FHIR_STARTER_URL=https://github.com/hapifhir/hapi-fhir-jpaserver-starter/
ARG HAPI_FHIR_STARTER_BRANCH=master

# Build HAPI_FHIR_STARTER
WORKDIR /tmp
RUN git clone --branch ${HAPI_FHIR_STARTER_BRANCH} ${HAPI_FHIR_STARTER_URL}
COPY ./tmpl-banner.html /tmp/hapi-fhir-jpaserver-starter/src/main/webapp/WEB-INF/templates/tmpl-banner.html
COPY ./smart-logo.svg   /tmp/hapi-fhir-jpaserver-starter/src/main/webapp/img/smart-logo.svg
WORKDIR /tmp/hapi-fhir-jpaserver-starter
RUN mvn clean install -DskipTests

FROM build-hapi AS build-distroless
RUN mvn package spring-boot:repackage -Pboot
RUN mkdir /app && \
    cp /tmp/hapi-fhir-jpaserver-starter/target/ROOT.war /app/main.war

FROM gcr.io/distroless/java-debian10:11 AS release-distroless
COPY --chown=nonroot:nonroot --from=build-distroless /app /app
EXPOSE 8080
# 65532 is the nonroot user's uid
# used here instead of the name to allow Kubernetes to easily detect that the container
# is running as a non-root (uid != 0) user.
USER 65532:65532
WORKDIR /app
CMD ["/app/main.war"]


FROM tomcat:9.0.38-jdk11-openjdk-buster

RUN mkdir -p /data/hapi/lucenefiles && chmod 775 /data/hapi/lucenefiles
COPY --from=build-hapi /tmp/hapi-fhir-jpaserver-starter/target/ROOT.war /usr/local/tomcat/webapps/hapi-fhir-jpaserver.war

RUN apt-get update && apt-get install gettext-base -y && apt-get install vim -y

ARG DATABASE=empty
ARG IP=127.0.0.1
ARG PORT=8080
ARG FHIR_VERSION=R4
ARG JAVA_OPTS=-Dspring.config.location=/config/application.yaml

ENV JAVA_OPTS=$JAVA_OPTS
ENV IP=$IP
ENV PORT=$PORT
ENV FHIR_VERSION=$FHIR_VERSION
ENV DATABASE=$DATABASE
ENV HOST=localhost
#ENV --spring.config.location=/config/application.yaml

COPY ./databases/${DATABASE}/ /usr/local/tomcat/target/database/
COPY ./server.xml  /tmp/server.xml

RUN mkdir /config
COPY ./application.yaml  /tmp/application.yaml.tpl

EXPOSE 8080

CMD envsubst < /tmp/application.yaml.tpl > /config/application.yaml && catalina.sh run
