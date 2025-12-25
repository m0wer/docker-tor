ARG VERSION=0.4.8.21
ARG TOR_TARBALL_SHA256=eaf6f5b73091b95576945eade98816ddff7cd005befe4d94718a6f766b840903

ARG USER=toruser
ARG UID=1000

ARG DIR=/data

FROM debian:12-slim as preparer-base

RUN apt update
RUN apt -y install gpg gpg-agent curl

# Add tor key
# Grabbed from https://gitlab.torproject.org/tpo/core/tor/-/blob/main/README.md#keys-that-can-sign-a-release
ENV KEYS 514102454D0A87DB0767A1EBBE6A0531C18A9179 B74417EDDF22AC9F9E90F49142E86A2A11F48D36 2133BC600AB133E1D826D173FE43009C4607B1FB

#RUN curl -s https://openpgpkey.torproject.org/.well-known/openpgpkey/torproject.org/hu/kounek7zrdx745qydx6p59t9mqjpuhdf |gpg --import -
RUN gpg --keyserver keys.openpgp.org --recv-keys $KEYS 

RUN gpg --list-keys | tail -n +3 | tee /tmp/keys.txt && \
    gpg --list-keys $KEYS | diff - /tmp/keys.txt

FROM preparer-base AS preparer-release

ARG VERSION
ARG TOR_TARBALL_SHA256

ADD https://dist.torproject.org/tor-$VERSION.tar.gz.sha256sum.asc ./
ADD https://dist.torproject.org/tor-$VERSION.tar.gz.sha256sum ./
ADD --checksum="sha256:$TOR_TARBALL_SHA256" \
    https://dist.torproject.org/tor-$VERSION.tar.gz \
    ./

RUN gpg --verify tor-$VERSION.tar.gz.sha256sum.asc
RUN sha256sum -c tor-$VERSION.tar.gz.sha256sum
# Extract
RUN tar -xzf "/tor-$VERSION.tar.gz" && \
    rm  -f   "/tor-$VERSION.tar.gz"

FROM preparer-release AS preparer

FROM debian:12-slim as builder

ARG VERSION

RUN apt update
RUN apt -y install libevent-dev libssl-dev zlib1g-dev build-essential

WORKDIR /tor-$VERSION/

COPY  --from=preparer /tor-$VERSION/  ./

RUN ./configure --sysconfdir=/etc --datadir=/var/lib
RUN make -j$(nproc)
RUN make install

RUN ls -la /etc
RUN ls -la /etc/tor
RUN ls -la /var/lib
RUN ls -la /var/lib/tor

FROM debian:12-slim as final

ARG VERSION
ARG USER
ARG DIR

LABEL maintainer="nolim1t (@nolim1t)"

# Libraries (linked)
COPY  --from=builder /usr/lib /usr/lib
# Copy all the TOR files
COPY  --from=builder /usr/local/bin/tor*  /usr/local/bin/

# NOTE: Default GID == UID == 1000
RUN adduser --disabled-password \
            --home "$DIR/" \
            --gecos "" \
            "$USER"

# Copy default torrc configuration
RUN mkdir -p /etc/tor && \
    chown "$USER":"$USER" /etc/tor
COPY  --chown=$USER:$USER torrc-dist /etc/tor/torrc

USER $USER

VOLUME /etc/tor
VOLUME /var/lib/tor

EXPOSE 9050 9051 29050 29051

ENTRYPOINT ["tor"]
