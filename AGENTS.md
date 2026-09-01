## Commit Message Workflow

When creating a commit, first create a temporary file and write the complete commit message
into that file. Then create the commit with `git commit -F path_to_temp_file`. Do not use
`git commit -m`. Remove the temporary file after the commit succeeds.

Before committing a fix or feature:

1. Run `./build.sh version` and note the current package version.
2. Decide between a patch increment for a backward-compatible fix and a minor
   increment for a backward-compatible feature. Keep the current major component.
3. Never change the major component. Major-version changes are made only by the
   user. If a change would require a new major version, report that requirement and
   wait for the user to change the version before committing.
4. Run `./build.sh version set <new_sem_ver>` with the selected patch or minor
   version.
5. Include every version file updated by that command in the fix or feature commit.

## Temporary Files

Remove any temporary file when it is no longer needed using plain `rm path_to_temp_file`,
without additional flags.

## Zig Version

Use `./build.sh` for normal local build and test commands. It selects the Zig version declared
by `minimum_zig_version` in `build.zig.zon` and fails clearly when that compiler is unavailable.
