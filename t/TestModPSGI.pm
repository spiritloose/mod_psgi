package t::TestModPSGI;
use strict;
use warnings;
use Test::Base -Base;

use File::Basename;
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

sub compare($$$;@) {
    my ($res, $input, $expected, @args) = @_;
    my $ref = ref $expected;
    if ($ref eq 'CODE') {
        no warnings 'prototype';
        compare($res, $input, $expected->());
    } elsif ($ref eq 'Regexp') {
        like $res->$input(@args), $expected;
    } elsif ($ref eq 'HASH') {
        while (my ($key, $val) = each %$expected) {
            no warnings 'prototype';
            compare($res, $input, $val, $key);
        }
    } elsif ($ref) {
        is_deeply $res->$input(@args), $expected;
    } elsif ($expected eq 'ok') {
        ok $res->$input(@args);
    } elsif ($expected eq 'not ok') {
        ok !$res->$input(@args);
    } else {
        is $res->$input(@args), $expected;
    }
}

our $TestFile;

sub run_httpd($) {
    my $port = shift;
    my $tmpdir = $ENV{APACHE2_TMP_DIR} || File::Temp::tempdir(CLEANUP => 1);
    chomp(my $libexecdir = `$ENV{APXS} -q libexecdir`);
    chomp(my $sbindir = `$ENV{APXS} -q sbindir`);
    chomp(my $progname = `$ENV{APXS} -q progname`);
    my $httpd = "$sbindir/$progname";
    my $conf = <<"END_CONF";
LoadModule psgi_module $libexecdir/mod_psgi.so
PidFile  $tmpdir/httpd.pid
LockFile $tmpdir/httpd.lock
ErrorLog $tmpdir/error_log
Listen $port
<Location />
  SetHandler psgi
  PSGIApp $TestFile
</Location>
END_CONF
    open my $fh, '>', "$tmpdir/httpd.conf" or die $!;
    print $fh $conf;
    close $fh;
    exec "$httpd -X -D FOREGROUND -f $tmpdir/httpd.conf";
}

sub run_server_tests() {
    my ($pkg, $file) = caller;
    $TestFile = $file;
    test_tcp(
        client => sub {
            my $port = shift;
            setup_tests;
            run {
                my $block = shift;
                my $req = $block->request;
                my $res = eval_request($port, $req->{method}, $req->{code}, @{$req->{args}});
                my $response = $block->response;
                #local $Test::Builder::Level = $Test::Builder::Level + 3;
                while (my ($input, $expected) = each %$response) {
                    compare($res, $input, $expected);
                }
            };
        },
        server => sub {
            my $port = shift;
            run_httpd($port);
        },
    );
}

1;
