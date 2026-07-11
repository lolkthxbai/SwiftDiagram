# CLI

The CLI provides offline `render`, `validate`, and `format` commands. All commands read local files, perform no network access, and print diagnostics to standard error.

## Render

```bash
swiftdiagram render Architecture.swd
swiftdiagram render Architecture.swd --format mermaid
swiftdiagram render Architecture.swd --format plantuml --output Architecture.puml
swiftdiagram render Architecture.swd --output Architecture.mmd
swiftdiagram render Architecture.swd --stdout
swiftdiagram render Architecture.swd --extensions separate
```

Mermaid is the default format. PlantUML is selected with `--format plantuml` and produces textual `.puml` source without requiring Java, a browser, or a remote server. Extensions default to `merged`; `--extensions separate` renders extension blocks and edges, while `--extensions hidden` omits extension-originated members and conformances. Without `--output`, rendered text is written to standard output. `--stdout` and `--output` are mutually exclusive. Rendering is suppressed when parsing or validation produces an error.

## Validate

```bash
swiftdiagram validate Architecture.swd
```

Valid input exits successfully without output. Notes and errors are printed to standard error. Invalid input exits nonzero.

## Format

```bash
swiftdiagram format Architecture.swd
swiftdiagram format Architecture.swd --in-place
swiftdiagram format Architecture.swd --check
```

Without a flag, canonical source is written to standard output. `--in-place` rewrites the input atomically. `--check` performs a byte-for-byte comparison against canonical output and exits nonzero when the file would change. The two flags are mutually exclusive, and syntax errors are never rewritten.

## Exit Status

- `0`: parsing, validation, and any requested rendering succeeded.
- `1`: source diagnostics contain an error.
- `64`: command arguments or file I/O are invalid.

Configuration discovery, `--force`, inspection, and JSON commands are planned for later milestones.
