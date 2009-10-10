use strict;
use warnings;
use t::TestModPSGI;

return eval_body_app if running_in_mod_psgi;

run_server_tests;

__END__

=== Lint OK
--- request
method: GET
code: |
  require Plack::Middleware::Lint;
  eval { Plack::Middleware::Lint->validate_env($env) };
  $@ || 'valid env';
--- response
is_success: ok
content: valid env

