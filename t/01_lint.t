use strict;
use warnings;
use t::TestModPSGI;

return eval_body_app if running_in_mod_psgi;

run_eval_request;

__END__

=== Lint OK
--- request
method: GET
code: |
  require Plack::Lint;
  eval { Plack::Lint->validate_env($env) };
  $@ || 'valid env';
--- response
is_success: ok
content: valid env

