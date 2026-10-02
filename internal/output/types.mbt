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
pub struct Expectation {
  lines : Array[ExpectedLine]
  exit_code : Int
  no_eol : Bool
}

///|
pub(all) struct Captured {
  output : String
  diagnostic : String
  exit_code : Int
}
