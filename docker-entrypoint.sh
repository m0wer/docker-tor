#!/bin/bash
set -euo pipefail

# Fix permissions on /var/lib/tor and its contents so Tor can read/write
# hidden service keys when running as an unprivileged user.
#
# Tor enforces strict permission checks:
#   - HiddenServiceDir must be mode 0700
#   - Key files must be mode 0600
#   - All must be owned by the running user

fix_permissions() {
    local dir="$1"

    if [ ! -d "$dir" ]; then
        return
    fi

    # Fix directory permissions: Tor requires 0700 on data dirs
    if [ -w "$dir" ]; then
        chmod 700 "$dir" 2>/dev/null || true
    fi

    # Fix subdirectory permissions (hidden service dirs)
    find "$dir" -mindepth 1 -maxdepth 1 -type d -writable 2>/dev/null | while read -r subdir; do
        chmod 700 "$subdir" 2>/dev/null || true
        # Fix key file permissions inside hidden service dirs
        find "$subdir" -maxdepth 1 -type f -writable 2>/dev/null | while read -r file; do
            chmod 600 "$file" 2>/dev/null || true
        done
    done

    # Fix key/data file permissions directly in the data dir
    find "$dir" -maxdepth 1 -type f -writable 2>/dev/null | while read -r file; do
        chmod 600 "$file" 2>/dev/null || true
    done
}

fix_permissions /var/lib/tor

exec "$@"
