defmodule ProcessInfo do
  def run, do: Process.info(self())
end
