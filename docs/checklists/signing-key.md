# Create the package signing key

For Alex, on his own machine. About 15 minutes. You need `gpg` (installed on
Arch by default) and a password manager.

The key signs every package and the package list in the `[invictus-testing]`
repo, so pacman on your machines can tell our packages from tampered ones.
The private key lives in two places only: your machine and a GitHub Actions
secret. Nothing secret goes into the repo, a chat or a file on disk other
than the backup in step 3.

## 1. Make the key

- [ ] Open a terminal and run:

  ```
  gpg --quick-gen-key "Invictus package repo" ed25519 sign 2y
  ```

  It asks for a passphrase. Make a long one, save it in your password manager
  as "Invictus repo key passphrase". The key expires in two years; extending
  it later is one command.

- [ ] Get the fingerprint (the 40-character line under `pub`):

  ```
  gpg --fingerprint "Invictus package repo"
  ```

  Remove the spaces and keep it at hand. Below it is written `FPR`.

## 2. Put the public key in the repo

The public key is safe to share. This is what every Invictus machine uses to
check signatures.

- [ ] In your clone of the repo:

  ```
  cd ~/invictus
  git pull
  gpg --armor --export FPR > pkgs/own/invictus-keyring/invictus.gpg
  head -1 pkgs/own/invictus-keyring/invictus.gpg
  ```

  The last line must print `-----BEGIN PGP PUBLIC KEY BLOCK-----`. If it says
  PRIVATE, stop and tell Cicero.

- [ ] Commit and push it:

  ```
  git add pkgs/own/invictus-keyring/invictus.gpg
  git commit -m "invictus-keyring: add the repo public key"
  git push
  ```

  If you would rather not push, send the file to Cicero instead. It is public.

## 3. Back up the private key (offline)

- [ ] Plug in a USB stick you keep somewhere safe, then:

  ```
  gpg --armor --export-secret-keys FPR > /run/media/$USER/<stick>/invictus-repo-key.asc
  cp ~/.gnupg/openpgp-revocs.d/FPR.rev /run/media/$USER/<stick>/
  ```

  The `.rev` file revokes the key if it is ever stolen. Unplug the stick.

## 4. Give GitHub the key

The secrets page: https://github.com/turneralexander55/invictus/settings/secrets/actions

- [ ] Copy the private key to the clipboard without writing it to a file:

  ```
  gpg --armor --export-secret-keys FPR | wl-copy
  ```

  It asks for the passphrase.

- [ ] Open https://github.com/turneralexander55/invictus/settings/secrets/actions/new
  - Name: `REPO_SIGNING_KEY`
  - Secret: paste
  - Click **Add secret**

- [ ] Clear the clipboard: `wl-copy --clear`

- [ ] Open https://github.com/turneralexander55/invictus/settings/secrets/actions/new again
  - Name: `REPO_SIGNING_PASSPHRASE`
  - Secret: the passphrase from step 1
  - Click **Add secret**

- [ ] The secrets page now lists both names. GitHub never shows the values
  again, which is expected.

## 5. Build the repo

- [ ] Open https://github.com/turneralexander55/invictus/actions/workflows/packages.yml,
  click **Run workflow**, branch `main`, **Run workflow**.
- [ ] When it finishes (a few minutes), open the run. There should be no
  "Unsigned repo" warning.
- [ ] https://github.com/turneralexander55/invictus/releases/tag/invictus-testing
  lists `invictus-keyring-...pkg.tar.zst`, a `.sig` next to every package, and
  `invictus-testing.db` with `invictus-testing.db.sig`.

## 6. Use it on this machine

- [ ] Tell pacman to trust the key:

  ```
  sudo pacman-key --add ~/invictus/pkgs/own/invictus-keyring/invictus.gpg
  sudo pacman-key --lsign-key FPR
  ```

- [ ] Add the repo. Open `/etc/pacman.conf` with `sudo nano /etc/pacman.conf`
  and put these lines just above the `[core]` line:

  ```
  [invictus-testing]
  Server = https://github.com/turneralexander55/invictus/releases/download/invictus-testing
  ```

- [ ] Install the keyring:

  ```
  sudo pacman -Syu invictus-keyring
  ```

  The output includes "Appending keys from invictus.gpg". From now on the
  keyring package keeps the key current.

- [ ] Tell Cicero it worked, or paste the error.

For now install only `invictus-keyring`. The meta packages
(`invictus-desktop` and the rest) are in the repo but need Phase 1 before
they install.

## Later

- Adding a collaborator to the GitHub repo gives them a way to use the
  secret. Make a new key then (steps 1 to 5 again) and tell Cicero, who
  moves the old one to `invictus-revoked`.
- Two years from now: `gpg --quick-set-expire FPR 2y`, then steps 2 and 4.
