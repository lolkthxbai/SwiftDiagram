# Versioning

SwiftDiagram has separate package and language versions.

The Milestone 4 package release target is `0.4.0`. Milestone 0 remains an untagged development baseline; Milestones 1 through 3 are tagged `0.1.0`, `0.2.0`, and `0.3.0`. Package versions follow semantic versioning as later milestones add behavior and eventually stabilize the public API.

`.swd` files may declare their language version independently:

```text
swiftDiagram 1.0
```

When the directive is omitted, SwiftDiagram language version 1.0 is assumed. The parser records numeric major, minor, and optional patch components; compatibility enforcement for future language versions will be added before 1.0.
