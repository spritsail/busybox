repo = "spritsail/busybox"
architectures = ["amd64", "arm64"]
branches = ["master"]

def main(ctx):
  builds = []
  depends_on = []

  for arch in architectures:
    key = "build-%s" % arch
    builds.append(step(arch, key))
    depends_on.append(key)
  if ctx.build.branch in branches:
    builds.append(publish(depends_on))

  return builds

def step(arch, key):
  return {
    "kind": "pipeline",
    "name": key,
    "platform": {
      "os": "linux",
      "arch": arch,
    },
    "steps": [
      {
        "name": "build",
        "pull": "always",
        "image": "spritsail/docker-build",
      },
      {
        "name": "test",
        "pull": "never",
        "image": "drone/${DRONE_REPO}/${DRONE_BUILD_NUMBER}:${DRONE_STAGE_OS}-${DRONE_STAGE_ARCH}",
        "commands": [
          "true",
          "test -f /lib/libc.so.6",
          "ldconfig -p",
          "nslookup google.com",
          "test \"$(date +%Z)\" = 'UTC'",
          "test \"$(echo This is a test string | md5sum | cut -f1 -d' ' | tee /dev/stderr)\" = 'b584c39f97dfe71ebceea3fdb860ed6c'"
        ],
      },
      {
        "name": "publish",
        "pull": "always",
        "image": "spritsail/docker-publish",
        "settings": {
          "registry": {"from_secret": "registry_url"},
          "login": {"from_secret": "registry_login"},
        },
        "when": {
          "branch": branches,
          "event": ["push"],
        },
      },
    ],
  }

def publish(depends_on):
  return {
    "kind": "pipeline",
    "name": "publish-manifest",
    "depends_on": depends_on,
    "platform": {
      "os": "linux",
    },
    "steps": [
      {
        "name": "publish",
        "image": "spritsail/docker-multiarch-publish",
        "pull": "always",
        "settings": {
          "tags": [
            "latest",
            "%label io.spritsail.version.busybox"
          ],
          "src_registry": {"from_secret": "registry_url"},
          "src_login": {"from_secret": "registry_login"},
          "dest_repo": repo,
          "dest_login": {"from_secret": "docker_login"},
        },
        "when": {
          "branch": branches,
          "event": ["push"],
        },
      },
    ],
  }

# vim: ft=python sw=2
