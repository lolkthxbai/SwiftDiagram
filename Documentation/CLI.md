# CLI

Milestone 1 provides `render` and `validate`. Both commands read local files, perform no network access, and print diagnostics to standard error.

## Render

```bash
swiftdiagram render Architecture.swd
swiftdiagram render Architecture.swd --format mermaid
swiftdiagram render Architecture.swd --output Architecture.mmd
swiftdiagram render Architecture.swd --stdout
```

Mermaid is the only Milestone 1 format and is the default. Without `--output`, rendered text is written to standard output. `--stdout` and `--output` are mutually exclusive. Rendering is suppressed when parsing or validation produces an error.

## Validate

```bash
swiftdiagram validate Architecture.swd
```

Valid input exits successfully without output. Notes and errors are printed to standard error. Invalid input exits nonzero.

## Exit Status

- `0`: parsing, validation, and any requested rendering succeeded.
- `1`: source diagnostics contain an error.
- `64`: command arguments or file I/O are invalid.

Configuration discovery, `--force`, PlantUML, inspection, formatting, and JSON commands are planned for later milestones.
