# BNSC v0.0.4d by Shadowserver SSD Team
#
# usage: bnsc.pl /path/to/config.ini

# sample config.ini (remove all comments):
#
# [target]
# server = "1.1.1.1" ; server ip or hostname
# port = "6667" ; server port
# nick = "foo" ; nick
# user = "foo 0 0 :foo" ; user string
# join = "#bar zoo" ; join string
# password = "secret" ; server password (optional)
#
# [output]
# text = "[MyIRC]" ; text to be prepended to output line
# log = "myirc.log" ; path to log file (append mode)
# alive = "15" ; number of minutes between connection still established messages
#
# [mirror]
# server = "2.2.2.2" ; mirror server ip or hostname
# port = "6667" ; mirror server port
# user = "foo 0 0 :foo: ; user string for mirror
# nick = "me" ; nick
# join = "#mirror" ; join string
# throttle = "2" ; seconds between messages
# password = "secret" ; server password (optional)
#
# Release 'd' fixes a known bug with linefeeds.

use strict;
use IO::Socket;
use IO::Poll 0.04 qw(POLLIN POLLOUT POLLERR POLLHUP);
use Errno qw(EWOULDBLOCK);
use Config::Simple;
use constant MAXBUF => 8192;
use Data::Dumper;
$SIG{PIPE} = 'IGNORE';
my ($to_stdout,$to_socket,$to_log,$to_mirror,$from_mirror,$last_to_mirror,
$stdin_done,$sock_done,$log_done, $mirror_done);

# load config file
my $ini = shift or die "BNSC v0.0.4d - Shadowserver.org Botnet Hunters\nUsage: $0 /path/to/config.ini\n";
tie my %conf, "Config::Simple", $ini;

# connect to target server
my $socket = IO::Socket::INET->new($conf{'target.server'} . ':'
. $conf{'target.port'}) or die $@;

# open log file in append mode
open(LOG, ">>" . $conf{'output.log'}) or
die "Can't write to logfile " . $conf{'output.log'};

my $poll = IO::Poll->new() or die "Can't create IO::Poll object";
my $alive_tell = $conf{'output.alive'} * 60;
my $alive_last = time();
my $stdout_last = "\n";
$poll->mask(\*STDIN => POLLIN);
$poll->mask($socket => POLLIN);
$socket->blocking(0); #turn off blocking on the socket
STDOUT->blocking(0); #and on stdout
LOG->blocking(0); #and the log

# connect to mirror server
my $mirror;
if ($conf{'mirror.server'})
{
$mirror = IO::Socket::INET->new($conf{'mirror.server'} . ':'
. $conf{'mirror.port'}) or die $@;
$mirror->blocking(0);
$poll->mask($mirror => POLLIN);
if ($conf{'mirror.password'})
{
$to_mirror = "PASS " . $conf{'mirror.password'} . "\r\n";
}
$to_mirror .= "NICK " . $conf{'mirror.nick'} . "\r\n" .
"USER " . $conf{'mirror.user'} . "\r\n" .
"JOIN " . $conf{'mirror.join'} . "\r\n";
$conf{'mirror.throttle'} = 1 unless ($conf{'mirror.throttle'} > 1);
}

# text to prepend to each output line
my $text = $conf{'output.text'};
$text .= " " if (length($text));
$text .= "(" . $socket->peerhost() . ':' . $conf{'target.port'} . ") -> ";

# login to server
if ($conf{'target.password'})
{
$to_socket = "PASS " . $conf{'target.password'} . "\r\n";
}

$to_socket .= "NICK " . $conf{'target.nick'} . "\r\n" .
"USER " . $conf{'target.user'} . "\r\n" .
"JOIN " . $conf{'target.join'} . "\r\n" .
"NAMES " . $conf {'target.join'} . "\r\n";


while ($poll->handles) {

$poll->poll;

for my $handle ($poll->handles(POLLIN|POLLHUP|POLLERR)) {
if ($handle eq \*STDIN) {
&stdin_done++ unless sysread(STDIN,$to_socket,2048,length $to_socket);
}

elsif ($handle eq $socket) {
$sock_done++ unless sysread($socket,$to_stdout,2048,length $to_stdout);
}
elsif ($handle eq $mirror) {
$mirror_done++ unless sysread($mirror,$from_mirror,2048,length $from_mirror);
}
}

# handle writers
for my $handle ($poll->handles(POLLOUT|POLLERR))
{
if ($handle eq \*STDOUT)
{
foreach my $line (split /(\n)/, $to_stdout)
{
if ($line =~ /^PING :(.*)$/i)
{
my $id = $1;
my $bytes = syswrite($socket,"PONG :$id\r\n");
unless ($bytes)
{
next if $! == EWOULDBLOCK;
die "write to socket failed: $!";
}
substr($to_stdout,0,length($line)) = '';
$stdout_last = '';

if (time() - $alive_last > $alive_tell)
{

my $timestamp = gmtime time;
$to_stdout .= "* Connection still established " . $timestamp . " *\n";
$alive_last = time();
}
}
else
{
if ($stdout_last =~ /\n/)
{
syswrite (STDOUT, $text);
$to_log .= $text;
if ($mirror)
{
$conf{'mirror.join'} =~ /([^\s,]+)/;
$to_mirror .= "PRIVMSG $1 :" . $text;
}
}

my $bytes = syswrite(STDOUT, $line);
unless ($bytes)
{
next if $! == EWOULDBLOCK;
die "write to stdout failed: $!";
}

if ($mirror)
{
my $tmp = $line;
$tmp =~ s/[^[:print:]\n]//g;
if (length $tmp)
{
$to_mirror .= $tmp;
}
}

$to_log .= $line;
substr($to_stdout,0,$bytes) = '';
$stdout_last = substr($line, length($line) - 1, 1);
}
}
}
elsif ($handle eq $socket)
{
my $bytes = syswrite($socket,$to_socket);
unless ($bytes)
{
next if $! == EWOULDBLOCK;
die "write to socket failed: $!";
}
substr($to_socket,0,$bytes) = '';
}
elsif ($handle eq $mirror)
{
foreach my $line (split /(\n)/, $from_mirror)
{
if ($line =~ /^PING :(.*)$/i)
{
my $id = $1;
my $bytes = syswrite($mirror,"PONG :$id\r\n");
unless ($bytes)
{
next if $! == EWOULDBLOCK;
die "write to socket failed: $!";
}
}
substr($from_mirror,0,length($line)) = '';
}

if (time() - $last_to_mirror > $conf{'mirror.throttle'})
{
if ($to_mirror =~ /^([^\r\n]+[\r\n]+)/)
{
my $line = $1;
my $bytes = syswrite($mirror,$line);
unless ($bytes)
{
next if $! == EWOULDBLOCK;
die "write to socket failed: $!";
}
substr($to_mirror,0,$bytes) = '';
$last_to_mirror = time();
}
else
{
$to_mirror =~ s/^[\r\n]+//;
}
}
}
elsif ($handle eq \*LOG)
{
my $bytes = syswrite(LOG,$to_log);
unless ($bytes)
{
next if $! == EWOULDBLOCK;
die "write to socket failed: $!";
}
substr($to_log,0,$bytes) = '';
}
}

} continue {
my ($outmask,$inmask,$sockmask,$logmask,$mirrormask) = (0,0,0,0,0);

$outmask = POLLOUT if length $to_stdout > 0;
$inmask = POLLIN unless length $to_socket >= MAXBUF
or ($sock_done || $stdin_done);

$sockmask = POLLOUT unless length $to_socket == 0 or $sock_done;
$sockmask |= POLLIN unless length $to_stdout >= MAXBUF or $sock_done;

$logmask = POLLOUT unless length $to_log == 0 or $log_done;

$poll->mask(\*STDIN => $inmask);
$poll->mask(\*STDOUT => $outmask);
$poll->mask($socket => $sockmask);
$poll->mask(\*LOG => $logmask);

if ($conf{'mirror.server'})
{
$mirrormask = POLLOUT unless length $to_mirror == 0 or $mirror_done;
$mirrormask |= POLLIN unless length $from_mirror >= MAXBUF or $mirror_done;

$poll->mask($mirror => $mirrormask);
}

$socket->shutdown(1) if $stdin_done and !length($to_socket);
} 