#!/usr/bin/env python3
import json
import re
import subprocess
import urllib.request
from pathlib import Path

PACKAGE_FILE = Path("modules/packages/kunai.nix")
REPOSITORY = "KitsuneKode/kunai"
API = f"https://api.github.com/repos/{REPOSITORY}"
ARCHES = ("x64", "arm64")


def github_json(url):
    request = urllib.request.Request(
        url,
        headers={"Accept": "application/vnd.github+json", "User-Agent": "lumina-package-updater"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def github_text(url):
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


def source_hash(revision):
    url = f"https://github.com/{REPOSITORY}/archive/{revision}.tar.gz"
    base32_hash = run(["nix-prefetch-url", "--unpack", "--type", "sha256", url])
    return run(["nix", "hash", "to-sri", "--type", "sha256", base32_hash])


def workspace_hash():
    content = PACKAGE_FILE.read_text()
    content = replace_once(
        r'outputHash = (?:lib\.fakeHash|"[^"]+");',
        "outputHash = lib.fakeHash;",
        content,
        "workspace output hash",
    )
    PACKAGE_FILE.write_text(content)
    result = subprocess.run(
        ["nix", "build", ".#packages.x86_64-linux.kunai-latest.passthru.workspace", "--no-link"],
        text=True,
        capture_output=True,
    )
    output = result.stdout + "\n" + result.stderr
    match = re.search(r"got:\s*(sha256-[A-Za-z0-9+/=]+)", output)
    if not match:
        raise RuntimeError(f"Unable to calculate Bun workspace hash (exit {result.returncode}):\n{output}")
    return match.group(1)


def main():
    content = PACKAGE_FILE.read_text()
    release = github_json(f"{API}/releases/latest")
    if release.get("prerelease"):
        raise RuntimeError("GitHub latest release unexpectedly points to a prerelease")

    tag = release["tag_name"]
    release_version = tag.removeprefix("v")
    assets = {asset["name"] for asset in release.get("assets", [])}
    revision = github_json(f"{API}/commits/main")["sha"]
    manifest = json.loads(github_text(
        f"https://raw.githubusercontent.com/{REPOSITORY}/{revision}/apps/cli/package.json"
    ))
    source_version = manifest["version"]

    old_release = re.search(r'(?m)^\s*version = "([^"]+)";', content).group(1)
    old_source_version = re.search(r'(?m)^\s*latestVersion = "([^"]+)";', content).group(1)
    old_revision = re.search(r'(?m)^\s*rev = "([0-9a-f]+)";', content).group(1)

    def version_tuple(value):
        return tuple(int(part) for part in value.split("."))

    if version_tuple(release_version) < version_tuple(old_release):
        release_version = old_release
        tag = f"v{old_release}"

    content = replace_once(
        r'(?m)^(\s*version = ")[^"]+(";\s*)$',
        rf'\g<1>{release_version}\g<2>', content, "stable version"
    ) if old_release != release_version else content
    content = replace_once(
        r'(?m)^(\s*latestVersion = ")[^"]+(";\s*)$',
        rf'\g<1>{source_version}\g<2>', content, "latest source version"
    ) if old_source_version != source_version else content
    content = replace_once(
        r'(?m)^(\s*rev = ")[^"]+(";\s*)$',
        rf'\g<1>{revision}\g<2>', content, "latest source revision"
    ) if old_revision != revision else content
    PACKAGE_FILE.write_text(content)

    stable_block = content.split("stableHashes = {", 1)[1].split("};", 1)[0]
    hashes = {}
    for arch in ARCHES:
        current_hash = re.search(
            rf'(?m)^\s*{arch} = (lib\.fakeHash|"[^"]+");', stable_block
        ).group(1)
        if old_release != release_version or current_hash == "lib.fakeHash":
            asset = f"kunai-linux-{arch}.tar.gz"
            if asset not in assets:
                raise RuntimeError(f"Release {tag} is missing asset {asset}")
            hashes[arch] = release_hash(
                f"https://github.com/{REPOSITORY}/releases/download/{tag}/{asset}"
            )
        else:
            hashes[arch] = current_hash.strip('"')

    block = (
        "stableHashes = {\n"
        f'      x64 = "{hashes["x64"]}";\n'
        f'      arm64 = "{hashes["arm64"]}";\n'
        "    };"
    )
    content = PACKAGE_FILE.read_text()
    PACKAGE_FILE.write_text(replace_once(
        r"stableHashes = \{.*?\};", block, content, "stable architecture hashes", re.S
    ))

    source_match = re.search(
        r'(source = pkgs\.fetchFromGitHub \{.*?\n\s*hash = )(lib\.fakeHash|"[^"]+")(;\s*\n\s*\};)',
        PACKAGE_FILE.read_text(),
        re.S,
    )
    source_hash_missing = source_match is None or source_match.group(2) == "lib.fakeHash"
    if old_revision != revision or old_source_version != source_version or source_hash_missing:
        digest = source_hash(revision)
        content = PACKAGE_FILE.read_text()
        content = replace_once(
            r'(source = pkgs\.fetchFromGitHub \{.*?\n\s*hash = )(?:lib\.fakeHash|"[^"]+")(;\s*\n\s*\};)',
            rf'\g<1>"{digest}"\g<2>', content, "latest source hash", re.S
        )
        PACKAGE_FILE.write_text(content)

    content = PACKAGE_FILE.read_text()
    source_match = re.search(
        r'(source = pkgs\.fetchFromGitHub \{.*?\n\s*hash = )(lib\.fakeHash|"[^"]+")(;\s*\n\s*\};)',
        content,
        re.S,
    )
    if source_match is None or source_match.group(2) == "lib.fakeHash":
        raise RuntimeError("Latest source hash is still a placeholder; refusing workspace hash calculation")

    workspace_match = re.search(r'outputHash = (lib\.fakeHash|"[^"]+");', content)
    workspace_hash_missing = workspace_match is None or workspace_match.group(1) == "lib.fakeHash"
    if old_revision != revision or old_source_version != source_version or source_hash_missing or workspace_hash_missing:
        digest = workspace_hash()
        content = PACKAGE_FILE.read_text()
        content = replace_once(
            r'outputHash = (?:lib\.fakeHash|"[^"]+");',
            f'outputHash = "{digest}";', content, "workspace output hash"
        )
        PACKAGE_FILE.write_text(content)

    print(f"Kunai stable: v{release_version}; development source: {revision[:12]} ({source_version})")


if __name__ == "__main__":
    main()
