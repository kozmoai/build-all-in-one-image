#
# build kozmo-builder-backend & kozmo-builder-backend-ws
#

FROM --platform=$BUILDPLATFORM golang:1.20-bullseye as kozmo-builder-backend

## set env
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG TARGETARCH
ENV GO111MODULE=on \
    CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=${TARGETARCH}

## build
WORKDIR /opt/kozmo/kozmo-builder-backend
RUN cd  /opt/kozmo/kozmo-builder-backend
RUN ls -alh

ARG BE=main
RUN git clone -b ${BE} https://github.com/kozmoai/builder-backend.git ./

RUN cat ./Makefile

RUN make all

RUN ls -alh ./bin/*



#
# build kozmo-supervisor-backend & kozmo-supervisor-backend-internal
#

FROM --platform=$BUILDPLATFORM golang:1.20-bullseye as kozmo-supervisor-backend

## set env
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG TARGETARCH

ENV GO111MODULE=on \
    CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=${TARGETARCH}

## build
WORKDIR /opt/kozmo/kozmo-supervisor-backend
RUN cd  /opt/kozmo/kozmo-supervisor-backend
RUN ls -alh

ARG SBE=main
RUN git clone -b ${SBE} https://github.com/kozmoai/kozmo-supervisor-backend.git ./

RUN cat ./Makefile

RUN make all

RUN ls -alh ./bin/*


#
# build redis
#
FROM redis:6.2.7 as cache-redis

RUN ls -alh /usr/local/bin/redis*


#
# build minio
#
FROM minio/minio:edge as drive-minio

RUN ls -alh /opt/bin/minio

#
# build nginx
#
FROM nginx:1.24-bullseye as webserver-nginx

RUN ls -alh /usr/sbin/nginx; ls -alh /usr/lib/nginx; ls -alh /etc/nginx; ls -alh /usr/share/nginx;

#
# build envoy
#
FROM envoyproxy/envoy:v1.18.2 as ingress-envoy

RUN ls -alh /etc/envoy

RUN ls -alh /usr/local/bin/envoy*
RUN ls -alh /usr/local/bin/su-exec
RUN ls -alh /etc/envoy/envoy.yaml
RUN ls -alh  /docker-entrypoint.sh


#
# Assembly all-in-one image
#
FROM postgres:14.5-bullseye as runner


#
# init environment & install required debug & runtime tools
#
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    netbase \
    wget \
    telnet \
    gnupg \
    dirmngr \
    dumb-init \
    procps \
    gettext-base \
    ; \
    rm -rf /var/lib/apt/lists/*




#
# init working folder and users
#
RUN mkdir /opt/kozmo
RUN addgroup --system --gid 102 nginx \
    && adduser --system --disabled-login --ingroup nginx --no-create-home --home /nonexistent --gecos "nginx user" --shell /bin/false --uid 102 nginx \
    && adduser --group --system envoy \
    && adduser --group --system minio \
    && adduser --group --system redis \
    && adduser --group --system kozmo \
    && cat /etc/group

#
# copy kozmo-builder-backend bin
#
COPY --from=kozmo-builder-backend /opt/kozmo/kozmo-builder-backend /opt/kozmo/kozmo-builder-backend

#
# copy kozmo-supervisor-backend bin
#
COPY --from=kozmo-supervisor-backend /opt/kozmo/kozmo-supervisor-backend /opt/kozmo/kozmo-supervisor-backend

#
# copy kozmo-builder-frontend
#
COPY ./builder /opt/kozmo/kozmo-builder-frontend
COPY ./cloud /opt/kozmo/kozmoai-frontend



#
# copy gosu
#

RUN gosu --version; \
	gosu nobody true

#
# copy redis
#
RUN mkdir -p /opt/kozmo/cache-data/; \
    mkdir -p /opt/kozmo/redis/; \
    chown -fR redis:redis /opt/kozmo/cache-data/; \
    chown -fR redis:redis /opt/kozmo/redis/;


COPY --from=cache-redis /usr/local/bin/redis-benchmark /usr/local/bin/redis-benchmark
COPY --from=cache-redis /usr/local/bin/redis-check-aof /usr/local/bin/redis-check-aof
COPY --from=cache-redis /usr/local/bin/redis-check-rdb /usr/local/bin/redis-check-rdb
COPY --from=cache-redis /usr/local/bin/redis-cli       /usr/local/bin/redis-cli
COPY --from=cache-redis /usr/local/bin/redis-sentinel  /usr/local/bin/redis-sentinel
COPY --from=cache-redis /usr/local/bin/redis-server    /usr/local/bin/redis-server

COPY scripts/redis-entrypoint.sh    /opt/kozmo/redis
RUN chmod +x /opt/kozmo/redis/redis-entrypoint.sh


#
# copy minio
#
RUN mkdir -p /opt/kozmo/drive/; \
    mkdir -p /opt/kozmo/minio/; \
    chown -fR minio:minio /opt/kozmo/drive/; \
    chown -fR minio:minio /opt/kozmo/minio/;


COPY --from=drive-minio /opt/bin/minio /usr/local/bin/minio

COPY scripts/minio-entrypoint.sh /opt/kozmo/minio
RUN chmod +x /opt/kozmo/minio/minio-entrypoint.sh


#
# copy nginx
#
RUN mkdir /opt/kozmo/nginx

COPY --from=webserver-nginx /usr/sbin/nginx  /usr/sbin/nginx
COPY --from=webserver-nginx /usr/lib/nginx   /usr/lib/nginx
COPY --from=webserver-nginx /etc/nginx       /etc/nginx
COPY --from=webserver-nginx /usr/share/nginx /usr/share/nginx

COPY config/nginx/nginx.conf /etc/nginx/nginx.conf
COPY config/nginx/kozmo-builder-frontend.conf /etc/nginx/conf.d/
COPY config/nginx/kozmoai-frontend.conf /etc/nginx/conf.d/
COPY scripts/nginx-entrypoint.sh /opt/kozmo/nginx

RUN set -x \
    && mkdir /var/log/nginx/ \
    && chmod 0777 /var/log/nginx/ \
    && mkdir /var/cache/nginx/ \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log \
    && touch /tmp/nginx.pid \
    && chmod 0777 /tmp/nginx.pid \
    && rm /etc/nginx/conf.d/default.conf \
    && chmod +x /opt/kozmo/nginx/nginx-entrypoint.sh \
    && chown -R $UID:0 /var/cache/nginx \
    && chmod -R g+w /var/cache/nginx \
    && chown -R $UID:0 /etc/nginx \
    && chmod -R g+w /etc/nginx

RUN nginx -t


#
# copy envoy
#
ENV ENVOY_UID 0 # set to root for envoy listing on 80 prot
ENV ENVOY_GID 0

RUN mkdir -p /opt/kozmo/envoy \
    && mkdir -p /etc/envoy

COPY --from=ingress-envoy  /usr/local/bin/envoy* /usr/local/bin/
COPY --from=ingress-envoy  /usr/local/bin/su-exec  /usr/local/bin/
COPY --from=ingress-envoy  /etc/envoy/envoy.yaml  /etc/envoy/

COPY config/envoy/kozmo-unit-ingress.yaml /opt/kozmo/envoy
COPY scripts/envoy-entrypoint.sh /opt/kozmo/envoy

RUN chmod +x /opt/kozmo/envoy/envoy-entrypoint.sh \
    && ls -alh /usr/local/bin/envoy* \
    && ls -alh /usr/local/bin/su-exec \
    && ls -alh /etc/envoy/envoy.yaml


#
# init database
#
RUN mkdir -p /opt/kozmo/database/ \
    && mkdir -p /opt/kozmo/postgres/

COPY scripts/postgres-entrypoint.sh  /opt/kozmo/postgres
COPY scripts/postgres-init.sh /opt/kozmo/postgres
RUN chmod +x /opt/kozmo/postgres/postgres-entrypoint.sh \
    && chmod +x /opt/kozmo/postgres/postgres-init.sh


#
# add main scripts
#
COPY scripts/main.sh /opt/kozmo/
COPY scripts/pre-init.sh /opt/kozmo/
COPY scripts/post-init.sh /opt/kozmo/
RUN chmod +x /opt/kozmo/main.sh
RUN chmod +x /opt/kozmo/pre-init.sh
RUN chmod +x /opt/kozmo/post-init.sh

#
# modify global permission
#
COPY config/system/group /opt/kozmo/
RUN cat /opt/kozmo/group > /etc/group; rm /opt/kozmo/group
RUN chown -fR kozmo:root /opt/kozmo
RUN chmod 775 -fR /opt/kozmo

#
# run
#
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
EXPOSE 2022
CMD ["/opt/kozmo/main.sh"]