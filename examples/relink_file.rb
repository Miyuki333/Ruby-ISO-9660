require "iso9660"

#open the iso image
stream = File.open("example.iso", "rb+")
iso = ISO.new(stream)

#open the folder our files are in
dir = iso.root["test"]

#open the entries for the source and destination file
source = dir.entry("source.file")
dest = dir.entry("dest.file")

#modify the lba and size of the destination entry to match the source
dest.extent_lba = source.extent_lba
dest.data_length = source.data_length

#write the dest entry back to the ISO
stream.pos = dest.position
#this will only work if we don't modify the length of the entry
#most changes don't modify the entry length, but you can check for changes
#by calling the entry's length method before and after modifying it
dest.dump(stream)