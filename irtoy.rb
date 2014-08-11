require 'rubyserial'
require 'fastandand'
require 'sxp'
require 'rational'

class Fixnum
  def to_x
    "%0.2x" % self
  end
end

class Array
  def to_hex
    map{|xb| "%0.2x" % xb}
  end
end

class String
  def to_hex
    unpack('C*').to_hex.join(' ')
  end
end

# irtoy = IrToy port, baud = 115200
# although baud is not really necessary
# http://dangerousprototypes.com/docs/USB_Infrared_Toy
# http://dangerousprototypes.com/docs/USB_IR_Toy_firmware_update
# If it ends up in diolan boot loader, say
# ./fw_update -r -vid 0x04D8 -pid 0xFD0B -t
class IrToy < Serial
  FF = "\xff".force_encoding('ASCII-8BIT').freeze
  FULLSTOP = FF * 2
  OVERLOAD = FF * 6

  TICK_LENGTH = Rational(64,3)

  # microsecond to sample duration
  def self.µs_to_sample( ary )
    ary.map{|m,s| [(m / IrToy::TICK_LENGTH), ((s / IrToy::TICK_LENGTH) rescue nil)].compact}
  end

  def initialize( port, baud = 115200 )
    super port, Integer(baud)
  end

  # clear devicebuffer - ie read data until we get an empty read
  def clear
    until (response = read).empty?
      yield response
    end
  end

  # TODO take args, and concatenate args into a string that
  # can be passed to super.
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

  # send 0xff x 2 (in ascii-8bit) to exit transmit mode
  # send at least one 0x0 to reset the mode
  # send 5 x 0x0 to get it out of SUMP mode
  def reset
    write FULLSTOP
    write [0x0]*5
    self
  end

  # write stuff, and read response as soon as it's available.
  # mainly for debugging and pry-driving.
  def wr( stuff )
    write stuff
    wait_readable.read.to_hex
  end

  # Must be in sample_mode first.
  # Not necessary to call sample_mode before each call to this though.
  # stuff is an ascii-8bit string of bytes to send.
  # Must be pairs of msb lsb
  # FULLSTOP will be sent after stuff.
  def transmit( stuff )
    stuff = stuff.dup
    original_length = stuff.length

    # handshaking, transmit notify (C|F), transmit byte count, transmit sub-mode
    write [0x26, 0x25, 0x24, 0x03]

    while not stuff.empty?
      # reply here is how many bytes to send in next transmit
      send_bytes = wait_readable.read.unpack('C*').first
      log "send_bytes: #{send_bytes.inspect}"

      if send_bytes
        # ooh. Nasty mutable code here. Gasp.
        next_slice = stuff.slice!( 0, send_bytes)
        log "send partial bytes: #{next_slice.size}: #{next_slice.to_hex}"
      else
        # dunno how many bytes to send, so just send it all
        next_slice = stuff
        stuff = ''
      end

      next_slice << FULLSTOP if stuff.empty?
      write next_slice
    end

    # could possibly use parslet for this
    last_handshake = wait_readable.read(1)
    log "expected last handshake. Got #{last_handshake.inspect}" unless last_handshake.length == 1

    # check transmission
    t,bytes_received = wait_readable.read.unpack('an')
    log "not t: #{t.inspect}" unless t == 't'
    # + 6 for opening 4 bytes to set transmit mode, and the final 2 0xff
    # dunno, really. The bytes received number is all over the place.
    log "byte mismatch: #{original_length} != #{bytes_received}" unless original_length + 6 == bytes_received

    c = wait_readable.read
    # C is for complete, F is for underrun
    log "Not C: #{c.inspect}" unless c == 'C'
    self
  end

  def log( *args )
    @log ||= []
    @log.concat args
  end

  # put it in sample mode
  # http://dangerousprototypes.com/docs/USB_IR_Toy:_Sampling_mode
  def sample_mode
    # there may be a bunch of other stuff waiting to be read,
    # so just get it out of the way.
    loop do
      write 's'
      # MUST have blink here, otherwise wait_readable waits forever
      blink
      # actually wait_readable just seems to be in the way here.
      # wait_readable
      version_response = read
      log "version_response: #{version_response}"
      # raise "#{version_response} not S01" unless version_response == 'S01'
      break if version_response == 'S01'
    end
    self
  end

  # create wrapper and keep the IO instance around so it doesn't make the fd available
  # for something else to use. Which breaks unpleasantly, naturally enough.
  # Should really be part of rubyserial.
  def io
    @io ||= IO.for_fd(@fd)
  end

  # true if there are bytes, false otherwise.
  # Specify nil timeout to block until there is data,
  # or a value in seconds as the timeout. Default is 0.
  def read?( timeout = 0 )
    rs = IO.select [io], [], [], timeout
    return false if rs.nil?
    not rs.first.empty?
  end

  # block until there's data, then return self.
  def wait_readable(timeout=nil)
    read?(timeout)
    self
  end

  def version
    write 'v'
    wait_readable.read
  end

  def settings
    write 0x23
    rv = wait_readable.read.unpack 'C4N'
    # put it back in sample mode. Request for settings seems to end sample mode.
    sample_mode
    names = %i[pwm_pr2 duty_cycle pwm_prescaler transmit_prescaler clock_hz]
    Hash[names.zip(rv)]
  end

  # for debugging
  # pry seems to break the DATA IO object. So just do it manually.
  def self.rmsg
    @rmsg ||= begin
      contents = File.read __FILE__
      source, data = contents.split /^__END__\s*$/
      YAML.load(data).join
    end
  end

  def rmsg; self.class.rmsg; end
end

DEFAULT_IRTOY_SERIAL_DEV =
case uname = `uname`
when /Darwin/
  # '/dev/tty.usbmodem00000001'

  # The technical difference is that /dev/tty.* devices will wait (or listen)
  # for DCD (data-carrier-detect), eg, someone calling in, before responding.
  # /dev/cu.* devices do not assert DCD, so they will always connect (respond
  # or succeed) immediately.

  # So we need to use the cu device here.

  '/dev/cu.usbmodem00000001'
when /Linux/
  '/dev/ttyACM0'
else
  raise "unknown uname value #{uname}"
end

def irtoy( dev = DEFAULT_IRTOY_SERIAL_DEV )
  @irtoy ||= IrToy.new( dev ).tap do |irtoy|
    irtoy.reset.sample_mode
  end
end

# a test command. I think it might be turn-right?
__END__
---
- !binary |-
  AFoAGABaAC4AEQBJABAAHAAQABwAEAAcABEAHAAQABwAEABgABEASQAQAEkA
  EABJABAQOQBaABgAWgAuABAAHAAQABwAEAAcABEAHAAQABwAEABIABEASAAR
  AEkAEABJABAASQAQE/MAWgAYAFoALgAQABwAEAAcABAAHAAQABwAEAAcABAA
  SAARAEkAEABJABAASQAQAEkAEBP4AFoAGABaAC4AEQAcABAAHAAQABwAEAAc
  ABAAHAAQAEkAEABJABAASQAQAEkAEABJABAT+gBaABgAWgAuABEAHAAQABwA
  EAAcABAAHAAQABwAEABJABAASQAQAEkAEABJABAASQAQE/sAWgAYAFoALwAQ
  ABwAEAAcABAAHAAQABwAEAAcABAASQARAEgAEQBJABAASQAQAEkAEBP8AFoA
  GABaAC4AEQAcABAAHAAQABwAEAAcABAAHAARAEkAEABJABAASQAQAEkAEABJ
  ABAT+wBbABgAWgAuABEAHAAQABwAEAAcABEAHAAQABwAEABJABAASAARAEkA
  EABJABAASQAQE/0AWgAYAFoALgARABwAEAAcABAAHAAQABwAEAAcABAASQAQ
  AEkAEABJABEASQAQAEkAEBP8AFoAGABaAC8AEAAcABAAHAAQABwAEAAcABAA
  HAAQAEgAEQBJABAASQAQAEgAEQBJABA=
- !binary |-
  E/wAWgAYAFoALgARABwAEAAcABAAHAAQABwAEAAcABAASQAQAEgAEQBJABAA
  SQAQAEkAEBP8AFoAGABaAC8AEAAcABAAHAAQABwAEQAcABAAHAAQAEkAEABJ
  ABAASQAQAEkAEABJABET/ABaABgAWgAvABAAGwARABwAEAAcABAAHAAQABwA
  EQBJABAASQAQAEkAEABJABAASAARE/wAWgAYAFoALgARABwAEAAcABAAHAAQ
  ABwAEAAcABAASQAQAEkAEABJABAASQAQAEkAEBP8AFoAGABaAC4AEQAcABAA
  HAAQABwAEAAcABAAGwARAEkAEABJABAASQAQAEkAEABJABH//w==
- ''
