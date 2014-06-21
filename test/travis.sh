#/bin/sh

export PATH=`pwd`/elixir-$ELIXIR_VERSION/bin:$PATH

echo $PATH
elixir -v
mix test --trace --include localbin
