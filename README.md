# FoxPack

Libraries for Visual FoxPro projects, downloaded from GitHub at a fixed version.

```
foxpack add jsonfox
```

FoxPack puts the library in `lib\jsonfox\` of your project and records it in
`foxpack.lock`: the exact commit and the SHA-256 of every file. Commit both to git,
and anyone who clones the project gets the same bytes with `foxpack restore`.

FoxPack is written in Visual FoxPro and built with
[FoxCli](https://irwinrodriguez.dev): it is a console application, like any other,
and its source is the example.

## Commands

| Command | What it does |
|---|---|
| `foxpack add jsonfox` | Install the latest version of a library from the index |
| `foxpack add jsonfox@13.1` | Install a given version |
| `foxpack add github:user/repo` | Install a library that is not in the index (asks first; `--yes` for scripts) |
| `foxpack restore` | Download exactly what `foxpack.lock` says |
| `foxpack update [library]` | Move one library, or all of them, to the latest version |
| `foxpack remove library` | Delete it from `lib\`, from `foxpack.lock` and from the closed `.pjx` |
| `foxpack list` | The installed libraries (`--format json` for scripts) |
| `foxpack verify` | Check that nobody has edited the copies in `lib\` |

Every command works on the current folder, or on the one given with `-p`.
`foxpack <command> --help` explains each one, and [docs/foxpack.md](docs/foxpack.md)
has all of them.

## Rules

- **A library's copy is never edited.** The fix goes to its repository, and a new
  version comes back with `foxpack update`. `verify` and `update` notice a changed
  copy, and `update` will not overwrite it without `--force`.
- **Fixed versions.** A version is a tag of the library's repository, and
  `foxpack.lock` keeps its commit: a tag can move, a commit cannot.
- **Bytes as they come.** A CP1252 `.prg` is saved exactly as it was published.
  FoxPack also writes `lib\.gitattributes` so that git does not change line endings.
- **All or nothing.** A library is downloaded to a temporary folder and only
  replaces the old one when every file has arrived.
- **No code is run.** Installing a library copies files; nothing of the library
  executes.

## With FoxForge

In FoxForge (0.3.22 or later), *FoxForge > Current project > Add library...* runs `foxpack add`, and
building (Ctrl+F7) puts the files of `foxpack.lock` in the project and takes out
those it no longer lists. The test bench finds the libraries in `lib\` too.

## Publishing a library

Put a `foxpack.json` in the root of your repository:

```json
{
  "name": "mylib",
  "version": "1.0",
  "description": "What it does",
  "license": "MIT",
  "files": ["MyLib.prg"],
  "usage": "loLib = NEWOBJECT(\"MyLib\", \"MyLib.prg\")"
}
```

Tag that commit with the same version (`v1.0`). Anyone can then install it with
`foxpack add github:you/mylib`. To install it by name, add it to the
[index](https://github.com/Irwin1985/foxpack-index).

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Done |
| 10 | The library or the version does not exist |
| 11 | Download failed (network, GitHub, a missing file) |
| 12 | A copy in `lib\` does not match `foxpack.lock` |
| 13 | The repository has no valid `foxpack.json` |
| 14 | The folder is not a project, or `foxpack.lock` cannot be read |

## License

MIT. See [LICENSE](LICENSE).
