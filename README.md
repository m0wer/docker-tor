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
docker run -d --name tor -p 9050:9050 ghcr.io/m0wer/docker-tor:latest
```

This allows you to use Tor as a proxy for your applications.

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

Make sure the mounted `/var/lib/tor` directory is writable by the container user (UID 1000). 

### Docker Compose

For convenience, a [docker-compose.yml-dist](docker-compose.yml-dist) file is available:

```bash
docker compose -f docker-compose.yml-dist up
```

### Configuration Examples

The default [torrc-dist](torrc-dist) configuration provides a minimal SOCKS proxy setup. It includes commented examples for:
- Control port with cookie authentication
- Hidden services (SSH, Bitcoin P2P)

**Note**: Both control port (with cookie auth) and hidden services require mounting `/var/lib/tor` as shown in the Advanced Usage section above.

For a full configuration reference, see the [official Tor configuration documentation](https://github.com/torproject/tor/blob/main/src/config/torrc.sample.in).

### Using the Control Port

If you enable the control port with cookie authentication, you can interact with Tor using tools like `nyx` or libraries that support the Tor control protocol. The authentication cookie will be stored in `/var/lib/tor/control_auth_cookie`.

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

