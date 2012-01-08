require "iso9660"

#open the iso image
stream = File.open("example.iso", "rb+")
iso = ISO.new(stream)

#open the folder whose entries we'd like to list
#in this example we are using ISO::Directory's ability to read a subfolder entry
dir = iso.root["folder"]["subfolder"]

#list the entries in "/folder/subfolder"
dir.entries.each do | entry_name |
  puts(entry_name)
end