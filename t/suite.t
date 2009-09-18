use strict;
use warnings;

use Test::More;
use Plack::Test::Suite;
use Path::Class;

our $Port = $ENV{PLACK_TEST_SUITE_PORT} || 8080;

$Plack::Test::Suite::BaseDir = do {
    my $dir = do {
        if ($ENV{PLACK_DIR}) {
            dir($ENV{PLACK_DIR})->file('t')->stringify;
        } else {
            my $pmdir = file($INC{'Plack/Test/Suite.pm'})->dir;
            $pmdir->file('..', '..', '..', 't')->resolve->stringify;
        }
    };
    die "Plack test dir 't' not found" unless -e $dir;
    $dir;
};

return \&app if $ENV{MOD_PSGI};
runtests() unless caller;

sub app {
    my $env = shift;
    my $index = $env->{HTTP_X_PLACK_TEST};
    my $test = $Plack::Test::Suite::TEST[$index];
    note $test->[0];
    my $app = $test->[2];
    my $res = $app->($env);
    ok $res;
    done_testing;
    $res;
}

sub runtests {
    require LWP::UserAgent;
    my $ua = LWP::UserAgent->new;
    my $index = 0;
    Plack::Test::Suite->runtests(sub {
        my ($name, $reqgen, $handler, $test) = @_;
        note $name;
        my $req = $reqgen->($Port);
        $req->headers->header('X-Plack-Test' => $index++);
        my $res = $ua->request($req);
        local $Test::Builder::Level = $Test::Builder::Level + 3;
        $test->($res, $Port);
    });
    done_testing;
}

