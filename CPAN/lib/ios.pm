package ios;

=head1 NAME

ios - supporting XS code for iOS and derivatives

=cut

BEGIN {
    if ($^O =~ /darwin-ios/) {
        *CORE::GLOBAL::readpipe = sub {
            my ($code, $result);
            eval {
                ($code, $result) = exec_cli(getcwd(), "@_")
            };
            $code = $code >> 8 if defined $code;
            $? = $code;
            return $result;
        };
    }
}

use strict;
use warnings;
use Config;

require Exporter;
our @ISA = qw(Exporter);
our $VERSION = '0.0.1';

our @methods = (
    'capture_test',
    'exec_perl_capture',
    'exec_perl',
    'exec_test',
    'yield',
    'cat',
);

our @EXPORT = @methods;
our @EXPORT_OK = @methods;

require XSLoader;
XSLoader::load('ios', $VERSION);

# auto-flush on socket
$| = 1;

use open ":std", ":encoding(UTF-8)";
use JSON::PP;
use Data::Dumper;
use Cwd qw(abs_path chdir getcwd);
use Text::ParseWords;

our $DEBUG = 0;

our $capture = 1;

my $json = JSON::PP->new->convert_blessed(1);

sub check_error {
  my ($error) = @_;
  warn "ios error: $error" if $error;
}

sub yield {
  CBYield(shift);
}

# runperl, run_perl - Runs a separate perl interpreter and returns its output.
# Arguments :
#   switches => [ command-line switches ]
#   nolib    => 1 # don't use -I../lib (included by default)
#   non_portable => Don't warn if a one liner contains quotes
#   prog     => one-liner (avoid quotes)
#   progs    => [ multi-liner (avoid quotes) ]
#   progfile => perl script
#   stdin    => string to feed the stdin (or undef to redirect from /dev/null)
#   stderr   => If 'devnull' suppresses stderr, if other TRUE value redirect
#               stderr to stdout
#   args     => [ command-line arguments to the perl program ]
#   verbose  => print the command line

sub exec_perl {
    my ($req) = @_;
    my $runPerl = {
        switches => $req->{switches},
        nolib => $req->{nolib},
        non_portable => $req->{non_portable},
        prog => $req->{prog},
        progs => $req->{progs},
        progfile => $req->{progfile},
        stdin => $req->{stdin},
        stderr => $req->{stderr},
        args => $req->{args},
        verbose => $req->{verbose},
        pwd => $req->{pwd},
    };
    my $exec = $json->utf8->canonical->pretty->encode($runPerl);
    print "\$exec: $exec\n" if $DEBUG;
    my $t = CBRunPerl($exec);
    print "\$t: $t\n" if $DEBUG;
    return int($t);
}

sub exec_perl_capture {
    my ($req) = @_;
    my $runPerl = {
        switches => $req->{switches},
        nolib => $req->{nolib},
        non_portable => $req->{non_portable},
        prog => $req->{prog},
        progs => $req->{progs},
        progfile => $req->{progfile},
        stdin => $req->{stdin},
        stderr => $req->{stderr},
        args => $req->{args},
        verbose => $req->{verbose},
        pwd => $req->{pwd},
    };
    my $exec = $json->utf8->canonical->pretty->encode($runPerl);
    print "exec_perl_capture \$exec: $exec\n" if $DEBUG;
    my ($exit_code, $result);
    local $@;
    eval {
        ($exit_code, $result) = CBRunPerlCaptureStdout($exec);
    };
    print "exec_perl_capture \$result: $result:\n" if ($result && $DEBUG);
    return ($exit_code, $result ? $result : $@);
}

sub parse_test {
    my ($pwd, $t) = @_;
    print Dumper("parse_test pwd", $pwd) if $DEBUG;
    print Dumper("parse_test t", $t) if $DEBUG;

    my ($cmd) = $t =~ s/.*?(perl|harness)["']?\s(.*$)/$2/r;
    print Dumper("cmd", $cmd) if $DEBUG;

    my ($file) = $cmd =~ s/(.*?)([^\s]*)\s*$/$2/r;
    print Dumper("File", $file) if $DEBUG;

    if (! -e "$pwd/$file") {
        warn "parse_test() file not found: $pwd/$file\n";
        return {
            file => undef
        }
    }

    my ($arg) = $t =~ s/(.*?$file)(.*)/$2/r;
    print Dumper("Args", $arg) if $DEBUG;
    my @args = split " ", $arg;

    my ($switch) = $cmd =~ s/(.*?)([^\s]*)\s*$/$1/r;
    my @switches = split " ", $switch;
    print Dumper("Switches:", @switches) if $DEBUG;

    my $result = {
        progfile => $file,
        pwd => $pwd,
        switches => \@switches,
        args => \@args,
    };

    print Dumper("parse_test", $result) if $DEBUG;
    return $result
}

sub parse_cli {
    my ($pwd, $cli) = @_;
    print Dumper("parse_test pwd", $pwd) if $DEBUG;
    print Dumper("parse_test t", $cli) if $DEBUG;
    my ($file, $arg, $switch, $stderr, @args, @switches);

    my ($cmd) = $cli =~ s/[^\s]*(perl|harness)["']?\s*([^\s]+.*$)/$2/r;

    print Dumper("cmd", $cmd) if $DEBUG;

    $stderr = 0;
    $cmd =~ s/2>&1//;

    my $file_index = -1;
    my @cmd_words = &quotewords('\s+', 0, $cmd);
    @cmd_words = grep defined, @cmd_words;
    print Dumper("\@cmd_words", "@cmd_words") if $DEBUG;
    if ($cmd !~ /\-[l]?e['" ]+/) {
        for (my $i = 0; $i < scalar @cmd_words; $i++) {
            print Dumper("trying word", $cmd_words[$i]) if $DEBUG;
            if (-f $cmd_words[$i]) {
                $file = $cmd_words[$i];
                print Dumper("File", $file) if $DEBUG;
                $file_index = $i;
                last;
            }
        }
    }

    if ($file) {
        @args = splice @cmd_words, $file_index +1, @cmd_words -1;
        print Dumper("\@args", @args) if $DEBUG && @switches;
        @switches = splice @cmd_words, 0, $file_index;
        print Dumper("\@switches", @switches) if $DEBUG && @switches;
    } else {
        @switches = @cmd_words;
    }

    @args = grep defined, @args;
    @switches = grep defined, @switches;

    my $result = {
        progfile => $file,
        pwd => $pwd,
        switches => \@switches,
        args => \@args,
    };

    print Dumper("parse_cli", $result) if $DEBUG;
    return $result
}

sub exec_test {
    my ($pwd, $test) = @_;
    die ('Could not chdir to $pwd') if ($pwd && ! chdir $pwd);
    print "Executing: $test\nPWD: $pwd\n" if $DEBUG;
    my $json = parse_test($pwd, $test);
    print  Dumper("json", $json) if $DEBUG;
    my $result;
    local $@;

    if ($capture){
        eval {
            ($result) = exec_perl_capture($json);
        };
        print  Dumper("code", $result->[0]) if $DEBUG;
        print  Dumper("output", $result->[1]) if $DEBUG;
        return ($result->[0], $result->[1] ? $result->[1] : $@);
    } else {
        eval {
            ($result) = exec_perl($json);
        };
        return ($result, "");
    }
}

sub exec_cli {
    my ($pwd, $test) = @_;
    print "Executing: $test\nPWD: $pwd\n" if $DEBUG;
    my $json = parse_cli($pwd, $test);
    print  Dumper("json", $json) if $DEBUG;
    my $result;
    local $@;

    eval {
        ($result) = exec_perl_capture($json);
    };
    print  Dumper("code", $result->[0]) if $DEBUG;
    print  Dumper("output", $result->[1]) if $DEBUG;
    return ($result->[0], $result->[1] ? $result->[1] : $@);
}

sub cat {
    my ($file) = @_;
    open(my $fh, '<:encoding(UTF-8)', $file)
        or die "Could not open file $file  $!";
    my $result;
    while (my $row = <$fh>) {
        $result .= $row;
    }
    close $fh;
    print $result;
}

1;
