defmodule Porcelain.Mixfile do
  use Mix.Project

  def project do
    [app: :porcelain,
     version: "1.0.0-beta",
     elixir: "~> 0.13.3 or ~> 0.14.0",
     docs: docs]
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

  # no deps
  # --alco
end
