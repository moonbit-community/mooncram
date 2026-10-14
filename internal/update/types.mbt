///|
priv struct Edit {
  start : Int32
  end : Int32
  text : String
}

///|
/// A validated in-memory expectation update returned by `generate`.
pub struct Generated {
  /// Complete updated Markdown, ready for a diff or guarded filesystem write.
  source : String
  /// Number of distinct changed cases, including cases whose shared
  /// fence markers changed. Each case is counted at most once.
  changed_cases : Int32
}
