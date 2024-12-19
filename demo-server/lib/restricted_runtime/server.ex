defmodule RestrictedRuntime.Server do
  @moduledoc false

  require Logger

  @socket_name "/tmp/restricted-runtime-environment.sock"
  @listen_opts [:binary, active: false, reuseaddr: true, packet: 4, ip: {:local, @socket_name}]

  def start do
    :ok = File.rm!(@socket_name)
    {:ok, listen_socket} = :gen_tcp.listen(0, @listen_opts)
    Logger.info("Listening...")
    loop(listen_socket)
  end

  defp loop(listen_socket) do
    {:ok, socket} = :gen_tcp.accept(listen_socket)
    serve(socket)
    loop(listen_socket)
  end

  defp serve(socket) do
    {:ok, info} = :gen_tcp.recv(socket, 0)
    :ok = :gen_tcp.shutdown(socket, :read_write)

    case RestrictedRuntime.compile(info) do
      {:ok, module} -> execute(module)
      {:error, reason} -> Logger.error("Compilation error: " <> inspect(reason))
    end
  end

  defp execute(module) do
    if function_exported?(module, :run, 0) do
      execute_with_timeout(module)
    else
      Logger.error("The module is not compatible")
    end
  end

  defp execute(module, pid, ref) do
    result = module.run()
    send(pid, {ref, result})
  end

  defp execute_with_timeout(module) do
    parent = self()
    ref = make_ref()
    {pid, mon_ref} = spawn_monitor(fn -> execute(module, parent, ref) end)

    receive do
      {^ref, result} ->
        Process.demonitor(mon_ref, [:flush])
        Logger.info("Execution result: " <> inspect(result))

      {:DOWN, ^mon_ref, :process, ^pid, reason} ->
        Logger.error("Execution error: " <> inspect(reason))
    after
      5000 ->
        Process.exit(pid, :kill)
        Logger.error("Execution timed out")
    end
  end
end
