# Repository Bundles CLI

Export Git and Mercurial repositories into portable bundle files, one per
repository. Each bundle contains the history, branches and tags available to the
clone. Git exports also attempt to include pull request and merge request refs.

## Required: Quickstart

Follow these four steps to create and collect your bundles. Everything after the
**Optional reference** divider covers alternative inputs and advanced usage.

### 1. Install dependencies

Use macOS or Linux with Bash, Git and an SSH client.

**macOS**, with [Homebrew](https://brew.sh/) installed:

```bash
brew install git
```

Bash and the SSH client are included with macOS.

**Ubuntu / Debian**:

```bash
sudo apt-get update
sudo apt-get install -y bash git openssh-client ca-certificates
```

<details>
<summary>Optional dependency: Mercurial</summary>

Install this only if your list includes Mercurial repositories:

**macOS**:

```bash
brew install mercurial
```

**Ubuntu / Debian**:

```bash
sudo apt-get install -y mercurial
```

</details>

**Then, on either platform**:

```bash
git clone https://github.com/Fermatix/repo_bundles_cli.git
cd repo_bundles_cli
chmod +x make_bundles.sh
```

Run subsequent commands from this directory.

### 2. Prepare the repository list

Create `repos.txt` with one Git SSH URL per line. This Quickstart assumes your SSH
key is configured and has read access to the repositories:

```text
# Blank lines and lines starting with # are ignored

git@git.example.com:group/service-api.git
git@git.example.com:group/mobile-app.git
```

Replace the examples with your repositories. Leading and trailing whitespace is
trimmed; both Unix and Windows line endings are accepted.

### 3. Create bundles

```bash
./make_bundles.sh repos.txt ./bundles
```

For each repository, the script creates a temporary mirror, fetches available
review refs, creates and verifies a bundle, then removes the temporary clone.
The source repository is not changed.

### 4. Collect the results

The files to share are in **`./bundles`**. The example list produces:

```text
bundles/group_service-api.bundle
bundles/group_mobile-app.bundle
```

Check the final summary: the successful count should match the number of
repositories in your list, with no errors. Exit status `0` means all listed
repositories were exported; a nonzero status indicates an error. Progress and
summary messages are currently in Russian.

If a repository fails, successful bundles remain in the output directory. Fix
access or dependencies and rerun a list containing the failed repositories.

---

## Optional reference

The export workflow above is complete. Read below only for other input types,
output settings or restoring a bundle.

### HTTPS access

HTTPS URLs are an alternative in `repos.txt`:

```text
https://github.com/example-org/mobile-app.git

# Without an SSH key, include your username and token in the HTTPS URL
https://username:TOKEN@git.example.com/group/legacy-service.git
```

For private repositories, configure a Git credential helper or use credentials
in the URL. The script disables Git's interactive username/password prompts.

### Local repositories

Local Git repositories can also be listed:

```text
/home/user/repos/internal-tool
```

Use absolute paths.

### Mercurial

Install the optional `hg` dependency from step 1, then prefix Mercurial entries
with `hg+`:

```text
hg+https://hg.example.org/old-project
hg+/home/user/repos/legacy-billing
```

The script uses `hg clone -U`, `hg bundle --all` and `hg debugbundle`, producing
`.hgbundle` files. Without `hg`, Mercurial entries fail while Git entries are
still processed. Empty repositories cannot produce a bundle.

Explicit `hg+` and `git+` prefixes override detection. Otherwise, a `.git` suffix
selects Git; hosts matching `hg.*`, `*heptapod*` or `mercurial-scm.org` (including
its subdomains) select Mercurial. Other inputs default to Git.

### Output settings

```text
./make_bundles.sh <repository-list> [output-directory]
```

The list is required. The output directory defaults to `./bundles` and is created
if needed. Repository path separators become single underscores:
`group/service-api.git` becomes `group_service-api.bundle`.

Hostnames are omitted from filenames. Use separate output directories for
repositories whose names would collide. Each run clones the listed repositories
again and replaces matching output files; it does not resume earlier work.

### Review refs

By default, after `git clone --mirror`, the script attempts to fetch these
additional namespaces:

```text
+refs/merge-requests/*:refs/merge-requests/*
+refs/pull/*:refs/pull/*
```

These can retain commits from PR/MR branches that are no longer ordinary branches.
The server must make the refs available to your account. Fetch failures for these
namespaces do not fail the export, so an `OK` result does not guarantee their
presence. The progress line reports the review ref count when it is nonzero.

To skip the additional fetches:

```bash
HIDDEN_REFS=0 ./make_bundles.sh repos.txt ./bundles
```

### Restore a bundle

To inspect the refs saved in a Git bundle:

```bash
git bundle list-heads bundles/group_service-api.bundle
```

For a working copy:

```bash
git clone bundles/group_service-api.bundle restored-service-api
```

A normal clone does not import the review namespaces. To import all bundled refs
into a bare mirror instead:

```bash
git clone --mirror bundles/group_service-api.bundle restored-service-api.git
```

For Mercurial:

```bash
hg clone bundles/old-project.hgbundle restored-old-project
```
