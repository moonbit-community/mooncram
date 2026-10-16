# Error isolation and safe replacement

After a case execution error, later cases in the same document still run.
However, any execution/build/timeout error suppresses **all** expectation edits
for that document. If any successful case was captured for update, stderr also
receives:

```text
Not updating <canonical-file>: execution errors in this document
```

The same suppression applies to proposed dry-run document diffs. Parsing
errors prevent execution altogether. Errors in one document do not prevent
other discovered documents from running and updating, and do not undo earlier
updates or program effects.

Before replacing a changed document, mooncram checks that its content still
matches what was read before execution. If another process or a test changed it,
mooncram refuses to overwrite it and reports:

```text
source changed during execution; refusing to update <path>
```

Replacement is atomic per file; updates across documents are not a transaction.
The content check is not a filesystem lock, and there is a window between the
check and replacement. File symlinks were resolved during discovery, so replacement
targets the canonical document. Original permissions, inode identity, hard-link
relationships, and extended metadata are not preserved. On Unix, the replacement
uses new-file permissions `0644`, subject to umask; this Unix permission rule
does not apply on Windows.
