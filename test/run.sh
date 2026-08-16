#!/bin/bash

# Run setup.sh end to end in a throwaway container per image, then assert the
# result. Defaults to the distributions the repo claims to support.
#
#   test/run.sh                  # debian:13 and ubuntu:24.04
#   test/run.sh ubuntu:22.04     # one image
#   KEEP=1 test/run.sh           # leave the containers around to poke at
#
# Nothing here touches the machine it runs on; every change lands in the
# container.

set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
user=tester

images=("$@")
if [ ${#images[@]} -eq 0 ]; then
  images=(debian:13 ubuntu:24.04)
fi

if ! docker info >/dev/null 2>&1; then
  echo "docker is not available" >&2
  exit 1
fi

run_in_container() {
  docker exec -u "$user" -e USER="$user" -e HOME="/home/$user" \
    -e DEBIAN_FRONTEND=noninteractive "$1" bash "/home/$user/claude-sandbox/$2"
}

failed=0

for image in "${images[@]}"; do
  container="claude-sandbox-test-$(echo "$image" | tr ':/.' '---')"
  log="$(mktemp)"

  echo "==> $image"
  docker rm -f "$container" >/dev/null 2>&1

  docker run -d --name "$container" -v "$repo:/repo:ro" "$image" sleep 7200 >/dev/null

  # A fresh VM has a sudo-capable non-root user; the base images do not.
  docker exec -e DEBIAN_FRONTEND=noninteractive "$container" bash -c "
    set -e
    apt-get update -qq
    apt-get install -y -qq sudo passwd adduser >/dev/null
    useradd -m -s /bin/bash $user
    echo '$user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/$user
    cp -r /repo /home/$user/claude-sandbox
    chown -R $user:$user /home/$user/claude-sandbox
  " >>"$log" 2>&1

  stage_failed=0

  echo "--- setup.sh"
  if ! run_in_container "$container" setup.sh >>"$log" 2>&1; then
    echo "  FAIL  setup.sh exited non-zero"
    stage_failed=1
  fi

  if [ "$stage_failed" -eq 0 ]; then
    run_in_container "$container" test/assert.sh || stage_failed=1

    # install.sh is documented as safe to re-run, so prove it.
    echo "--- install.sh again"
    if run_in_container "$container" install.sh >>"$log" 2>&1; then
      run_in_container "$container" test/assert.sh || stage_failed=1
    else
      echo "  FAIL  install.sh is not idempotent"
      stage_failed=1
    fi
  fi

  if [ "$stage_failed" -ne 0 ]; then
    failed=1
    echo "--- last 40 lines of output"
    tail -40 "$log" | sed 's/^/  /'
    echo "  full log: $log"
  else
    rm -f "$log"
  fi

  if [ "${KEEP:-}" = 1 ]; then
    echo "  container kept: $container"
  else
    docker rm -f "$container" >/dev/null 2>&1
  fi
done

if [ "$failed" -ne 0 ]; then
  echo "FAILED"
  exit 1
fi

echo "PASSED"
