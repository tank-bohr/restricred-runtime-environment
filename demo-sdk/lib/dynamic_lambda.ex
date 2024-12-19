defmodule DynamicLambda do
  def run, do: ~w[batman green_arrow superman]

  def run(list) do
    mod = String.to_atom("String")
    Enum.map(list, &mod.upcase/1)
  end
end
