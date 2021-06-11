defmodule Surface.Components.Markdown do
  @moduledoc File.read!("README.md")

  use Surface.MacroComponent

  alias Surface.MacroComponent
  alias Surface.IOHelper

  @doc "The CSS class for the wrapping `<div>`"
  prop class, :string

  @doc "Removes the wrapping `<div>`, if `true`"
  prop unwrap, :boolean, static: true, default: false

  @doc """
  Keyword list with options to be passed down to `Earmark.as_html/2`.

  For a full list of available options, please refer to the
  [Earmark.as_html/2](https://hexdocs.pm/earmark/Earmark.html#as_html/2)
  documentation.
  """
  prop opts, :keyword, static: true, default: []

  @doc "The markdown text to be translated to HTML"
  slot default

  def expand(attributes, children, meta) do
    static_props = MacroComponent.eval_static_props!(__MODULE__, attributes, meta.caller)

    unwrap = static_props[:unwrap]
    class = Surface.AST.find_attribute_value(attributes, :class) || get_config(:default_class) || ""

    config_opts =
      case get_config(:default_opts) do
        nil -> []
        opts -> opts
      end

    opts = Keyword.merge(config_opts, static_props[:opts] || [])

    html =
      children
      |> IO.iodata_to_binary()
      |> trim_leading_space()
      |> String.replace(~S("\""), ~S("""), global: true)
      # Need to reconstruct the relative line
      |> markdown_as_html!(meta.caller, meta.line, opts)

    if unwrap do
      quote_surface do
        ~F"{^html}"
      end
    else
      quote_surface do
        ~F"<div class={^class}>{^html}</div>"
      end
    end
  end

  defp trim_leading_space(markdown) do
    lines =
      markdown
      |> String.split("\n")
      |> Enum.drop_while(fn str -> String.trim(str) == "" end)

    case lines do
      [first | _] ->
        [space] = Regex.run(~r/^\s*/, first)

        lines
        |> Enum.map(fn line -> String.replace_prefix(line, space, "") end)
        |> Enum.join("\n")

      _ ->
        ""
    end
  end

  defp markdown_as_html!(markdown, caller, tag_line, opts) do
    markdown
    |> Earmark.as_html(struct(Earmark.Options, opts))
    |> handle_result!(caller, tag_line)
  end

  defp handle_result!({_, html, messages}, caller, tag_line) do
    {errors, warnings_and_deprecations} =
      Enum.split_with(messages, fn {type, _line, _message} -> type == :error end)

    Enum.each(warnings_and_deprecations, fn {_type, line, message} ->
      actual_line = tag_line + line - 1
      IOHelper.warn(message, caller, fn _ -> actual_line end)
    end)

    if errors != [] do
      [{_type, line, message} | _] = errors
      actual_line = tag_line + line - 1
      IOHelper.compile_error(message, caller.file, actual_line)
    end

    html
  end
end
