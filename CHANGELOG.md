Changelog
=========

## v2.0.3 - Nov 10, 2016

  * Add `:crypto` to the application list

## v2.0.0 - Aug 20, 2014

  * Fix a mistake in the message format used for sending output from the
    external process. The old format was

        {<pid>, :data, <data>}

    the new format is

        {<pid>, :data, :out | :err, <data>}

  * Add support for sending OS signals to external processes


## v1.1.3 - Aug 18, 2014

  * Fix issues with sending large inputs. There was a related issue in goon, so
    you'll need to update it to v1.0.2.


## v1.1.2 - Aug 4, 2014

  * support Elixir versions 0.14.3 up to 2.0.0


## v1.1.1 - Jul 14, 2014

  * add missing type for the `Result` struct (minor change)


## v1.1.0 - Jul 14, 2014

  * support files opened in raw mode for input and output
  * update for Elixir v0.14.3 by adding type definition for the `Process`
    struct


## v1.0.0 – Jun 21, 2014

  * initial release on hex.pm


## v1.0.0-beta – Jun 19, 2014

  * initial release
