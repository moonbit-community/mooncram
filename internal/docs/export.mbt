///|
pub let docs : ReadOnlyArray[(String, String, String)] = [
  (
    "quickstart", "First test: targets, path bases, execution rules, and check/test/update workflow.",
    quickstart_md,
  ),
  (
    "recipes", "Runnable templates: stderr, exit codes, patterns, env, pipes, no-eol.",
    recipes_md,
  ),
  (
    "troubleshooting", "Diagnose missing cases/paths/modules, build errors, timeouts, and failed updates.",
    troubleshooting_md,
  ),
  (
    "invocation", "CLI options, defaults, check validation, and embedded docs.",
    invocation_md,
  ),
  (
    "discovery", "Find Markdown inputs: paths, exclusions, symlinks, and ordering.",
    discovery_md,
  ),
  (
    "markdown", "Write mooncram fences, local module declarations, and case boundaries.",
    markdown_md,
  ),
  (
    "commands", "Write commands without a shell; resolve #cwd/paths, local packages, env, pipes.",
    commands_md,
  ),
  (
    "execution", "Select backends; run without isolation; share timeouts across builds, fetching, capture.",
    execution_md,
  ),
  (
    "expectations", "Assert stdout/stderr and exit codes; choose exact, glob, regex, no-eol.",
    expectations_md,
  ),
  (
    "reports", "Read FAIL/ERROR diagnostics, output diffs, and report color.", reports_md,
  ),
  (
    "updates", "Preview/apply updates: passing cases, normalization, preserved patterns, blocked documents.",
    updates_md,
  ),
  (
    "errors", "Understand blocked updates, concurrent edits, and safe file replacement.",
    errors_md,
  ),
  (
    "summaries", "Interpret counters, updated 0, CLI exit codes, and dry-run success versus test success.",
    summaries_md,
  ),
]
