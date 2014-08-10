require 'parslet'

class Array
  def unify
    case size
    when 0; nil
    when 1; first
    else; self
    end
  end
end

class ByteString < Parslet::Atoms::Re
  def initialize
    super('.')
  end

  def try(source, context)
    success, value = super
    # value = value.to_s.unpack('n*')
    [ success, value ]
  end

  # def to_s_inner(prec)
  #   result = super
  #   binding.pry
  #   result
  # end
end

class Emitter < Parslet::Atoms::Context
  def self.queue
    @queue ||= []
  end

  def try_with_cache(obj, source)
    success, value = result = super

    case value
    when Array
      self.class.queue << value[1..-1] unless value.first == :sequence
    when Hash
      self.class.queue << value
    when String
    when nil
    end

    result
  end
end

class Parslet::Atoms::Context
  def self.new( error_reporter )
    inst = Emitter.allocate
    inst.send :initialize, error_reporter
    inst
  end
end


class HexbugParser < Parslet::Parser
  def initialize( ff = "ff" )
    @ff = ff
  end

  class Lead
    def initialize( bytes )
      @bytes = bytes
    end
  end

  def parse( *args )
    Emitter.queue.clear
    super
  end

  # def byte
  #   ByteString.new
  # end

  rule(:ff){ str @ff }
  rule(:no_activity){ ff.repeat(2,2).as(:no_activity)}
  rule(:overload){ff.repeat(3,3).as(:overload) }

  rule(:two_byte) do
    (no_activity.absent? >> any >> any)
  end

  rule(:mark){two_byte.as :mark}
  rule(:spac){two_byte.as :space}

  def long_space; spac; end

  def lead;         (mark >> spac).as :lead end
  def control_code; (mark >> spac).as :control_code end
  def command;      (mark >> spac).repeat(8,8).as :command end
  def channel;      (mark >> spac).repeat(2,2).as :channel end
  def stop;         (mark >> spac).as :stop end

  def packet
    lead >> control_code >> command >> channel >> stop
  end

  rule(:block){(overload | no_activity) | packet.as(:packet).repeat}

  root :block

  def read( st )
    transformer = Human.new
    tree = parse(st, prefix: true)
    transformer.apply tree
  end
end

if defined? Human
  Human.rules.clear
end

class Human < Parslet::Transform
  def self.gravitize( value )
    # [0, 350, 450, 550, 900, 1450, 1800].each_cons(2).flat_map{|l,h| ["when #{l}..#{(l+h)/2}; #{l}", "when #{(l+h)/2}..#{h}; #{h}"]  }
    case value
      when    0 ..  175;               0
      when  175 ..  375;             350
      when  375 ..  400;             350
      when  400 ..  450;             450
      when  450 ..  500;             450
      when  500 ..  550;             550
      when  550 ..  725;             550
      when  725 ..  900;             900
      when  900 .. 1175;             900
      when 1175 .. 1450;            1450
      when 1450 .. 1625;            1450
      when 1625 .. 1800;            1800

      # and these two weren't generated
      when (1800..2200);            1800
      when (2200..Float::INFINITY); 100000
    end
  end

  def gravitize(value) self.class.gravitize value end

  def self.sample_length
    @sample_length ||= Rational 64, 3
  end

  def sample_length
    @sample_length ||= Rational 64, 3
  end

  rule :packet => subtree(:pkt) do |blk|
    blk[:pkt].map{|k,v| Hash[k,v]}
  end

  # rule :packet => subtree(:pkt) do |blk|
  #   asocry = blk[:pkt].map do |key,value|
  #     mark_spaces =
  #     if Array === value
  #       value
  #     else
  #       [ value ]
  #     end

  #     timings = mark_spaces.map do |hash|
  #       Hash[ hash.map{|k,value| [k, value.to_s.unpack('n*').map{|v| gravitize( v * sample_length) }.unify ] } ]
  #     end

  #     [key, timings]
  #   end
  #   Hash[asocry]
  # end

  BACK_LOOKUP = {
    [1800, 450] => 'lead',
    [1800, 550] => 'lead2',
    [1800, 900] => 'control',
    [350,  550] => 0,
    [350, 1450] => 1,
    [350, 0] => 'stop',
    [350, 100000] => 'stop',
  }

  rule :mark=>simple(:m), :space=>simple(:s) do |hash|
    ry = hash.flat_map{|k,value| value.to_s.unpack('n*').map{|v| gravitize( v * sample_length) } }
    BACK_LOOKUP[ry] || hash.flat_map{|k,value| value.to_s.unpack('n*')}
  end

  rule :command => sequence(:command) do
    'bytes'
  end

  # rule( :lead => subtree(:leader)) do
  #   puts "FOUND leader"
  #   'leader'
  # end

  # rule(:command => simple(:cmd)) do
  #   require 'pry'; binding.pry
  #   cmd.unpack('n*')
  # end

  # rule(:object => subtree(:ob)) do
  #   (ob.is_a?(Array) ? ob : [ ob ]).inject({}) { |h, e| h[e.key] = e.val; h }
  # end

  # rule(:entry => { :key => simple(:ke), :val => simple(:va) }) do
  #   Entry.new(ke, va)
  # end

  # rule(:string => simple(:st)) do
  #   st.to_s
  # end

  # rule(:number => simple(:nb)) do
  #   nb.match(/[eE\.]/) ? Float(nb) : Integer(nb)
  # end
end
