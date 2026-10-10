///|
priv enum Matcher {
  Equal(String)
  Glob(Array[GlobToken])
  Regex(@string.Regex)
}

///|
pub struct ExpectedLine {
  raw : String
  priv matcher : Matcher
}

///|
pub struct StreamExpectation {
  lines : Array[ExpectedLine]
  no_eol : Bool
}

///|
pub(all) enum Stream {
  Stdout
  Stderr
} derive(Eq)

///|
pub extend Stream with Eq::{equal, not_equal}

///|
pub(all) enum StreamConstraint {
  Match(StreamExpectation)
  Ignore
  Empty
}

///|
pub struct StreamSection {
  stream : Stream
  constraint : StreamConstraint
  // Row offsets into Expectation.source_lines; end includes separator blanks.
  start : Int
  content_end : Int
  end : Int
}

///|
pub(all) enum ExpectedBody {
  Legacy(StreamExpectation)
  Streams(Array[StreamSection])
}

///|
pub struct Expectation {
  body : ExpectedBody
  exit_code : Int
  source_lines : Array[String]
}

///|
pub(all) struct Captured {
  output : String
  diagnostic : String
  exit_code : Int
}
