defmodule Porcelain.Mixfile do
  use Mix.Project

  def project do
    [app: :porcelain,
     version: "1.0.0-alpha",
     elixir: "~> 0.13.3 or ~> 0.14.0",
     docs: docs]
  end

  # Configuration for the OTP application
  def application do
    []
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
