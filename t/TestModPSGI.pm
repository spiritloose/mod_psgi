package t::TestModPSGI;
use strict;
use warnings;
use Test::Base -Base;

use t::Config;
use URI::Escape;
use List::Util qw(sum);
use Test::TCP;
use File::Temp;

our @EXPORT = qw(
    running_in_mod_psgi eval_body_app eval_response_app
    run_server_tests
);

BEGIN {
    no warnings 'redefine';
    *Test::Base::run_compare = sub {}; # XXX
}

sub running_in_mod_psgi() {
    exists $ENV{MOD_PSGI};
}

sub eval_body_app() {
    sub {
        my $env = shift;
        my $code = uri_unescape($env->{QUERY_STRING});
        my $body = eval $code;
        [ 200, [ 'Content-Type' => 'text/plain' ], [ $body ] ];
    };
}

sub eval_response_app() {
    sub {
        my $env = shift;
        my $code = uri_unescape($env->{QUERY_STRING});
        eval $code;
    };
}

our $UA;

sub ua() {
    require LWP::UserAgent;
    $UA ||= LWP::UserAgent->new;
}

sub eval_request($$$;@) {
    my ($port, $method, $code, @args) = @_;
    if (ref $code eq 'CODE') {
        no warnings 'prototype';
        return eval_request($port, $method, $code->(), @args);
    }
    my $uri = sprintf 'http://localhost:%d/?%s', $port, uri_escape($code);
    $method = lc $method;
    ua->$method($uri, @args);
}

sub setup_filters() {
    filters {
        request => 'yaml',
        response => 'yaml',
    };
}

sub setup_plan() {
    plan tests => sum map { scalar keys %{$_->response} } blocks;
}

sub setup_tests() {
    setup_filters;
    setup_plan;
}

sub compare($$$$;@) {
    my ($res, $input, $expected, $name, @args) = @_;
    my $ref = ref $expected;
    if ($ref eq 'CODE') {
        no warnings 'prototype';
        compare($res, $input, $expected->(), $name);
    } elsif ($ref eq 'Regexp') {
        like $res->$input(@args), $expected, $name;
    } elsif ($ref eq 'HASH') {
        while (my ($key, $val) = each %$expected) {
            no warnings 'prototype';
            compare($res, $input, $val, $name, $key);
        }
    } elsif ($ref) {
        is_deeply $res->$input(@args), $expected, $name;
    } elsif ($expected eq 'ok') {
        ok $res->$input(@args), $name;
    } elsif ($expected eq 'not ok') {
        ok !$res->$input(@args), $name;
    } else {
        is $res->$input(@args), $expected, $name;
    }
}

our $TestFile;

sub run_httpd($) {
    my $port = shift;
    my $tmpdir = $ENV{MOD_PSGI_TMP_DIR} || File::Temp::tempdir(CLEANUP => 1);
    my $apxs = $t::Config::APXS;
    chomp(my $libexecdir = `$apxs -q libexecdir`);
    chomp(my $sbindir = `$apxs -q sbindir`);
    chomp(my $progname = `$apxs -q progname`);
    my $httpd = "$sbindir/$progname";
    my $topdir = $t::Config::ABS_TOP_BUILDDIR;
    my $conf = <<"END_CONF";
ServerName mod-psgi.test
LoadModule psgi_module $topdir/.libs/mod_psgi.so
PidFile  $tmpdir/httpd.pid
LockFile $tmpdir/httpd.lock
ErrorLog $tmpdir/error_log
Listen $port
<Location />
  SetHandler psgi
  PSGIApp $topdir/$TestFile
</Location>
END_CONF
    open my $fh, '>', "$tmpdir/httpd.conf" or die $!;
    print $fh $conf;
    close $fh;
    exec "$httpd -X -D FOREGROUND -f $tmpdir/httpd.conf";
}

sub run_requests($) {
    my $port = shift;
    setup_tests;
    run {
        my $block = shift;
        my $req = $block->request;
        my $res = eval_request($port, $req->{method}, $req->{code}, @{$req->{args}});
        my $response = $block->response;
        local $Test::Builder::Level = $Test::Builder::Level + 5;
        while (my ($input, $expected) = each %$response) {
            compare($res, $input, $expected, $block->name);
        }
    };
}

sub run_server_tests() {
    my ($pkg, $file) = caller;
    $TestFile = $file;
    test_tcp(client => \&run_requests, server => \&run_httpd);
}

1;
