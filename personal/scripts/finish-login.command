#!/bin/bash
# Run once by the user. No secret is embedded in this launcher.
set -euo pipefail
config="$HOME/Library/Application Support/cmux-personal/config.json"
if [[ ! -f "$config" ]]; then
  echo 'Open cmux Personal and configure Connection first.'
  read -r -p 'Press Return to close. ' _
  exit 1
fi
key="$(/usr/bin/plutil -extract connection.identityFile raw -o - "$config")"
host="$(/usr/bin/plutil -extract connection.host raw -o - "$config")"
port="$(/usr/bin/plutil -extract connection.port raw -o - "$config")"
if [[ "$key" == '~/'* ]]; then key="$HOME/${key:2}"; fi
if [[ "$key" != /* || ! -f "$key" ]]; then
  echo 'Choose your SSH key file in the app Connection settings first.'
  read -r -p 'Press Return to close. ' _
  exit 1
fi
echo 'One-time setup for cmux Personal'
echo
echo 'This stores the password protecting your configured SSH key in macOS Keychain.'
echo 'The app can then connect after a restart. It does not store the password itself.'
echo 'The SSH key file and server account will not be changed.'
echo
read -r -p 'Save this key password in macOS Keychain? [y/N] ' answer
case "$answer" in y|Y|yes|YES) ;; *) echo 'No changes made.'; exit 0 ;; esac
echo 'Enter the SSH KEY password when asked. Typing is hidden.'
if ! /usr/bin/ssh-add --apple-use-keychain "$key"; then
  echo 'Setup did not complete. The SSH key password was not accepted.'
  read -r -p 'Press Return to close. ' _
  exit 1
fi
echo 'Checking access without relying on the currently unlocked SSH agent...'
if /usr/bin/ssh -T -o IdentityAgent=none -o IdentitiesOnly=yes \
  -o UseKeychain=yes -o AddKeysToAgent=no -o BatchMode=yes \
  -o StrictHostKeyChecking=yes -o ForwardAgent=no -o ClearAllForwardings=yes \
  -o PermitLocalCommand=no -o ConnectTimeout=10 \
  -i "$key" -p "$port" -l developer -- "$host" true; then
  echo
  echo 'READY. You can shut down your Mac. Keep the VPS running.'
  echo 'Tomorrow: sign in to macOS, then open cmux Personal Preview from Applications.'
else
  echo
  echo 'The password was saved, but the connection check failed.'
  echo 'Do not assume setup is complete; check the network and Connection settings.'
fi
read -r -p 'Press Return to close. ' _
