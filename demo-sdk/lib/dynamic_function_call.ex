defmodule DynamicFunctionCall do
  def run, do: ~w[batman green_arrow superman]

  def run(list) do
    mod = String.to_atom("String")
    Enum.map(list, fn hero -> mod.upcase(hero) end)
  end
end
