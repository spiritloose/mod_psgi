#!/usr/bin/env perl
use strict;
use warnings;
use FindBin '$Bin';
use File::Spec;
use lib File::Spec->catfile($Bin, '..');

use t::TestModPSGI;
use Getopt::Long;
use Template;
use Cwd;

main() unless caller;

sub main {
    my $opts = get_opt();
    my $params = make_params();
    render($opts, $params);
}

sub get_opt {
    my $opts = {
        input  => File::Spec->catfile($Bin, 'test.conf.tt'),
        output => File::Spec->catfile($Bin, 'test.conf'),
    };
    GetOptions($opts, 'input=s', 'output=s')
        or die "usage: $0 --input FILE --output FILE";
    $opts;
}

sub chdir_do {
    my ($dir, $code) = @_;
    my $old_cwd = getcwd;
    chdir $dir;
    eval { $code->(); };
    my $err = $@;
    chdir $old_cwd;
    die $err if $err;
}

sub make_params {
    my (@files, $dir);
    chdir_do $Bin => sub {
        push @files, $_ while <[0-9]*.t>;
        $dir = getcwd;
        require 'suite.t';
    };
    no warnings 'once';
    +{
        dir   => $dir,
        files => \@files,
        path  => $t::TestModPSGI::Path,
        port  => $main::Port,
    };
}

sub render {
    my ($opts, $params) = @_;
    my $tt = Template->new(ABSOLUTE => 1);
    $tt->process($opts->{input}, $params, $opts->{output}) or die $tt->error;
}

