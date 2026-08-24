## Commit Message Workflow

When creating a commit, first create a temporary file and write the complete commit message
into that file. Then create the commit with `git commit -F path_to_temp_file`. Do not use
`git commit -m`. Remove the temporary file after the commit succeeds.

## Temporary Files

Remove any temporary file when it is no longer needed using plain `rm path_to_temp_file`,
without additional flags.

## Zig Version

Use `./build.sh` for normal local build and test commands. It selects the Zig version declared
by `minimum_zig_version` in `build.zig.zon` and fails clearly when that compiler is unavailable.
