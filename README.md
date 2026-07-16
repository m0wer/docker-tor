# Tor as a Docker container

Tor service as a docker container, supporting multiple platforms/architectures (amd64, arm64).

## Goal

This project provides Docker images for the latest non-alpha Tor release from [https://dist.torproject.org/](https://dist.torproject.org/?C=M;O=D).

## Tags

* `latest` - Latest tagged release
* `master` - Latest commit on master branch
* Version tags (e.g., `0.4.8.21`) - Specific Tor versions

## Usage

### Default Configuration (SOCKS Proxy)

By default, when run without a mounted configuration, the container listens on all interfaces on port 9050 as a SOCKS proxy:

```bash
docker run -d --name tor -p 127.0.0.1:9050:9050 ghcr.io/m0wer/docker-tor:latest
```

This allows local applications to use Tor as a proxy. Do not publish SOCKS on
all host interfaces unless remote clients intentionally need access; the SOCKS
protocol is not an access-control boundary by itself.

### Advanced Usage

For more advanced configurations (control port, custom settings, etc.), mount your own `torrc` configuration file:

```bash
docker run -d \
  --name tor \
  -v $PWD/torrc:/etc/tor/torrc \
  ghcr.io/m0wer/docker-tor:latest
```

**For hidden services**, you must mount `/var/lib/tor` to persist your hidden service keys and allow Tor to create the necessary directories:

```bash
docker run -d \
  --name tor \
  -v $PWD/torrc:/etc/tor/torrc \
  -v $PWD/data:/var/lib/tor \
  ghcr.io/m0wer/docker-tor:latest
```

The entrypoint automatically fixes directory and file permissions (`0700` for
directories, `0600` for files) inside `/var/lib/tor` so that Tor's strict
permission checks pass. The mounted host directory and any pre-existing key
files **must be owned by the UID the container runs as** (default `1000`).

When running with a custom `user:` in Docker Compose or `--user` on the CLI,
make sure the host directory ownership matches:

```bash
# Example: prepare a hidden service data directory for UID 1000
mkdir -p ./tor-data
chown -R 1000:1000 ./tor-data
chmod 700 ./tor-data
```

### Disabling the SOCKS Proxy and Control Port

If you are only running hidden services and do not need SOCKS proxy or control
port access, disable them in your `torrc` for a smaller attack surface:

```
SocksPort 0
ControlPort 0
```

### Docker Compose

For convenience, a [docker-compose.yml-dist](docker-compose.yml-dist) file is available:

```bash
docker compose -f docker-compose.yml-dist up
```

### Hardened Docker Compose

For an application that must not have direct Internet access, put the
application and Tor on an internal network and attach only Tor to a separate
egress network. The application can then reach `tor:9050`, but a missed proxy
configuration cannot silently fall back to clearnet. Keep `tor-egress`
dedicated to this Tor container.

```yaml
services:
  tor:
    image: ghcr.io/m0wer/docker-tor:0.4.9.11
    restart: unless-stopped
    user: "1000:1000"
    command:
      - tor
      - --ignore-missing-torrc
      - -f
      - /nonexistent
      - --SocksPort
      - "0.0.0.0:9050 IsolateSOCKSAuth"
      - --DataDirectory
      - /var/lib/tor
      - --ClientOnly
      - "1"
      - --NoExec
      - "1"
      - --SafeLogging
      - "1"
      - --Log
      - notice stdout
    volumes:
      - tor-data:/var/lib/tor
    networks:
      - tor-internal
      - tor-egress
    healthcheck:
      test: ["CMD", "bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/9050"]
      interval: 10s
      timeout: 3s
      retries: 30
      start_period: 20s
    read_only: true
    tmpfs:
      - /tmp:rw,noexec,nosuid,nodev,size=16m,mode=1777
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    pids_limit: 128
    logging:
      driver: local
      options:
        max-size: 10m
        max-file: "3"

  application:
    image: your-application:latest
    restart: unless-stopped
    depends_on:
      tor:
        condition: service_healthy
    networks:
      - tor-internal
    read_only: true
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL

volumes:
  tor-data:

networks:
  tor-internal:
    driver: bridge
    internal: true
  tor-egress:
    driver: bridge
```

Do not publish the SOCKS port in this topology. Configure the application to
use SOCKS5 with proxy-side hostname resolution (commonly a `socks5h` URL), and
use distinct arbitrary SOCKS credentials when multiple applications need
`IsolateSOCKSAuth` circuit separation. The health check confirms that the local
SOCKS listener is open, not that Tor has finished bootstrapping, so the
application must retry transient startup failures. Adapt its user and writable
mounts before enabling `read_only` and dropping all capabilities.

The explicit command ignores the image's default `torrc`, so a writable
anonymous `/etc/tor` volume created from the image cannot alter the effective
configuration on restart. The baseline leaves Tor's control interface disabled
and does not expose the data volume to the application. An application that
must control Tor should prefer a Unix control socket over a TCP control
listener. For example, replace the Tor command and add only the following
runtime-volume access:

```yaml
services:
  tor:
    command:
      - tor
      - --ignore-missing-torrc
      - -f
      - /nonexistent
      - --SocksPort
      - "0.0.0.0:9050 IsolateSOCKSAuth"
      - --ControlPort
      - "unix:/var/run/tor/control GroupWritable"
      - --CookieAuthentication
      - "1"
      - --CookieAuthFile
      - /var/run/tor/control_auth_cookie
      - --CookieAuthFileGroupReadable
      - "1"
      - --DataDirectory
      - /var/lib/tor
      - --ClientOnly
      - "1"
      - --NoExec
      - "1"
      - --SafeLogging
      - "1"
      - --Log
      - notice stdout
    volumes:
      - tor-data:/var/lib/tor
      - tor-control:/var/run/tor

  application:
    # Match the Tor image's default GID so the controller can read the cookie
    # and connect to the group-writable Unix socket.
    group_add:
      - "1000"
    volumes:
      - tor-control:/var/run/tor:ro

volumes:
  tor-control:
```

The controller must support the Unix Tor control protocol and SAFECOOKIE.
Possession of the cookie grants full control over Tor, so do not share this
volume with non-controller containers. Avoid a remotely reachable TCP control
listener; SAFECOOKIE authenticates clients but does not encrypt control traffic.

The image user's home is `/data`, and Tor otherwise defaults its data directory
to `/data/.tor`. This example explicitly uses `/var/lib/tor`, so the home can
remain read-only and all Tor state is stored in the named data volume.

For a host-managed configuration, remove `command:` and use bind mounts instead:

```yaml
    volumes:
      - ./tor/conf:/etc/tor:ro
      - ./tor/data:/var/lib/tor
      # Mount a runtime directory only when the torrc uses one.
      - ./tor/run:/var/run/tor
```

Create those directories before startup, set ownership to `1000:1000`, and set
mode `0700` on the data directory. Keep `/etc/tor` read-only and retain the
`/tmp` tmpfs mount. The custom `torrc` must set `DataDirectory /var/lib/tor`;
otherwise Tor will try to use the read-only `/data/.tor`. Set network listeners
to `0.0.0.0` only when another container must reach them, use `SafeLogging 1`,
and authenticate every control listener. If a controller creates services with
`ADD_ONION`, do not enable Tor's syscall sandbox because Tor documents that
combination as unsupported.

### Configuration Examples

The default [torrc-dist](torrc-dist) configuration provides a minimal SOCKS proxy setup. It includes commented examples for:
- Control port with cookie authentication
- Hidden services (SSH, Bitcoin P2P)

**Note**: Hidden services require mounting `/var/lib/tor`. The recommended
control configuration places its authentication cookie in `/var/run/tor`,
which should be a separate runtime mount shared only with trusted controllers.

For a full configuration reference, see the [official Tor configuration documentation](https://github.com/torproject/tor/blob/main/src/config/torrc.sample.in).

### Using the Control Port

If you enable the control port with cookie authentication, you can interact
with Tor using tools like `nyx` or libraries that support the Tor control
protocol. Set `CookieAuthFile /var/run/tor/control_auth_cookie` and mount that
runtime directory into trusted controller containers.

Tor reports `CookieAuthFile` as an absolute path in its own filesystem through
`PROTOCOLINFO`. A controller in another container must either mount the cookie
at the same absolute path or support a local cookie-path override. Sharing the
file at a different path without configuring the controller will produce a
file-not-found error even though both containers mount the same volume.

The default [torrc-dist](torrc-dist) explicitly sets
`DataDirectory /var/lib/tor`. A custom `torrc` that omits `DataDirectory` falls
back to `$HOME/.tor`; this image's home is `/data`, so that fallback is
`/data/.tor` and the default cookie becomes
`/data/.tor/control_auth_cookie`. Mounting `/var/run/tor` does not redirect it;
set both `DataDirectory` and `CookieAuthFile` explicitly.

### Generating Tor Passwords

If you prefer password authentication over cookie authentication for the control port, you can generate a hashed password:

```bash
docker run --rm ghcr.io/m0wer/docker-tor:latest --hash-password mypassword
```

Then use `HashedControlPassword` in your torrc instead of `CookieAuthentication`.

## Building

To update to a new Tor version:

1. Check [dist.torproject.org](https://dist.torproject.org/?C=M;O=D) for the latest non-alpha release
2. Update `VERSION` and `TOR_TARBALL_SHA256` in the Dockerfile
3. Tag and push to trigger the build:

```bash
git tag 0.4.8.21
git push origin 0.4.8.21
```
