///|
async fn main {
  @env.exit(@cli.run(@env.args()[1:].to_owned()))
}
