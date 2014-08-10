require 'irtoy'

class Hexbug
  def initialize( irtoy )
    @irtoy = irtoy
  end

  # not used right now. But they provide some clues on how the hexbug protocol is constructed.
  HEXBUG_SPIDER_LEAD =         [1800, 450]
  HEXBUG_SPIDER_CONTROL_CODE = [1800, 900]
  SPAC = HEXBUG_SPIDER_B0 =    [350,  550]
  MARK = HEXBUG_SPIDER_B1 =    [350, 1450]
  HEXBUG_SPIDER_STOP =         [350, 0]

  # #define HEXBUG_SPIDER_SIGNAL(code)
  def signal(code)
    [HEXBUG_SPIDER_LEAD, HEXBUG_SPIDER_CONTROL_CODE, code, HEXBUG_SPIDER_CONTROLLER_ID, HEXBUG_SPIDER_STOP].flatten
  end

  # these are actually pairs of mark/space durations in µs
  #
  #   lead     control   d0      d1        d2       d3       d4      d5       d6       d7        id0      id1        stop
  # CMDS = <<-EOF
  #   (right
  #     1800 450 1800 900  350 550 350 550   350 1450 350 550  350 550 350 1450 350 1450 350 550   350 1450 350 1450   350)

  #   (back
  #     1800 450 1800 900  350 550 350 1450  350 550  350 550  350 550 350 1450 350 550  350 1450  350 1450 350 1450   350)

  #   (forward
  #     1800 450 1800 900  350 1450 350 550  350 550  350 550  350 550 350 550  350 1450 350 1450  350 1450 350 1450   350)

  #   (left
  #     1800 450 1800 900  350 1450 350 1450 350 550  350 550  350 550 350 550  350 550  350 1450  350 1450 350 1450   350)
  # EOF
  CMDS = <<-EOF
    (right
      1962 490 1962 959 383 575 383 575 383 1514 383 575 383 575 383 1535 383 1514 383 575 383 1514 383 1514 383)

    (back
      1962 490 1962 959 383 575 383 1514 383 575 383 575 383 575 383 1535 383 575 383 1514 383 1514 383 1514 383)

    (forward
      1962 490 1962 959 383 1535 383 575 383 575 383 575 383 575 383 575 383 1514 383 1535 383 1535 362 1535 383)

    (left
      1962 490 1962 959 383 1514 383 1535 362 575 383 575 383 575 383 575 383 575 383 1514 383 1514 383 1514 383)
  EOF

  def reset
    irtoy.reset.sample_mode
  end

  alias fixit reset

  def self.cmds
    Hash[SXP.read_all(CMDS).map{|name,*rest| [name,rest]}]
  end

  def cmds
    @cmds ||= self.class.cmds
  end

  alias durations cmds

  # generate the last space of the mark/space pairs. It's a long one.
  def pause
    [pause_µs / IrToy::TICK_LENGTH].pack('n')
  end

  # 100_000 µs seems to be about the pause duration between strings coming from the remote
  def pause_µs
    # seems to work well after various tries
    90_000
  end

  def cmd( name, count = 1 )
    cmdst = durations[name]
      .map{|m,s| [(m / IrToy::TICK_LENGTH), ((s / IrToy::TICK_LENGTH) rescue nil)].compact}
      .flatten.map{|e| e.to_i}.pack('n*')

    count.times{ yield cmdst + pause }
  end

  def method_missing(meth, *args, &blk)
    if durations.key? meth
      cmd meth, *args do |cmdst|
        irtoy.transmit cmdst
        # 2x pause, seems to work well after various tries.
        sleep (pause_µs * 2) / 1e6
      end
    else
      super
    end
  end
end

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

