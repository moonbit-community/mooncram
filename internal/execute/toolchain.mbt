///|
/// One invocation's startup environment and lazily selected MoonBit installation.
/// Reuse this value across every document and case in the invocation.
pub struct Toolchain {
  priv startup_cwd : String
  priv startup_path : String?
  priv mut resolved : Result[ResolvedToolchain, @diagnostic.Failure]?
}

///|
priv struct ResolvedToolchain {
  moon : String
  bin : String
}

///|
/// Snapshot PATH without inspecting or starting any tools. `startup_cwd` must
/// be absolute; relative and empty PATH entries are based on this directory.
pub fn Toolchain::new(startup_cwd : String) -> Toolchain {
  { startup_cwd, startup_path: @env.get_env_var("PATH"), resolved: None, }
}

///|
fn tool_name(name : String) -> String {
  if @path.sep == '\\' {
    name + ".exe"
  } else {
    name
  }
}

///|
async fn executable_file(path : String) -> Bool {
  try @fs.can_execute(path) && @fs.kind(path) == Regular catch {
    @os_error.OsError(NotFound | NotDirectory | AccessDenied, ..) => false
    e => raise e
  }
}

///|
async fn Toolchain::resolve(
  self : Toolchain,
  progress : Progress,
) -> ResolvedToolchain {
  if self.resolved is Some(result) {
    return match result {
      Ok(paths) => paths
      Err(error) => raise error
    }
  }
  try self.find(progress) catch {
    @diagnostic.Failure(_) | @os_error.OsError(_, ..) as e => {
      let error = @diagnostic.context(
        @diagnostic.wrap(e, "failed to resolve MoonBit toolchain"),
        tool?=progress.tool,
      )
      self.resolved = Some(Err(error))
      raise error
    }
    e => raise e
  } noraise {
    paths => {
      self.resolved = Some(Ok(paths))
      paths
    }
  }
}

///|
async fn Toolchain::find(
  self : Toolchain,
  progress : Progress,
) -> ResolvedToolchain {
  if self.startup_path is Some(path) {
    for entry in path.split(@path.delimiter.to_string()) {
      let directory = @files.resolve_from(self.startup_cwd, entry.to_owned())
      let candidate = @files.resolve_from(directory, tool_name("moon"))
      if !executable_file(candidate) {
        continue
      }
      // The first executable wins even when its installation is invalid.
      progress.tool = Some(candidate)
      let moon = @fs.realpath(candidate)
      progress.tool = Some(moon)
      let bin = @path.Path(moon).dirname()
      if bin.basename() != "bin" {
        raise @diagnostic.failure(
          "selected moon must be in a toolchain bin directory",
        )
      }
      let root = bin.dirname().to_string()
      for directory in ["include", "lib/core"] {
        let required = @files.resolve_from(root, directory)
        let is_directory = try @fs.kind(required) == Directory catch {
          @os_error.OsError(NotFound | NotDirectory, ..) => false
          e => raise e
        }
        if !is_directory {
          raise @diagnostic.failure(
            "expected toolchain directory '\{required}'",
          )
        }
      }
      let moonc = @files.resolve_from(bin.to_string(), tool_name("moonc"))
      if !executable_file(moonc) {
        raise @diagnostic.failure("expected toolchain executable '\{moonc}'")
      }
      return { moon, bin: bin.to_string(), }
    }
  }
  raise @diagnostic.failure(
    "cannot find executable '\{tool_name("moon")}' on startup PATH",
  )
}

///|
fn ResolvedToolchain::tool(self : ResolvedToolchain, name : String) -> String {
  // In particular, preserve the moonx entry name even when it links to moon:
  // the executable uses that name to select its command-line behavior.
  @files.resolve_from(self.bin, tool_name(name))
}
