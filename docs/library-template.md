# Publishing a library: the template

A library needs two files in the root of its repository, and nothing else:

| File | For whom |
|---|---|
| `foxpack.json` | FoxPack, to install it |
| `README.md` | People and AI agents, to use it. FoxStack serves it to agents as `foxstack://libs/<name>` |

The README is the manual. There is no other document to keep in sync, so write it once,
in English, with the sections below and in this order. An agent reads it top to bottom
and writes code from it: say what the library does, show it working, list every public
call, and warn about what goes wrong.

## foxpack.json

```json
{
  "name": "mylib",
  "version": "1.0.0",
  "description": "One sentence: what it does",
  "license": "MIT",
  "files": ["mylib.prg"],
  "usage": "SET PROCEDURE TO mylib.prg ADDITIVE"
}
```

- `files`: the `.prg` and `.h` files a program needs, nothing else (no tests, no samples).
- `usage`: the one line that loads the library. FoxPack prints it after `foxpack add`.
- Tag the commit with the same version (`v1.0.0`).

## README.md

Copy this, replace what is in angle brackets, and delete what does not apply.

````markdown
# <Name>

<One or two sentences: what it does and when to use it.>

## Install

```
foxpack add <name>
```

```foxpro
SET PROCEDURE TO <file>.prg ADDITIVE
```

<Anything else it needs: VFP version, a DLL, a SET command. If nothing, delete this line.>

## Example

```foxpro
<A complete example someone can paste into a .prg and run.>
```

## API

### <Function or Class.Method>(<parameters>)

<What it does, in one or two sentences.> Returns <what>.

```foxpro
<One short example.>
```

<One ### block per public function, class and method.>

## Pitfalls

- **<What goes wrong.>** <Why, and what to write instead.>

## License

<MIT, GPL-3.0, ...>. See [LICENSE](LICENSE).
````

## Rules of thumb

- **Every example runs as written.** VFP cannot chain calls on the result of a method
  (`loX.Do().Then()` does not compile): show `WITH ... ENDWITH` or one call per line.
- **Write the pitfalls.** They are the part an agent cannot guess, and the reason the
  manual exists.
- **Keep it in the README.** A second document drifts; one file does not.
