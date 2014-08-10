require 'rubyserial'
require 'pry'
require 'fastandand'
require 'sxp'

class Fixnum
  def to_x
    "%0.2x" % self
  end
end

# irtoy = IrToy port, baud = 115200
# http://dangerousprototypes.com/docs/USB_Infrared_Toy
# http://dangerousprototypes.com/docs/USB_IR_Toy_firmware_update
class IrToy < Serial
  FF = "\xff".force_encoding('ASCII-8BIT').freeze
  QUIET = FF * 2
  OVERLOAD = FF * 6

  TICK_LENGTH = Rational(64,3)

  # microsecond to sample duration
  def self.us_to_( ary )
    ary.map{|m,s| [(m / IrToy::TICK_LENGTH), ((s / IrToy::TICK_LENGTH) rescue nil)].compact}
  end

  def initialize( port, baud = 115200 )
    super port, Integer(baud)
  end

  # clear devicebuffer - ie read data until we get an empty read
  def clear
    until (response = sp.read 1024).empty?
      yield response
    end
  end

  def write( stuff )
    case stuff
    when String
      super
    when Fixnum
      super [stuff].pack('C*')
    when Array
      super stuff.pack('C*')
    else
      raise "Dunno how to send #{stuff}"
    end
  end

  def read( buffer_size = 2048 )
    super
  end

  def blink
    # pause for a short while
    sleep 0.1
  end

  # send at least one 0x0 to reset the mode
  # send 5 x 0x0 to get it out of SUMP mode
  def reset
    write ([0x0]*5).pack('C*')
    blink
    self
  end

  def wr( stuff )
    write stuff
    blink
    read 2048
  end

  def transmit_mode
    sample_mode
    blink
    write 0x03
    blink
    self
  end

  def transmit( stuff )
    write 0x03
    blink
    write stuff
    blink
    write QUIET
  end

  # put it in sample mode
  # http://dangerousprototypes.com/docs/USB_IR_Toy:_Sampling_mode
  def sample_mode( &blk )
    loop do
      write 's'
      blink
      response = read 2048
      # raise "#{response} not S01" unless response == 'S01'
      break if response == 'S01'
    end

    if block_given?
      sample &blk
    else
      self
    end
  end

  # true if there are bytes, false otherwise.
  # Specify nil timeout to block until there is data,
  # or a value in seconds as the timeout. Default is 0.
  def read?( timeout = 0 )
    raise "borked"
    rs = IO.select [IO.for_fd(@fd)], [], [], timeout
    return false if rs.nil?
    not rs.first.empty?
  end

  def wait_read
    read?(nil)
    self
  end

  def buffer
    @buffer ||= []
  end

  def each_pulse( buffer_size: 1024, &receiver )
    return enum_for(__method__) unless block_given?
    loop do
      # we have buffered data, so return it
      if buffer.size >= 4
        yield Pulse.new(buffer.shift(4).pack('C4'))
      else
        # otherwise read from serial port
        st = read 1024
        if st.empty?
          blink
          next
        end

        # binding.pry if st.bytes.any?{|b| b == 0xff}

        if (pos = st.index(QUIET))
          # binding.pry
          # remove the marker from the buffer and then yield END
          st[pos,QUIET.length] = ''
          buffer.concat st.bytes
          yield 'END'
        else
          buffer.concat st.bytes
        end
      end
    end
  end

  def sample( yield_size: 4, buffer_size: 48 )
    return enum_for(__method__) unless block_given?

    loop do
      st = read_sample buffer_size
      yield st
    end
  end
end

require 'rational'
require 'stringio'

class Pulse
  # pass in 4 bytes
  def initialize( byte_string )
    # raise "not 4 bytes" if byte_string.length != 4

    # 16-bit unsigned, network (big-endian) byte order
    # byte_string.unpack 'n*'

    # 16-bit unsigned, VAX (little-endian) byte order
    # byte_string.unpack 'v*'

    # 8-bit unsigned
    # byte_string.unpack 'C*'

    case byte_string
    when String
      @on_sample, @off_sample = byte_string.unpack 'n2'
    when Array
      if byte_string.all?{|e| e.is_a? Fixnum}
        raise "should handle durations"
      end
    end
  end

  attr_reader :on_sample, :off_sample

  # in um microseconds
  def on
    on_sample * tick_length
  end

  # in um microseconds
  def off
    off_sample * tick_length
  end

  def inspect
    "(%8s)" % "#{on},#{off}" rescue "{#{on_sample},#{off_sample}}"
  end

  alias to_s inspect

  def each( &blk )
    [on_sample,off_sample].each &blk
  end
  include Enumerable

  def as_hex
    map{|b|"%0.4x" % b}.join(',')
  end

  def as_dec
    map{|b|"%0.3d" % b}.join(' ')
  end
end

DEFAULT_SERIAL_DEV =
case uname = `uname`
when /Darwin/
  # '/dev/tty.usbmodem00000001'

  # The technical difference is that /dev/tty.* devices will wait (or listen)
  # for DCD (data-carrier-detect), eg, someone calling in, before responding.
  # /dev/cu.* devices do not assert DCD, so they will always connect (respond
  # or succeed) immediately.

  # So we need to use the cu device here

  '/dev/cu.usbmodem00000001'
when /Linux/
  '/dev/ttyACM0'
else
  raise "unknown uname value #{uname}"
end

def irtoy( dev = DEFAULT_SERIAL_DEV )
  @irtoy ||= IrToy.new( dev ).tap do |irtoy|
    irtoy.reset.sample_mode
  end
end

def record
  irtoy.each_pulse( buffer_size: 1024).each_slice(13) do |pulse|
    if pulse.is_a? String
      STDOUT.print pulse
      STDOUT.flush
    else
      STDOUT.print pulse, ' '
    end
    STDOUT.puts "\n"

    irtoy.buffer.clear
  end
end

def rmsg
  @rmsg ||= YAML.load_file( 'one_read.yml').join
end

class Hexbug
  def initialize( irtoy )
    @irtoy = irtoy
  end

  HEXBUG_SPIDER_LEAD =         [1800, 450]
  HEXBUG_SPIDER_CONTROL_CODE = [1800, 900]
  SPAC = HEXBUG_SPIDER_B0 =    [350,  550]
  MARK = HEXBUG_SPIDER_B1 =    [350, 1450]
  HEXBUG_SPIDER_STOP =         [350, 0]

  # #define HEXBUG_SPIDER_SIGNAL(code)
  def signal(code)
    [HEXBUG_SPIDER_LEAD, HEXBUG_SPIDER_CONTROL_CODE, code, HEXBUG_SPIDER_CONTROLLER_ID, HEXBUG_SPIDER_STOP].flatten
  end

  #   lead     control   d0      d1        d2       d3       d4      d5       d6       d7        id0      id1        stop
  CMDS = <<-EOF
    (right
      1800 450 1800 900  350 550 350 550   350 1450 350 550  350 550 350 1450 350 1450 350 550   350 1450 350 1450   350)

    (back
      1800 450 1800 900  350 550 350 1450  350 550  350 550  350 550 350 1450 350 550  350 1450  350 1450 350 1450   350)

    (forward
      1800 450 1800 900  350 1450 350 550  350 550  350 550  350 550 350 550  350 1450 350 1450  350 1450 350 1450   350)

    (left
      1800 450 1800 900  350 1450 350 1450 350 550  350 550  350 550 350 550  350 550  350 1450  350 1450 350 1450   350)
  EOF
  # CMDS = <<-EOF
  #   (right
  #     1962 490 1962 959 383 575 383 575 383 1514 383 575 383 575 383 1535 383 1514 383 575 383 1514 383 1514 383)

  #   (back
  #     1962 490 1962 959 383 575 383 1514 383 575 383 575 383 575 383 1535 383 575 383 1514 383 1514 383 1514 383)

  #   (forward
  #     1962 490 1962 959 383 1535 383 575 383 575 383 575 383 575 383 575 383 1514 383 1535 383 1535 362 1535 383)

  #   (left
  #     1962 490 1962 959 383 1514 383 1535 362 575 383 575 383 575 383 575 383 575 383 1514 383 1514 383 1514 383)
  # EOF

  def reset
    irtoy.reset.transmit_mode
  end

  def self.cmds
    Hash[SXP.read_all(CMDS).map{|name,*rest| [name,rest]}]
  end

  def cmds
    @cmds ||= self.class.cmds
  end

  alias durations cmds

  # 100000 us seems to be the pause duration between strings coming from the remote
  def pause
    @pause ||= [100000 / IrToy::TICK_LENGTH].pack('n')
  end

  def cmd( name, count = 1 )
    cmdst = durations[name]
      .map{|m,s| [(m / IrToy::TICK_LENGTH), ((s / IrToy::TICK_LENGTH) rescue nil)].compact}
      .flatten.map{|e| e.to_i}.pack('n*')

    (cmdst + pause) * count
  end

  def method_missing(meth, *args, &blk)
    if durations.key? meth
      irtoy.transmit cmd(meth, *args)
    else
      super
    end
  end

  def fix
    irtoy.reset.sample_mode
  end
end

# record

# irtoy.close

__END__

http://www.avergottini.com/2012/02/hexbot-arduino-netduino-wireless-ir.html

int fwd[] =   {2000, 450, 1950, 950, 450, 1450, 450, 500, 500, 450,  500, 500, 450, 1450, 450, 500,  500, 1400, 500,  1450, 450, 1450, 450, 500,  500};
int lft[] =   {2050, 400, 2050, 850, 500, 450,  500, 500, 450, 1450, 450, 500, 500, 1400, 500, 1400, 500, 1450, 450,  500,  450, 1450, 500, 450,  500};
int right[] = {1962, 490, 1962, 959, 383, 575,  383, 575, 383, 1514, 383, 575, 383, 575,  383, 1535, 383, 1514, 383,  575,  383, 1514, 383, 1514, 383};
int up[] =    {2048, 384, 2048, 874, 406, 1514, 406, 533, 427, 554,  427, 533, 427, 1493, 406, 554,  427, 1493, 427,  1493, 406, 1493, 427, 533,  427};

---

http://www.ragingcomputer.com/2012/03/hexbug-lirc-control

irsend send_once hexbug left
irsend send_once hexbug right
irsend send_start hexbug forward
sleep 1
irsend send_stop hexbug forward
Advertisement:

LIRC configuration file. You’ll need to add an include line to /etc/lirc/lircd.conf

raging@mythbuntu:~$ cat hexbug.conf

# Please make this file available to others
# by sending it to #
# this config file was automatically generated
# using lirc-0.9.0(default) on Sun Mar 4 12:47:28 2012
#
# contributed by
#
# brand: hexbug
# model no. of remote control:
# devices being controlled by this remote:
#

# Raw Codes Section
#
# A button description begins with the parameter name and followed by the name
# of the button. The button description ends with the next button description or
# the end of the raw_codes block. The lines in between consist of a list of
# decimal numbers describing the signal sent by that button. The first number
# indicates the duration of the first pulse in microseconds. The second number
# indicates the duration of the space which follows it. Pulse and space
# durations alternate for as long as is necessary. The last duration should
# represent a pulse.

# from http://winlirc.sourceforge.net/technicaldetails.html

begin remote

name hexbug
flags RAW_CODES|CONST_LENGTH
eps 30
aeps 100

gap 100000

begin raw_codes

(right
 1962 490 1962 959 383 575 383 575 383 1514 383 575 383 575 383 1535 383 1514 383 575 383 1514 383 1514 383)

(back
 1962 490 1962 959 383 575 383 1514 383 575 383 575 383 575 383 1535 383 575 383 1514 383 1514 383 1514 383)

(forward
 1962 490 1962 959 383 1535 383 575 383 575 383 575 383 575 383 575 383 1514 383 1535 383 1535 362 1535 383)

(left
 1962 490 1962 959 383 1514 383 1535 362 575 383 575 383 575 383 575 383 575 383 1514 383 1514 383 1514 383)

end raw_codes

end remote

