class Endian
  
  if  "\0\1".unpack("s").first == 1
    @@big = true
    @@little = false
  elsif "\0\1".unpack("s").first != 1
    @@little = true
    @@big = false
  else
    raise("This computer is neither big or little endian!")
  end
  
  def self.big?
    @@big
  end
  
  def self.little?
    @@little
  end
  
  def self.select(array)
    if Endian.little? then return array[0] end
    return array[1]
  end
  
  def self.set(endian)
    if  endian == :big
      @@big = true
      @@little = false
    elsif endian == :little
      @@little = true
      @@big = false
    else
      raise("Invalid endian type \"#{endian}\".")
    end
  end
  
end

class ISO
  
  attr_reader :root
  attr_reader :stream
  attr_reader :descriptors
  attr_reader :primary_volume_descriptor
  attr_reader :lba_size
  
  def initialize(stream, offset = 0x8000)
    load(stream, offset)
  end
  
  def load(stream, offset = 0x8000)
    @stream = stream
    @stream.pos = offset
    
    descriptor = nil
    @descriptors = []
    
    while true
      if @primary_volume_descriptor != nil
        table = VolumeDescriptor::PathTable.new()
        table_size = @primary_volume_descriptor.path_table_size
        
        while @primary_volume_descriptor.path_table_positions.include?(@stream.pos)
          table.load(@stream, table_size)
        end
      end
      
      descriptor = VolumeDescriptor.get(@stream)
      
      if descriptor.type == :primary
        @primary_volume_descriptor = descriptor
        @root = descriptor.root
        @lba_size = descriptor.lba_size
      end
      
      @descriptors.push(descriptor)
      
      break if descriptor.type == :terminator
    end
  end
  
  def dump(stream, offset = 0x8000)
    
  end
  
  class Directory
    
    attr_reader :position
    attr_reader :lba_size
    
    def initialize(stream = nil, lba_size = 0x800)
      @lba_size = lba_size
      
      if stream == nil
        @position = 0
        return
      end
      
      load(stream)
    end
    
    def load(stream)
      @stream = stream
      @position = stream.pos
      @entries = {}
      
      @entry = Entry.new(@stream)
      
      if @entry.directory? != true
        raise("Cannot load an entry that isn't a directory.")
      end
      
      start_of_entries = @entry.extent_lba * @lba_size
      end_of_entries = start_of_entries + @entry.data_length
      
      pos = stream.pos
      stream.pos = start_of_entries
      
      while stream.pos < end_of_entries
        length = stream.read(1).unpack("C")[0]
        stream.pos -= 1
        if length <= 0
          bytes_left = end_of_entries - stream.pos
          #end the loop if the space remaining in the entry list is less than one block
          #this means the rest of the space is just padding
          if bytes_left < @lba_size
            break
          end
          #continue to the next block if there is padding at the end of the current block
          stream.pos += bytes_left % @lba_size
        end
        
        entry = Entry.new(@stream)
        @entries[entry.file_identifier] = entry
      end


      stream.pos = pos
    end
    
    def dump(stream)
      
    end
    
    def [](identifier)
      entry = @entries[identifier]
      if entry == nil then return nil end
      
      pos = @stream.pos
      @stream.pos = entry.position
      
      directory = Directory.new(@stream)

      @stream.pos = pos
      
      return directory
    end
    
    def entry(identifier = nil)
      if identifier == nil then return @entry end
      return @entries[identifier]
    end
    
    def entries
      return @entries.keys
    end
  
    class Entry
      
      attr_reader :position
      attr_reader :extended_attribute_length #extended attributes are located at the beginning of the file
      attr_accessor :extent_lba
      attr_accessor :data_length
      attr_reader :time
      attr_reader :flags
      attr_reader :pad_data
      
      FLAGS = {
        :hidden => 0x01,
        :directory => 0x02,
        :associated_file => 0x04,
        :extended_attribute_format_information => 0x08,
        :extended_attribute_permissions => 0x10,
        :not_final_entry => 0x80
      }
      
      def initialize(stream = nil)
        if stream != nil
          load(stream)
        end
      end
      
      def load(stream)
        @position = stream.pos
        length = stream.read(1).unpack("C")[0]
        stream.pos = @position
        
        if length < 34
          #we'll assume if the length of the entry is less than what's allowed,
          #we're trying to read something that's not an entry
          raise("Directory entry not found.")
        end
        
        buffer = stream.read(length)
        
        @extended_attribute_length = buffer[1..1].unpack("C")[0]
        @extent_lba = Endian.select( buffer[2...10].unpack("VN") )
        @data_length = Endian.select( buffer[10...18].unpack("VN") )
        @time = buffer[18...25]
        
        flags = buffer[25..25].unpack("C")[0]
        @flags = []
        FLAGS.each do | flag, value |
          if flags & value != 0 then @flags.push(flag) end
        end
        
        @interleaved_unit_size = buffer[26..26].unpack("C")[0]
        @interleaved_gap_size = buffer[27..27].unpack("C")[0]
        @volume_sequence_number = Endian.select( buffer[28...32].unpack("vn") )
        
        file_identifier_length = buffer[32..32].unpack("C")[0]
        file_identifier_end = 33 + file_identifier_length
        @file_identifier = buffer[33...file_identifier_end]
        #if the length left in the entry leaves data unaccounted for, we'll preserve it in a padding field
        #first though, we'll subtract a byte from the begging of the padding if the file identifier is even
        #this is because the specifications say that this byte must be nothing but a null padding byte no matter what
        if file_identifier_length % 2 == 0
          file_identifier_end += 1
        end
        @pad_data = buffer[file_identifier_end...length]
        
        if length % 2 != 0 then stream.pos += 1 end
        
        return self
      end
      
      def dump(stream)
        buffer = []
        
        buffer << self.length
        buffer << @extended_attribute_length
        buffer += [@extent_lba, @extent_lba]
        buffer += [@data_length, @data_length]
        buffer << @time
        flags = 0
        @flags.each do | flag |
          value = FLAGS[flag]
          flags = flags | value
        end
        buffer << flags
        buffer << @interleaved_unit_size
        buffer << @interleaved_gap_size
        buffer += [@volume_sequence_number, @volume_sequence_number]
        file_identifier = @file_identifier
        if file_identifier.length % 2 == 0 then file_identifier = file_identifier + "\0" end
        buffer << @file_identifier.length
        
        buffer = buffer.pack("CCVNVNA7CCCvnC")
        buffer += file_identifier
        buffer += @pad_data
        
        stream.write(buffer)
        
        return self
      end
      
      def length
        #account for the padding byte of the file identifier
        file_identifier_length = @file_identifier.length
        if file_identifier_length % 2 == 0 then file_identifier_length += 1 end
        #33 is the length of the fixed length portion of the entry field
        return 33 + file_identifier_length + @pad_data.length
      end
      
      def file_identifier
        if @file_identifier == "\000"
          return "."
        elsif @file_identifier == "\001"
          return ".."
        else
          return @file_identifier
        end
      end
      
      def hidden?
        return @flags.include?(:hidden)
      end
      
      def directory?
        return @flags.include?(:directory)
      end
      
    end
    
  end
  
  class VolumeDescriptor
    
    attr_reader :position
    
    def initialize(stream = nil)
      if stream != nil
        load(stream)
      end
    end
    
    def load(stream)
      @position = stream.pos
      buffer = stream.read(6)
      stream.pos = @position
      type, identifier = buffer.unpack("CA5")
      
      if type != self.type(true)
        raise("Incorrect descriptor type \"#{type}\".")
      end
      
      if identifier != "CD001"
        raise("Unknown descriptor identifier \"#{identifier}\".")
      end
      
      return self
    end
    
    def self.get(stream)
      pos = stream.pos
      buffer = stream.read(6)
      stream.pos = pos
      type, identifier = buffer.unpack("CA5")
      
      if identifier != "CD001"
        raise("Unknown descriptor identifier \"#{identifier}\".")
      end
      
      descriptor = nil
      
      case type
      when 0x00
        descriptor = Boot.new()
      when 0x01
        descriptor = Primary.new()
      when 0x02
        descriptor = Supplementary.new()
      when 0x03
        descriptor = Partition.new()
      when 0xFF
        descriptor = Terminator.new()
      end
      
      return descriptor.load(stream)
    end
    
    class Boot < VolumeDescriptor
      
      def type(number = false)
        if number == true then return 0x00 end
        return :boot
      end
      
      def load(stream)
        super(stream)
        stream.pos += 0x800
        
        return self
      end
      
    end
    
    class Primary < VolumeDescriptor
      
      attr_reader :root
      attr_reader :lba_size
      attr_reader :path_table
      attr_reader :path_table_size
      attr_reader :path_table_positions
    
      def type(number = false)
        if number == true then return 0x01 end
        return :primary
      end
      
      def load(stream)
        super(stream)
        buffer = stream.read(0x800)
        
        @lba_size = Endian.select( buffer[128...132].unpack("vn") )
        
        @path_table_size = Endian.select( buffer[132...140].unpack("VN") )
        
        path_table_little_pos = buffer[140...144].unpack("V")[0] * @lba_size
        path_table_little_pos_optional = buffer[144...148].unpack("V")[0] * @lba_size
        path_table_big_pos = buffer[148...152].unpack("N")[0] * @lba_size
        path_table_big_pos_optional = buffer[152...156].unpack("N")[0] * @lba_size
        
        path_table_pos = Endian.select( [path_table_little_pos, path_table_big_pos] )
        
        #load the appropriate path table from the stream
        pos = stream.pos
        stream.pos = path_table_pos
        
        @path_table = PathTable.new(stream, path_table_size)
        
        stream.pos = pos
        
        #we'll now record all the path table locations in a single array, so we can later check for them inbetween descriptors
        #this is done because I'm fairly sure the iso 9660 specs don't say path tables between descriptors aren't allowed
        @path_table_positions = []
        @path_table_positions.push(path_table_little_pos)
        if path_table_little_pos_optional != 0
          @path_table_positions.push(path_table_little_pos_optional)
        end
        @path_table_positions.push(path_table_big_pos)
        if path_table_big_pos_optional != 0
          @path_table_positions.push(path_table_big_pos_optional)
        end
        
        #read the root directory entry
        pos = stream.pos
        stream.pos = @position + 156
        
        @root = Directory.new(stream, @lba_size)
        
        stream.pos = pos
        
        return self
      end
      
    end
    
    class Supplementary < Primary
    
      def type(number = false)
        if number == true then return 0x02 end
        return :supplementary
      end
      
      def load(stream)
        super(stream)
        stream.pos += 0x800
        
        return self
      end
      
    end
    
    class Partition < VolumeDescriptor
    
      def type(number = false)
        if number == true then return 0x03 end
        return :partition
      end
      
      def load(stream)
        super(stream)
        stream.pos += 0x800
        
        return self
      end
      
    end
    
    class Terminator < VolumeDescriptor
      
      def type(number = false)
        if number == true then return 0xFF end
        return :terminator
      end
      
      def load(stream)
        super(stream)
        stream.pos += 0x800
        
        return self
      end
      
    end
    
    class PathTable < Array
      
      attr_accessor :endian
      
      def initialize(stream = nil, length = nil, endian = nil)
        if endian == nil then endian = Endian.little? ? :little : :big end
        @endian = endian
        
        if stream != nil
          load(stream, length)
        end
      end
      
      def load(stream, length)
        length += 0x400 - (length % 0x400)
        stream.pos +=  length
        
        return self
      end
      
      class Entry
        
      end
      
    end
    
  end
  
end