defmodule Porcelain.Mixfile do
  use Mix.Project

  def project do
    [
      app: :porcelain,
      version: "2.0.3",
      elixir: ">= 0.14.3 and < 2.0.0",
      deps: deps(),
      description: description(),
      docs: docs(),
      package: package(),
    ]
  end

  def application do
    [
      applications: [:logger, :crypto],
      mod: {Porcelain.App, []},
    ]
  end

  def docs do
    [
      extras: [{"README.md", title: "Readme"}],
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
      maintainers: ["Alexei Sholik"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/alco/porcelain",
      }
    ]
  end

  defp deps do
    [
      {:earmark, "> 0.0.0", only: :dev},
      {:ex_doc, "> 0.0.0", only: :dev},
    ]
  end
end
