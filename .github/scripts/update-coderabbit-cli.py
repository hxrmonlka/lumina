#!/usr/bin/env python3
"""Update the CodeRabbit CLI package from the official VERSION endpoint.

The version source is https://cli.coderabbit.ai/releases/latest/VERSION, so
`nix-update` cannot discover it from the archive URL. Whenever the upstream
version moves, every platform-specific archive hash is refreshed with
`nix store prefetch-file`.
"""
import json
import re
import subprocess
import urllib.request

PACKAGE_FILE = "modules/packages/coderabbit-cli.nix"
VERSION_URL = "https://cli.coderabbit.ai/releases/latest/VERSION"
# Keys match the `hashes` map in modules/packages/coderabbit-cli.nix.
ARCHES = ("linux-x64", "linux-arm64", "darwin-arm64")
RELEASE_URL = "https://cli.coderabbit.ai/releases/{version}/coderabbit-{arch}.zip"


def fetch_text(url):
    request = urllib.request.Request(url, headers={"User-Agent": "lumina-package-updater"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read().decode()


def run(args):
    return subprocess.run(args, check=True, text=True, capture_output=True).stdout.strip()


def replace_once(pattern, replacement, content, label, flags=0):
    updated, count = re.subn(pattern, replacement, content, count=1, flags=flags)
    if count != 1:
        raise RuntimeError(f"Could not locate {label} in {PACKAGE_FILE}")
    return updated


def release_hash(url):
    result = json.loads(run(["nix", "store", "prefetch-file", "--json", "--hash-type", "sha256", url]))
    return result["hash"]


def version_tuple(value):
    return tuple(int(part) for part in value.split("."))


def main():
    content = open(PACKAGE_FILE, encoding="utf-8").read()

    old_version = re.search(r'(?m)^\s*version = "([^"]+)";', content).group(1)
    new_version = fetch_text(VERSION_URL).strip()
    if not new_version:
        raise RuntimeError("VERSION endpoint returned an empty value")

    # Never downgrade: a retracted release keeps the packaged version until
    # upstream publishes a newer one.
    if version_tuple(new_version) < version_tuple(old_version):
        new_version = old_version

    hashes_block = re.search(r"hashes = \{(.*?)\};", content, re.S).group(1)
    stale_hashes = any(
        re.search(rf"(?m)^\s*{arch} = lib\.fakeHash;", hashes_block)
        for arch in ARCHES
    )

    if new_version == old_version and not stale_hashes:
        print(f"coderabbit-cli: up to date at {old_version}")
        return

    hashes = {
        arch: release_hash(RELEASE_URL.format(version=new_version, arch=arch))
        for arch in ARCHES
    }

    if new_version != old_version:
        content = replace_once(
            r'(?m)^(\s*version = ")[^"]+(";\s*)$',
            rf"\g<1>{new_version}\g<2>",
            content,
            "version",
        )

    block = "hashes = {\n" + "".join(
        f'      {arch} = "{hashes[arch]}";\n' for arch in ARCHES
    ) + "    };"
    content = replace_once(
        r"hashes = \{.*?\};", block, content, "architecture hashes", re.S
    )

    with open(PACKAGE_FILE, "w", encoding="utf-8") as handle:
        handle.write(content)

    print(f"coderabbit-cli: {old_version} -> {new_version} (hashes refreshed)")


if __name__ == "__main__":
    main()
