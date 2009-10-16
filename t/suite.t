use strict;
use warnings;
use Test::More;
use Plack::Test::Suite;
require t::TestModPSGI;

BEGIN {
    no warnings 'once';
    $t::TestModPSGI::TestFile = __FILE__;
    no warnings 'redefine';
    *CalledClose::close = sub {}; # XXX: workaround for TAP syntax error
}

return Plack::Test::Suite->test_app_handler if t::TestModPSGI::running_in_mod_psgi();
Plack::Test::Suite->run_server_tests(\&t::TestModPSGI::run_httpd);
done_testing;
