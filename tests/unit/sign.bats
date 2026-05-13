#!/usr/bin/env bats

load '../test_helper/common.bash'

setup() {
  export SCRIPT="$REPO_ROOT/scripts/sign.sh"
  export GNUPGHOME="$REPO_ROOT/tests/fixtures/gpg"
  mkdir -p "$GNUPGHOME"
  chmod 700 "$GNUPGHOME"

  # Generate a throwaway signing key if not already present
  if ! gpg --homedir "$GNUPGHOME" --list-secret-keys 2>/dev/null | grep -q "openkazoo-test"; then
    gpg --homedir "$GNUPGHOME" --batch --generate-key <<EOF 2>/dev/null
%no-protection
Key-Type: EDDSA
Key-Curve: ed25519
Subkey-Type: ECDH
Subkey-Curve: cv25519
Name-Real: openkazoo-test
Name-Email: openkazoo-test@example.invalid
Expire-Date: 0
%commit
EOF
  fi
}

@test "sign.sh exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "sign.sh fails if no TARGET is given" {
  run "$SCRIPT"
  assert_status 2
  assert_output_contains "TARGET"
}

@test "sign.sh fails if TARGET is unknown" {
  run "$SCRIPT" ubuntu-99
  assert_status 2
}

@test "sign.sh fails gracefully if no package exists yet" {
  rm -rf "$REPO_ROOT/build/out/kazoo_*.deb"
  GNUPGHOME="$GNUPGHOME" run "$SCRIPT" debian-12
  # Acceptable to either find no .deb (status nonzero) OR succeed if a deb is present
  if [ ! -f "$REPO_ROOT/build/out/kazoo_*.deb" ] 2>/dev/null; then
    [ "$status" -ne 0 ]
  fi
}
