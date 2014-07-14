defmodule Porcelain.Mixfile do
  use Mix.Project

  def project do
    [
      app: :porcelain,
      version: "1.1.0",
      elixir: "~> 0.14.3",
      docs: docs,
      description: description,
      package: package,
    ]
  end

  def application do
    [mod: {Porcelain.App, []}]
  end

  def docs do
    [
      formatter: "sphinx",
      #highlighter: :"highligh.js" | :"pygments",
      readme: true,

      formatter_opts: [
        gen_overview: false,
        pygments_style: "emacs",
        html_theme: "pyramid",
        html_type: "singlehtml"
      ]
    ]
  end

  defp description do
    "Porcelain implements a saner approach to launching and communicating " <>
    "with external OS processes from Elixir. Built on top of Erlang's ports, " <>
    "it provides richer functionality and simpler API."
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "CHANGELOG.md", "LICENSE"],
      contributors: ["Alexei Sholik"],
      licenses: ["MIT"],
      links: %{
        "Documentation" => "http://porcelain.readthedocs.org",
        "GitHub" => "https://github.com/alco/porcelain",
      }
    ]
  end

  # no deps
  # --alco
end
