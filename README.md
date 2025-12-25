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

For more advanced configurations (hidden services, custom settings, etc.), mount your own `torrc` configuration file and any necessary data directories:

```bash
docker run -d \
  --name tor \
  -v $PWD/torrc:/etc/tor/torrc \
  -v $PWD/data:/var/lib/tor \
  ghcr.io/m0wer/docker-tor:latest
```

For hidden services, you'll need to mount `/var/lib/tor` to persist your hidden service keys. 

### Docker Compose

For convenience, a [docker-compose.yml-dist](docker-compose.yml-dist) file is available:

```bash
docker compose -f docker-compose.yml-dist up
```

### Configuration Examples

See [torrc-dist](torrc-dist) for a sample configuration file with hidden services and control port examples.

For a full configuration reference, see the [official Tor configuration documentation](https://github.com/torproject/tor/blob/main/src/config/torrc.sample.in).

### Generating Tor Passwords

To generate a hashed password for the control port:

```bash
docker run --rm ghcr.io/m0wer/docker-tor:latest --hash-password mypassword
```

## Building

To update to a new Tor version:

1. Check [dist.torproject.org](https://dist.torproject.org/?C=M;O=D) for the latest non-alpha release
2. Update `VERSION` and `TOR_TARBALL_SHA256` in the Dockerfile
3. Tag and push to trigger the build:

```bash
git tag 0.4.8.21
git push origin 0.4.8.21
```

