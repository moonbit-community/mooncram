///|
fn parse_docs_cli(matches : @argparse.Matches) -> CliCommand raise {
  let list_requested = matches.flags.get("list").unwrap_or(false)
  let names = matches.values.get("doc-name").unwrap_or([])
  match (list_requested, names[:]) {
    (true, []) => DocsList
    (false, [name]) => DocsShow(name)
    (true, [_]) =>
      raise @diagnostic.failure(
        "docs --list cannot be combined with a document name",
      )
    _ => raise @diagnostic.failure("missing docs --list or document name")
  }
}

///|
fn render_docs_list() -> String {
  let mut name_width = 0
  for (name, _, _) in @docs.docs {
    if name.length() > name_width {
      name_width = name.length()
    }
  }
  @docs.docs
  .map(doc => {
    let (name, summary, _) = doc
    let padding = " ".repeat(name_width - name.length() + 2)
    "\{name}\{padding}\{summary}"
  })
  .join("\n")
}

///|
fn render_doc_body(name : String) -> String raise {
  for (doc_name, _, body) in @docs.docs {
    if doc_name == name {
      return body
    }
  }
  raise @diagnostic.failure(
    "unknown document '\{name}'; use mooncram docs --list to list available documents",
  )
}
