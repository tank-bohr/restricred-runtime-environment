defmodule DemoSDK do
  @moduledoc false

  @socket_name "/tmp/restricted-runtime-environment.sock"
  @socket_opts [:binary, active: false, reuseaddr: true, packet: 4]

  def send(module) do
    with {:ok, abstract_code} <- abstract_code(module),
         {:ok, socket} <- :gen_tcp.connect({:local, @socket_name}, 0, @socket_opts) do
      :gen_tcp.send(socket, abstract_code)
    end
  end

  def show(module) do
    with {:ok, abstract_code} <- abstract_code(module) do
      {:debug_info_v1, mod, info} = :erlang.binary_to_term(abstract_code)
      mod.debug_info(:erlang_v1, :not_relevant, info, [])
    end
  end

  def abstract_code(module) when is_atom(module) do
    case :code.which(module) do
      :non_existing -> {:error, :not_module}
      beam_path -> abstract_code(beam_path)
    end
  end

  def abstract_code(beam_path) do
    {:ok, _module, chunks} = :beam_lib.all_chunks(beam_path)
    {:ok, :proplists.get_value(~c"Dbgi", chunks)}
  end
end
