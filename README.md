# Corenna repo check

Find out whether your GitHub repo can be built into a signed Android app, or an iPhone app (beta), before you spend a build on it.

This Action runs the same free check as [corenna.dev/check](https://corenna.dev/check?utm_source=github&utm_medium=action&utm_campaign=repo_check). It reads your public repo from GitHub, finds the app in it (a Flutter or React Native app, or a web app made with Lovable, Bolt, v0, Vite or Next), and reports:

- what is ready for the build,
- what would stop the build, and how to fix it,
- what Google Play and the App Store will ask for before they accept the app, such as a privacy policy.

The report lands in the job summary of your workflow run, and each problem shows as an annotation.

The check is free and needs no account or API key.

## Use it

Add a workflow file to your repo, for example `.github/workflows/corenna-check.yml`:

```yaml
name: Corenna repo check
on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: nathanclaiborne21/corenna-repo-check@v1
```

No checkout step is needed: Corenna reads the repo from GitHub.

### Check for an iPhone build

```yaml
      - uses: nathanclaiborne21/corenna-repo-check@v1
        with:
          platform: ios
```

### Fail the workflow when the build would fail

```yaml
      - uses: nathanclaiborne21/corenna-repo-check@v1
        with:
          fail-on-blocking: true
```

### Use the result in a later step

```yaml
      - uses: nathanclaiborne21/corenna-repo-check@v1
        id: corenna
      - if: steps.corenna.outputs.ready == 'true'
        run: echo "Ready to build. Report: ${{ steps.corenna.outputs.report-url }}"
```

## Inputs

| Input | Default | What it does |
| --- | --- | --- |
| `repository` | the repo the workflow runs in | The public repo to check, as `owner/name` or a github.com link. |
| `platform` | `android` | `android` or `ios`. iPhone builds are in beta. |
| `fail-on-blocking` | `false` | `true` fails the step when the check finds a problem that would stop the build. |

## Outputs

| Output | What it holds |
| --- | --- |
| `checked` | `true` when the check ran. `false` when the repo is private or missing, or Corenna's check could not be reached. |
| `ready` | `true` when nothing in the repo blocks a build. |
| `blocking` | How many problems would stop the build. |
| `warnings` | How many things are worth a look but do not stop the build. |
| `report-url` | The full report on corenna.dev. |

## Good to know

- **It checks the default branch as it is on GitHub.** Changes that are only in a pull request are not checked until they are merged.
- **Public repos only.** A private repo can't be read by the public check. Sign up on [corenna.dev](https://corenna.dev/auth?mode=signup&utm_source=github&utm_medium=action&utm_campaign=repo_check), connect the repo through Corenna's GitHub App, and the check runs there.
- **What it sends.** The step sends Corenna the repo's GitHub link and the platform, nothing else: no token and no files from the runner.
- **If Corenna can't be reached,** the step shows a warning and your workflow carries on. Only a problem in your repo (with `fail-on-blocking: true`) or a wrong input fails the step.
- It runs on GitHub's hosted Linux and macOS runners, which have `curl` and `jq`.

## Build the app

When the check passes, [Corenna](https://corenna.dev/?utm_source=github&utm_medium=action&utm_campaign=repo_check) builds the signed app on GitHub Actions in your own repo: an `.apk` to install on a phone or an `.aab` for Google Play, or an `.ipa` for iPhone.

Building your Android app is free. Downloading it needs a plan: $1 for your first month. iPhone builds are in beta and need a plan.

## License

MIT
