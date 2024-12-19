defmodule StaticLambda do
  def run, do: ~w[batman green_arrow superman]

  def run(list) do
    Enum.map(list, &String.upcase/1)
  end
end
