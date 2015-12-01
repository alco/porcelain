Porcelain
=========

[![Build status](https://travis-ci.org/alco/porcelain.svg "Build status")](https://travis-ci.org/alco/porcelain)
[![Hex version](https://img.shields.io/hexpm/v/porcelain.svg "Hex version")](https://hex.pm/packages/porcelain)
![Hex downloads](https://img.shields.io/hexpm/dt/porcelain.svg "Hex downloads")

Porcelain implements a saner approach to launching and communicating with
external OS processes from Elixir. Built on top of Erlang's ports, it provides
richer functionality and simpler API.

Simply put, Porcelain removes the pain of dealing with ports and substitutes it
with happiness and peace of mind.


## Overview

Having some 20 odd options, the Erlang port API can be unwieldy and cumbersome
to use. Porcelain replaces it with a simpler approach and provides defaults for
the common cases.

User-level features include:

  * sane API

  * ability to launch external programs in a synchronous or asynchronous manner

  * multiple ways of passing input to the program and getting back its output
    (including working directly with files and Elixir streams)

  * being able to work with programs that try to read the whole input until EOF
    before producing output

  * ability to send OS signals to external processes (requires goon v2.0)

To read background story on the library's design and possible future
extensions, please refer to the [wiki][].

  [wiki]: https://github.com/alco/porcelain/wiki


## Installation

Add Porcelain as a dependency to your Mix project:

```elixir
def application do
  [applications: [:porcelain]]
end

defp deps do
  [{:porcelain, "~> 2.0"}]
end
```

Now, some of the advanced functionality is provided by the external program
called `goon`. See which particular features it implements in the reference
docs [here][goon_ref]. Go to `goon`'s [project page][goon] to find out how to
install it.

  [goon_ref]: http://hexdocs.pm/porcelain/Porcelain.Driver.Goon.html
  [goon]: https://github.com/alco/goon#goon


## Usage

Examples below show some of the common use cases. See also this [demo
app][exapp]. Refer to the [API docs][ref] to familiarize yourself with the
complete set of provided functions and options.


### Launching one-off programs

If you need to launch an external program, feed it some input and capture its
output and maybe also exit status, use `exec()` or `shell()`:

```elixir
alias Porcelain.Result

%Result{out: output, status: status} = Porcelain.shell("date")
IO.inspect status   #=> 0
IO.inspect output   #=> "Fri Jun  6 14:12:02 EEST 2014\n"

result = Porcelain.shell("date | cut -b 1-3")
IO.inspect result.out   #=> "Fri\n"

# Use exec() when you want launch a program directly without using a shell
File.write!("input.txt", "lines\nread\nfrom\nfile\n")
result = Porcelain.exec("sort", ["input.txt"])
IO.inspect result.out   #=> "file\nfrom\nlines\nread\n"
```


### Passing input and getting output

Porcelain gives you many options when it comes to interacting with external
processes. It is possible to feed input from a file or a stream, same for
output:

```elixir
File.write!("input.txt", """
  This file contains some patterns
  >like this<
  interspersed with other text
  ... >like this< the end.
  """)

Porcelain.exec("grep", [">like this<", "-m", "2"],
                    in: {:path, "input.txt"}, out: {:append, "output.txt"})
IO.inspect File.read!("output.txt")
#=> ">like this<\n... >like this< the end.\n"
```


### Streams

Programs can be spawned asynchronously (using `spawn()` and `spawn_shell()`)
allowing for continuously exchanging data between Elixir and the external
process.

In the next example we will use streams for both input and output.

```elixir
alias Porcelain.Process, as: Proc

instream = SocketStream.new('example.com', 80)
opts = [in: instream, out: :stream]
proc = %Proc{out: outstream} = Porcelain.spawn("grep", ["div", "-m", "4"], opts)

Enum.into(outstream, IO.stream(:stdio, :line))
#     div {
#         div {
# <div>
# </div>

Proc.alive?(proc)   #=> false
```

Alternatively, we could pass the output stream directly to the call to
`spawn()`:

```elixir
opts = [
  in: SocketStream.new('example.com', 80),
  out: IO.stream(:stderr, :line),
]
Porcelain.exec("grep", ["div", "-m", "4"], opts)
#=> this will be printed to stderr of the running Elixir process:
#     div {
#         div {
# <div>
# </div>
```

The `SocketStream` module used above wraps a tcp socket in a stream. Its
implementation can be found in the `test/util/socket_stream.exs` file.


### Messages

If you prefer to exchange messages with the external process, you can do that:

```elixir
alias Porcelain.Process, as: Proc
alias Porcelain.Result

proc = %Proc{pid: pid} =
  Porcelain.spawn_shell("grep ohai -m 2 --line-buffered",
                                in: :receive, out: {:send, self()})

Proc.send_input(proc, "ohai proc\n")
receive do
  {^pid, :data, :out, data} -> IO.inspect data   #=> "ohai proc\n"
end

Proc.send_input(proc, "this won't match\n")
Proc.send_input(proc, "ohai")
Proc.send_input(proc, "\n")
receive do
  {^pid, :data, :out, data} -> IO.inspect data   #=> "ohai\n"
end
receive do
  {^pid, :result, %Result{status: status}} -> IO.inspect status   #=> 0
end
```


## Configuring the Goon driver

There are a number of options you can tweak to customize the way `goon` is
used. All of the options described below should be put into your `config.exs`
file.


### Setting the driver

```elixir
config :porcelain, :driver, <driver>
```

This option allows you to set a particular driver to be used at all times.

By default, Porcelain will try to detect the `goon` executable. If it can find
one, it will use `Porcelain.Driver.Goon`. Otherwise, it will print a warning to
stderr and fall back to `Porcelain.Driver.Basic`.

By setting `Porcelain.Driver.Basic` above you can force Porcelain to always
use the basic driver.

If you set `Porcelain.Driver.Goon`, Porcelain will always use the Goon driver
and will fail to start if the `goon` executable can't be found.


### Goon options

```elixir
config :porcelain, :goon_driver_path, <path>
```

Set an absolute path to the `goon` executable. If this is not set, Porcelain
will search your system's `PATH` by default.

```elixir
config :porcelain, :goon_stop_timeout, <integer>
```

This setting is used by `Porcelain.Process.stop/1`. It specifes the number of seconds `goon` will
wait for the external process to terminate before it sends `SIGKILL` to it. Default timeout is 10
seconds.

```elixir
config :porcelain, :goon_warn_if_missing, <boolean>
```

Print a warning to the console if the `goon` executable isn't found. Default: `true`.


## Going deeper

Take a look at the [reference docs][ref] for the full description of all
provided functions and supported options.

  [exapp]: https://github.com/alco/porcelain_example
  [ref]: http://hexdocs.pm/porcelain/api-reference.html


## Known issues and roadmap

  * there are known crashes happening when using Porcelain across two nodes
  * error handling when using the Goon driver is not completely shaped out


## Acknowledgements

Huge thanks to all who have been test-driving the library in production, in
particular to

  * Josh Adams
  * Tim Ruffles


## License

This software is licensed under [the MIT license](LICENSE).
