defmodule RestrictedRuntime do
  alias RestrictedRuntime.Filter

  @whitelist MapSet.new([
               {:crypto, :hash, 2},
               {:crypto, :hash, 2},
               {:erlang, :++, 2},
               {:erlang, :element, 2},
               {:erlang, :error, 1},
               {:erlang, :get_module_info, 2},
               {:timer, :seconds, 1},
               {Access, :get, 2},
               {Base, :encode64, 1},
               {Base, :url_encode64, 1},
               {DateTime, :to_unix, 1},
               {DateTime, :utc_now, 0},
               {Enum, :find, 2},
               {Enum, :map, 2},
               {Integer, :parse, 1},
               {Jason, :decode, 1},
               {Jason, :encode!, 1},
               {Jason, :encode, 1},
               {Kernel, :=~, 2},
               {Kernel, :div, 2},
               {Kernel, :inspect, 1},
               {Keyword, :merge, 2},
               {Map, :get, 2},
               {Map, :get, 3},
               {String, :pad_leading, 3},
               {String, :trim_trailing, 2},
               {String.Chars, :to_string, 1},
               {UUID, :uuid4, 0}
             ])

  @spec compile(String.t()) :: {:ok, module()} | {:error, any()}
  def compile(code), do: compile(UUID.uuid4(), code)

  @spec compile(String.t(), String.t()) :: {:ok, module()} | {:error, any()}
  def compile(id, code) do
    with {:ok, forms} <- extract_erlang_forms(code),
         :ok <- check_ast(forms) do
      compile_forms(id, forms)
    end
  end

  defp extract_erlang_forms(debug_info) do
    {:debug_info_v1, mod, info} = Plug.Crypto.non_executable_binary_to_term(debug_info)
    mod.debug_info(:erlang_v1, :not_relevant, info, [])
  end

  defp compile_forms(id, forms) do
    {module, forms} = rename_module(id, forms)
    {^module, bin} = :elixir_erl_compiler.noenv_forms(forms, "#{module}", [])
    :code.load_binary(module, to_charlist("#{module}.erl"), bin)
    {:ok, module}
  end

  defp rename_module(id, forms) do
    module = Module.concat(__MODULE__, id)
    {:attribute, anno, :module, _original_module} = :lists.keyfind(:module, 3, forms)
    forms = :lists.keyreplace(:module, 3, forms, {:attribute, anno, :module, module})
    {module, forms}
  end

  defp check_ast(forms) do
    calls = Filter.remote_function_calls(forms)

    cond do
      MapSet.member?(calls, :dynamic_lambda) ->
        {:error, :dynamic_lambdas_are_not_allowed}

      MapSet.member?(calls, :dynamic_function_call) ->
        {:error, :dynamic_function_calls_are_not_allowed}

      true ->
        check_against_whitelist(calls)
    end
  end

  defp check_against_whitelist(calls) do
    not_allowed = MapSet.difference(calls, @whitelist)

    case MapSet.size(not_allowed) do
      0 -> :ok
      _non_zero -> {:error, {:not_allowed, MapSet.to_list(not_allowed)}}
    end
  end
end
