use strict;
use warnings;
use lib '.';
use t::TestModPSGI;

return eval_body_app if running_in_mod_psgi;

run_server_tests;

__END__

=== isa
--- request
method: get
code: |
  $env->{'psgi.errors'}->isa('ModPSGI::Errors');
--- response
is_success: ok
content: ok

=== can print
--- request
method: get
code: |
  $env->{'psgi.errors'}->can('print');
--- response
is_success: ok
content: ok

=== print
--- request
method: get
code: |
  $env->{'psgi.errors'}->print('this is test');
--- response
is_success: ok
content: ok

