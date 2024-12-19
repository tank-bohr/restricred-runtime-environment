defmodule RestrictedRuntime.Filter do
  @moduledoc false
  @spec remote_function_calls(list()) :: MapSet.t()
  def remote_function_calls(forms) do
    traverse_forms(forms, MapSet.new())
  end

  defp traverse_forms(forms, acc) do
    forms
    |> Enum.filter(&function_form?/1)
    |> Enum.reduce(acc, &analyze_function/2)
  end

  defp function_form?({:function, _anno, _name, _arity, _clauses}), do: true
  defp function_form?(_some_form), do: false

  defp analyze_function({:function, _anno, _name, _arity, clauses}, acc),
    do: Enum.reduce(clauses, acc, &analyze_clause/2)

  defp analyze_clause({:clause, _anno, head, _guard, exprs}, acc) do
    acc = Enum.reduce(head, acc, &analyze_pattern/2)
    Enum.reduce(exprs, acc, &analyze_expr/2)
  end

  defp analyze_expr({:cons, _anno, head, tail}, acc),
    do: analyze_expr(tail, analyze_expr(head, acc))

  defp analyze_expr({tag, _anno, comprehension_qualifiers, expr}, acc) when tag in ~w[lc bc mc]a,
    do:
      analyze_expr(
        expr,
        Enum.reduce(comprehension_qualifiers, acc, &analyze_comprehension_qualifier/2)
      )

  defp analyze_expr({:tuple, _anno, exprs}, acc), do: Enum.reduce(exprs, acc, &analyze_expr/2)

  defp analyze_expr({:map, _anno, exprs}, acc), do: Enum.reduce(exprs, acc, &analyze_expr/2)

  defp analyze_expr({:map, _anno, map, exprs}, acc),
    do: analyze_expr(map, Enum.reduce(exprs, acc, &analyze_expr/2))

  defp analyze_expr({:map_field_assoc, _anno, key, value}, acc),
    do: analyze_expr(value, analyze_expr(key, acc))

  defp analyze_expr({:map_field_exact, _anno, key, value}, acc),
    do: analyze_expr(value, analyze_expr(key, acc))

  defp analyze_expr({:record_index, _anno, _name, field}, acc), do: analyze_expr(field, acc)

  defp analyze_expr({:record_field, _anno, record, _name, field}, acc),
    do: analyze_expr(field, analyze_expr(record, acc))

  defp analyze_expr({:record_field, _anno, record, field}, acc),
    do: analyze_expr(field, analyze_expr(record, acc))

  defp analyze_expr({:record, _anno, _name, inits}, acc),
    do: Enum.reduce(inits, acc, &analyze_record_field/2)

  defp analyze_expr({:record, _anno, record, _name, updates}, acc),
    do: analyze_expr(record, Enum.reduce(updates, acc, &analyze_record_field/2))

  defp analyze_expr({:block, _anno, exprs}, acc), do: Enum.reduce(exprs, acc, &analyze_expr/2)

  defp analyze_expr({:if, _anno, clauses}, acc), do: Enum.reduce(clauses, acc, &analyze_clause/2)

  defp analyze_expr({:case, _anno, expr, clauses}, acc),
    do: analyze_expr(expr, Enum.reduce(clauses, acc, &analyze_clause/2))

  defp analyze_expr({:receive, _anno, clauses}, acc),
    do: Enum.reduce(clauses, acc, &analyze_clause/2)

  defp analyze_expr({:receive, _anno, clauses, timeout, timeout_exprs}, acc) do
    acc = analyze_expr(timeout, acc)
    acc = Enum.reduce(timeout_exprs, acc, &analyze_expr/2)
    Enum.reduce(clauses, acc, &analyze_clause/2)
  end

  defp analyze_expr({:try, _anno, exprs, clauses, catch_clauses, after_exprs}, acc) do
    acc = Enum.reduce(clauses, acc, &analyze_clause/2)
    acc = Enum.reduce(catch_clauses, acc, &analyze_clause/2)
    acc = Enum.reduce(after_exprs, acc, &analyze_expr/2)
    Enum.reduce(exprs, acc, &analyze_expr/2)
  end

  defp analyze_expr({:fun, _anno, {:clauses, clauses}}, acc),
    do: Enum.reduce(clauses, acc, &analyze_clause/2)

  # local function
  defp analyze_expr({:fun, _anno, {:function, _function, _arity}}, acc), do: acc

  # MFA
  defp analyze_expr(
         {:fun, _anno,
          {:function, {:atom, _mod_anno, module}, {:atom, _fun_anno, function},
           {:integer, _arity_anno, arity}}},
         acc
       ),
       do: MapSet.put(acc, {module, function, arity})

  defp analyze_expr({:fun, _anno, {:function, _module_expr, _function_expr, _arity_expr}}, acc),
    do: MapSet.put(acc, :dynamic_lambda)

  defp analyze_expr({:named_fun, _anno, _name, clauses}, acc),
    do: Enum.reduce(clauses, acc, &analyze_clause/2)

  # remote call
  defp analyze_expr(
         {:call, _anno,
          {:remote, _remote_anno, {:atom, _mod_anno, module}, {:atom, _fun_anno, function}},
          args},
         acc
       ) do
    acc = Enum.reduce(args, acc, &analyze_expr/2)
    arity = length(args)
    MapSet.put(acc, {module, function, arity})
  end

  defp analyze_expr(
         {:call, _anno, {:remote, _remote_anno, _module_expr, _function_expr}, _args},
         acc
       ) do
    MapSet.put(acc, :dynamic_function_call)
  end

  # local call
  defp analyze_expr({:call, _anno, function, args}, acc),
    do: analyze_expr(function, Enum.reduce(args, acc, &analyze_expr/2))

  defp analyze_expr({:catch, _anno, exprs}, acc), do: Enum.reduce(exprs, acc, &analyze_expr/2)

  defp analyze_expr({:maybe, _anno, exprs}, acc), do: Enum.reduce(exprs, acc, &analyze_expr/2)

  defp analyze_expr({:maybe, _anno, exprs, {:else, _else_anno, clauses}}, acc) do
    acc = Enum.reduce(clauses, acc, &analyze_clause/2)
    Enum.reduce(exprs, acc, &analyze_expr/2)
  end

  defp analyze_expr({match, _anno, pattern, expr}, acc) when match in ~w[maybe_match match]a,
    do: analyze_expr(expr, analyze_pattern(pattern, acc))

  defp analyze_expr({:bin, _anno, bin_elements}, acc),
    do: Enum.reduce(bin_elements, acc, &analyze_bin_element/2)

  defp analyze_expr({:op, _anno, _operand, arg}, acc), do: analyze_expr(arg, acc)

  defp analyze_expr({:op, _anno, _operand, left, right}, acc),
    do: analyze_expr(left, analyze_expr(right, acc))

  defp analyze_expr({tag, _anno, _value}, acc)
       when tag in ~w[var integer char float atom string]a,
       do: acc

  defp analyze_expr({nil, _anno}, acc), do: acc

  defp analyze_comprehension_qualifier({tag, _anno, patterns, expr}, acc)
       when tag in ~w[generate b_generate m_generate]a,
       do: analyze_expr(expr, Enum.reduce(patterns, acc, &analyze_pattern/2))

  defp analyze_comprehension_qualifier(expr, acc), do: analyze_expr(expr, acc)

  defp analyze_pattern({:match, _anno, left, right}, acc),
    do: analyze_pattern(left, analyze_pattern(right, acc))

  defp analyze_pattern({:cons, _anno, head, tail}, acc),
    do: analyze_pattern(head, analyze_pattern(tail, acc))

  defp analyze_pattern({tag, _anno, patterns}, acc) when tag in ~w[tuple map]a,
    do: Enum.reduce(patterns, acc, &analyze_pattern/2)

  defp analyze_pattern({:map_field_exact, _anno, key, value}, acc),
    do: analyze_pattern(value, analyze_expr(key, acc))

  defp analyze_pattern({:record, _anno, _name, pattern_fields}, acc),
    do: Enum.reduce(pattern_fields, acc, &analyze_pattern_field/2)

  defp analyze_pattern({:record_index, _anno, _name, field}, acc),
    do: analyze_pattern(field, acc)

  defp analyze_pattern({:record_field, _anno, record, _name, field}, acc),
    do: analyze_expr(field, analyze_expr(record, acc))

  defp analyze_pattern({:record_field, _anno, record, field}, acc),
    do: analyze_expr(field, analyze_expr(record, acc))

  defp analyze_pattern({:bin, _anno, bin_elements}, acc),
    do: Enum.reduce(bin_elements, acc, &analyze_bin_element/2)

  defp analyze_pattern({:op, _anno, _operand, _arg}, acc), do: acc

  defp analyze_pattern({:op, _anno, _operand, _left, _right}, acc), do: acc

  defp analyze_pattern({tag, _anno, _value}, acc)
       when tag in ~w[var integer char float atom string]a,
       do: acc

  defp analyze_pattern({nil, _anno}, acc), do: acc

  defp analyze_pattern_field({:record_field, _anno, {:atom, _field_anno, _field}, pattern}, acc),
    do: analyze_pattern(pattern, acc)

  defp analyze_pattern_field({:record_field, _anno, {:var, _field_anno, :_}, pattern}, acc),
    do: analyze_pattern(pattern, acc)

  defp analyze_bin_element({:bin_element, _anno, expr, :default, _bit_types}, acc),
    do: analyze_expr(expr, acc)

  defp analyze_bin_element({:bin_element, _anno, expr, size, _bit_types}, acc),
    do: analyze_expr(expr, analyze_expr(size, acc))

  defp analyze_record_field({:record_field, _anno, {:atom, _field_anno, _field}, expr}, acc),
    do: analyze_expr(expr, acc)

  defp analyze_record_field({:record_field, _anno, {:var, _field_anno, :_}, expr}, acc),
    do: analyze_expr(expr, acc)
end
