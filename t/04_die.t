use strict;
use warnings;
use t::TestModPSGI;

return eval_body_app if running_in_mod_psgi;

run_server_tests;

__END__

=== app exit but apache process is still running
--- request
method: GET
code: |
  $env->{'psgi.errors'}->print('test exit');
  exit;
--- response
is_success: not ok
code: 500
=== app die but apache process is still running
--- request
method: GET
code: |
  die 'test die';
--- response
is_success: not ok
code: 500

