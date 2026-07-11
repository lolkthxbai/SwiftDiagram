# Diagnostics

Diagnostics use one-based line and column positions and end-exclusive source ranges. The CLI format is:

```text
Architecture.swd:12:6: error SWD1027: expected a relationship target
```

The current implementation emits these stable codes:

| Code | Severity | Meaning |
|---|---|---|
| SWD1001 | error | Unterminated string literal |
| SWD1002 | error | Unexpected character |
| SWD1003 | error | Unterminated block comment |
| SWD1010-SWD1027 | error | Malformed or unsupported Milestone 1 syntax |
| SWD1028 | error | Unparseable type reference retained as unresolved text |
| SWD1029 | error | Access modifier used on an enum case |
| SWD1030-SWD1033 | error | Malformed method, parameter, initializer, associated-value, or effect signature |
| SWD2001 | error | Duplicate type declaration |
| SWD2002 | error | Duplicate member |
| SWD2003 | error | Unknown relationship source |
| SWD2004 | error | Unknown reference target |
| SWD2005 | error | Missing `through` member |
| SWD2006 | error | `through` member does not reference the relationship target |
| SWD2007 | error | Duplicate explicit relationship |
| SWD2008 | error | Conflicting explicit relationships |
| SWD2010 | error | Value type cannot inherit a class |
| SWD2011 | note | Enum raw-value entry skipped because raw values are not implemented |
| SWD2012 | note | Class-bound protocol constraint skipped |
| SWD2013 | error | Superclass is not the first inheritance entry |
| SWD2014 | note | Unresolved first class entry assumed to be a superclass |
| SWD2015 | error | Conformance target resolves to a non-protocol declaration |
| SWD2016 | error | `open` access used on a non-class declaration |
| SWD2017 | error | `open` member used outside a class declaration |
| SWD3001 | error | Renderer failure |
| SWD5001 | error | Invalid language-version directive |

The parser recovers at member and top-level boundaries so one run can report multiple independent source errors. Notes do not block rendering; errors do.
