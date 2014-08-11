# Irtoy-Hexbug-Spider

The kids each have a [Hexbug Spider](http://www.hexbug.com/mechanical/spider/).

In a fit of enthusiasm, I decided it would be a good idea to
get an [IR transceiver](http://dangerousprototypes.com/docs/USB_IR_Toy_v2)
to control the spiders.
Which turned out to be quite hard because lirc doesn't support the irtoy, and IR comms
(at least for the Hexbug Spider) are highly timing-sensitive.

This is the result:

- a parser (using [Parslet](http://kschiess.github.io/parslet/))
  to split up the incoming ir pulses into hexbug commands so
  we can reverse-engineer the protocol

- a wrapper for [rubyserial](https://github.com/hybridgroup/rubyserial)
  serial port which does handshaking transmission
  otherwise the irtoy overloads, and the spider overloads, and commands get lost.
  And which makes the serial port a bit easier to read/write from pry.

- a high-level hexbug controller which accepts methods ```forward```, ```back```, ```left```, ```right```.
  So that kids can type stuff and see things happen.

- IR command pulse trains are specified using [s-expressions](https://github.com/bendiken/sxp-ruby), which seemed like the
  lightest-weight? lightweightest? syntax for them.

Developed on a linux box, mildly tested on osx.

## Installation

git clone https://github.com/djellemah/irtoy-hexbug-spider

## Usage

$ rake pry

[1] pry(main)> cd Hexbug.new irtoy

[2] pry(\#\<Hexbug\>):1> forward 3

\# your irtoy lights will flash (you'll only see one), and your spider should now take 3 'steps' forward.

## TODO

Lots, as is normal in a day-scale hobby project:

- I haven't figure out the granularity of the commands. That is, the remote will send
  really short commands but I can't see how to do that.

- Only talks on channel A. The channel B command tags aren't hard, just not implemented.

- parser has too much dead code.
