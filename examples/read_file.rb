require "iso9660"

#open the iso image
stream = File.open("example.iso", "rb")
#ISO.new also accepts a second argument that allows you to specify to offset of the ISO 9660 header in the file
#there is rarely any need to use this, but it may be helpful for reading standalone ISO headers or non-standard confoming files
iso = ISO.new(stream)

#open the folder the file is in
dir = iso.root["test"]

#get the entry for the file
entry = dir.entry("test.file")
if entry.directory?
  raise("test.file is not a file!")
end

#seek to the position of the file. since the position is an LBA, we have to
#multiply it by the ISO's LBA size to get the actual file position
stream.pos = entry.extent_lba * iso.lba_size

#read the data into a buffer
buffer = stream.read(entry.data_length)
#we can now use the buffer object to see what's in the file

#...or we can extract the file to our hard drive to do yet more stuff with it
output = File.new("test.file", "wb")
output.write(buffer)