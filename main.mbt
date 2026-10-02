///|
async fn main {
  @sys.exit(@cli.run(@env.args()[1:].to_owned()))
}
