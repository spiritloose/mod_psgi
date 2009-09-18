package t::TestModPSGI;
use strict;
use warnings;
use Test::Base -Base;

use File::Basename;
use URI::Escape;
use List::Util qw(sum);

our @EXPORT = qw(
    running_in_mod_psgi eval_body_app eval_response_app
    run_eval_request
);

our $Host = '127.0.0.1';
our $Path = '/psgi/t';

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
    my ($file, $method, $code, @args) = @_;
    if (ref $code eq 'CODE') {
        no warnings 'prototype';
        return eval_request($file, $method, $code->(), @args);
    }
    my $uri = sprintf 'http://%s%s/%s?%s', $Host, $Path,
            basename($file), uri_escape($code);
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

sub run_eval_request() {
    my ($pkg, $file) = caller;
    setup_tests;
    run {
        my $block = shift;
        my $req = $block->request;
        my $res = eval_request($file, $req->{method}, $req->{code},
                @{$req->{args}});
        my $response = $block->response;
        while (my ($input, $expected) = each %$response) {
            compare($res, $input, $expected);
        }
    };
}

1;
